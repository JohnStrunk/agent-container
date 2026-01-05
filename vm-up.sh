#!/bin/bash
set -e -o pipefail

IMAGE_NAME="ghcr.io/johnstrunk/agent-bootc:latest"
BOOTC_DIR="bootc"
TERRAFORM_DIR="terraform"
BUILD_DIR=".build"
QCOW2_PATH="$BUILD_DIR/disk.qcow2"
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"

function usage {
    cat - <<EOF
$0: Launch VM from bootc image

Usage: $0 [options]

Options:
  --gcp-credentials <path>       Path to GCP service account JSON key file
                                 (default: ~/.config/gcloud/application_default_credentials.json if exists)
  --vertex-project-id <id>       Google Cloud project ID for Vertex AI
                                 (default: \$ANTHROPIC_VERTEX_PROJECT_ID)
  --vertex-region <region>       Google Cloud region for Vertex AI
                                 (default: \$CLOUD_ML_REGION or us-central1)
  -h, --help                     Show this help

The script will:
1. Build bootc image if source files changed
2. Generate qcow2 disk if bootc image updated
3. Apply terraform to launch VM

If GCP credentials are not provided, defaults to: ~/.config/gcloud/application_default_credentials.json

EOF
}

# Check if bootc image needs rebuild
needs_bootc_rebuild() {
    if ! sudo podman image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
        echo "bootc image doesn't exist"
        return 0
    fi

    local image_created
    image_created=$(sudo podman image inspect "$IMAGE_NAME" \
        --format '{{.Created}}' | xargs -I{} date -d {} +%s 2>/dev/null || echo 0)

    local newest_source
    newest_source=$(find "$BOOTC_DIR" -type f -printf '%T@\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d. -f1 || echo 0)

    if [ "$newest_source" -gt "$image_created" ]; then
        echo "source files modified since last build"
        return 0
    fi

    return 1
}

# Check if qcow2 needs rebuild
needs_qcow2_rebuild() {
    if [ ! -f "$QCOW2_PATH" ]; then
        echo "qcow2 doesn't exist"
        return 0
    fi

    local qcow2_time
    qcow2_time=$(stat -c %Y "$QCOW2_PATH")

    local image_created
    image_created=$(sudo podman image inspect "$IMAGE_NAME" \
        --format '{{.Created}}' | xargs -I{} date -d {} +%s 2>/dev/null || echo 0)

    if [ "$image_created" -gt "$qcow2_time" ]; then
        echo "bootc image updated"
        return 0
    fi

    return 1
}

# Parse arguments with defaults from environment
GCP_CREDS_PATH=""
VERTEX_PROJECT_ID="${ANTHROPIC_VERTEX_PROJECT_ID:-}"
VERTEX_REGION="${CLOUD_ML_REGION:-us-central1}"

while [[ $# -gt 0 ]]; do
    case $1 in
        --gcp-credentials)
            GCP_CREDS_PATH="$2"
            shift 2
            ;;
        --vertex-project-id)
            VERTEX_PROJECT_ID="$2"
            shift 2
            ;;
        --vertex-region)
            VERTEX_REGION="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Create build directory
mkdir -p "$BUILD_DIR"

# Step 1: Build bootc image if needed
if needs_bootc_rebuild; then
    echo "Building bootc image..."
    sudo podman build -t "$IMAGE_NAME" -f "$BOOTC_DIR/Containerfile" "$BOOTC_DIR/"
    # Force qcow2 rebuild since image changed
    rm -f "$QCOW2_PATH"
fi

# Step 2: Generate qcow2 if needed
if needs_qcow2_rebuild; then
    echo "Generating VM disk image from bootc container..."
    sudo podman run --rm --privileged \
        -v /var/lib/containers/storage:/var/lib/containers/storage \
        -v "$PWD/$BUILD_DIR:/output" \
        --security-opt label=disable \
        quay.io/centos-bootc/bootc-image-builder:latest \
        --type qcow2 \
        --output /output \
        "$IMAGE_NAME"

    # bootc-image-builder outputs to qcow2/disk.qcow2
    mv "$BUILD_DIR/qcow2/disk.qcow2" "$QCOW2_PATH"
    rm -rf "$BUILD_DIR/qcow2"
    echo "VM disk image created at $QCOW2_PATH"
fi

# Step 3: Prepare terraform variables
cd "$TERRAFORM_DIR"

# Handle GCP credentials and Vertex AI configuration
if [[ -z "$GCP_CREDS_PATH" ]]; then
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi

TFVARS=()
if [[ -f "$GCP_CREDS_PATH" ]]; then
    echo "Using GCP credentials from: $GCP_CREDS_PATH"
    TFVARS+=("-var" "gcp_service_account_key_path=$GCP_CREDS_PATH")

    # Add Vertex AI configuration if provided
    if [[ -n "$VERTEX_PROJECT_ID" ]]; then
        echo "Configuring Vertex AI: project=$VERTEX_PROJECT_ID, region=$VERTEX_REGION"
        TFVARS+=("-var" "vertex_project_id=$VERTEX_PROJECT_ID")
        TFVARS+=("-var" "vertex_region=$VERTEX_REGION")
    else
        echo "WARNING: GCP credentials provided but --vertex-project-id not set."
        echo "         Claude Code Vertex AI integration will not work without a project ID."
    fi
fi

# Step 4: Apply terraform
echo "Checking terraform plan..."
if ! terraform plan -detailed-exitcode "${TFVARS[@]}" > /dev/null 2>&1; then
    echo "Applying terraform changes..."
    terraform apply -auto-approve "${TFVARS[@]}"
else
    echo "No terraform changes needed, VM already up-to-date"
fi

cd ..

echo ""
echo "VM ready! Connect with: ./vm-connect.sh"
