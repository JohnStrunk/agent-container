# Bootc Unification Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Unify container and VM approaches into single bootable container image deployable in both modes.

**Architecture:** Single fedora-bootc:43 Containerfile builds OCI image runnable as container (fast git worktree workflow) or convertible to qcow2 for VM deployment (nested virtualization, full isolation). Smart build scripts auto-detect changes and rebuild only what's needed.

**Tech Stack:** Fedora-bootc:43, Podman, bootc-image-builder, Terraform, libvirt/KVM, cloud-init

---

## Phase 1: Build Core Bootc Infrastructure

### Task 1: Create bootc directory structure

**Files:**
- Create: `bootc/.gitkeep`
- Create: `bootc/homedir/.gitkeep`
- Create: `.build/.gitkeep`

**Step 1: Create bootc directory**

```bash
mkdir -p bootc/homedir
touch bootc/.gitkeep bootc/homedir/.gitkeep
```

**Step 2: Create build artifacts directory**

```bash
mkdir -p .build
touch .build/.gitkeep
```

**Step 3: Update .gitignore**

Add to `.gitignore`:
```
# Build artifacts
.build/
*.qcow2
!.build/.gitkeep

# Terraform state (will move to terraform/ subdir)
terraform/.terraform/
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/.terraform.lock.hcl
terraform/vm-ssh-key
terraform/vm-ssh-key.pub
```

**Step 4: Commit structure**

```bash
git add bootc/ .build/ .gitignore
git commit -m "feat: create bootc directory structure"
```

---

### Task 2: Copy homedir configs to bootc

**Files:**
- Copy: `common/homedir/*` → `bootc/homedir/`

**Step 1: Copy all homedir files**

```bash
cp -r common/homedir/. bootc/homedir/
```

**Step 2: Verify files copied**

```bash
ls -la bootc/homedir/
# Should see .claude.json, .gitconfig, .local/, etc.
```

**Step 3: Commit copied configs**

```bash
git add bootc/homedir/
git commit -m "feat: copy homedir configs to bootc structure"
```

---

### Task 3: Create fedora-bootc Containerfile

**Files:**
- Create: `bootc/Containerfile`

**Step 1: Create base Containerfile**

Create `bootc/Containerfile`:

```dockerfile
FROM quay.io/fedora/fedora-bootc:43

# Version arguments
ARG GOLANG_VERSION=1.25.0
ARG HADOLINT_VERSION=2.12.0

# Install base development packages
RUN dnf install -y \
    # Version control and basics
    git curl wget ca-certificates \
    # Build tools
    gcc gcc-c++ make cmake \
    # CLI tools
    ripgrep jq yq fzf \
    # Shell and utilities
    bash-completion vim-enhanced \
    # Process management
    procps-ng findutils \
    # Security
    gnupg2 \
    && dnf clean all

# Install Node.js and npm
RUN dnf install -y \
    nodejs npm \
    && dnf clean all

# Install Python and tools
RUN dnf install -y \
    python3 python3-pip python3-devel \
    && dnf clean all

# Install Python tools globally
RUN pip install --break-system-packages \
    pipenv \
    poetry \
    pre-commit \
    ruff

# Install uv for Python package management
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    mv /root/.local/bin/uv /usr/local/bin/uv && \
    mv /root/.local/bin/uvx /usr/local/bin/uvx

# Install Go
RUN curl -fsSL https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz -o /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm -f /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# Install hadolint
RUN curl -fsSL https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64 -o /tmp/hadolint && \
    install /tmp/hadolint /usr/local/bin/hadolint && \
    rm -f /tmp/hadolint

# Install HashiCorp repository and Terraform
RUN curl -fsSL https://rpm.releases.hashicorp.com/fedora/hashicorp.repo -o /etc/yum.repos.d/hashicorp.repo && \
    dnf install -y terraform && \
    dnf clean all

# Install AI coding agents
RUN npm install -g \
    @anthropic-ai/claude-code \
    @google/generative-ai-cli

# Copy homedir configs to /etc/skel/
COPY --chown=0:0 --chmod=u=rw,u+X,go=r,go+X homedir/ /etc/skel/

# Copy container entrypoint
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod a+rx /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/bin/bash"]
```

**Step 2: Commit Containerfile**

```bash
git add bootc/Containerfile
git commit -m "feat: create fedora-bootc Containerfile"
```

---

### Task 4: Create container entrypoint script

**Files:**
- Create: `bootc/entrypoint.sh`

**Step 1: Create entrypoint script**

Create `bootc/entrypoint.sh`:

```bash
#!/bin/bash
set -e

# This entrypoint handles container mode (not VM mode)
# It creates a user matching the host UID/GID for file permission compatibility

# Default values
EUID="${EUID:-1000}"
EGID="${EGID:-1000}"
USER="${USER:-user}"
HOME="${HOME:-/home/$USER}"

# Create group if it doesn't exist
if ! getent group "$EGID" > /dev/null 2>&1; then
    groupadd -g "$EGID" "$USER"
fi

# Create user if it doesn't exist
if ! id "$USER" > /dev/null 2>&1; then
    useradd -u "$EUID" -g "$EGID" -d "$HOME" -s /bin/bash -m "$USER"
fi

# Copy skeleton files to user home if not already present
if [ ! -f "$HOME/.claude.json" ]; then
    cp -r /etc/skel/. "$HOME/"
    chown -R "$EUID:$EGID" "$HOME"
fi

# Handle GCP credentials injection (base64 encoded)
if [ -n "$GCP_CREDENTIALS_B64" ]; then
    mkdir -p "$HOME/.config/gcloud"
    echo "$GCP_CREDENTIALS_B64" | base64 -d > "$HOME/.config/gcloud/application_default_credentials.json"
    chown -R "$EUID:$EGID" "$HOME/.config"
    chmod 600 "$HOME/.config/gcloud/application_default_credentials.json"
fi

# Switch to user and execute command
if [ $# -eq 0 ]; then
    exec gosu "$USER" /bin/bash
else
    exec gosu "$USER" "$@"
fi
```

**Step 2: Commit entrypoint**

```bash
git add bootc/entrypoint.sh
git commit -m "feat: create container entrypoint for UID/GID mapping"
```

---

### Task 5: Install gosu for user switching

**Files:**
- Modify: `bootc/Containerfile`

**Step 1: Add gosu installation to Containerfile**

Add after base packages section in `bootc/Containerfile`:

```dockerfile
# Install gosu for user switching in container mode
RUN dnf install -y gosu && dnf clean all
```

Insert this right after the first RUN dnf install block (after line 21).

**Step 2: Commit gosu addition**

```bash
git add bootc/Containerfile
git commit -m "feat: add gosu for container user switching"
```

---

## Phase 2: Container Mode Implementation

### Task 6: Create start-work script with auto-build

**Files:**
- Create: `start-work`

**Step 1: Create start-work script**

Create `start-work`:

```bash
#!/bin/bash
set -e -o pipefail

WORKTREE_BASE_DIR=~/src/worktrees
IMAGE_NAME="ghcr.io/johnstrunk/agent-bootc:latest"
BOOTC_DIR="bootc"

function usage {
    cat - <<EOF
$0: Start using a coding agent on a git worktree (bootc container mode)

Usage: $0 [options] [-b <branch_name>] [command...]

Options:
  -b, --branch <name>         Branch name for git worktree
  --gcp-credentials <path>    Path to GCP service account JSON key file
  -h, --help                  Show this help

Arguments:
  command...                  Optional command to execute in the container

Environment Variables:
  ANTHROPIC_API_KEY          Anthropic API key for Claude
  GEMINI_API_KEY             Google Gemini API key

Examples:
  $0 -b feature-auth                    # Start interactive session
  $0 -b feature-auth -- claude          # Run claude directly
  $0                                    # Use current directory (no git)
EOF
}

# Check if bootc image needs rebuild
needs_bootc_rebuild() {
    # No image exists
    if ! podman image exists "$IMAGE_NAME"; then
        echo "bootc image doesn't exist"
        return 0
    fi

    # Get image creation time
    local image_created=$(podman image inspect "$IMAGE_NAME" \
        --format '{{.Created}}' | xargs -I{} date -d {} +%s 2>/dev/null || echo 0)

    # Check if any source files are newer than image
    local newest_source=$(find "$BOOTC_DIR" -type f -printf '%T@\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d. -f1 || echo 0)

    if [ "$newest_source" -gt "$image_created" ]; then
        echo "source files modified since last build"
        return 0
    fi

    return 1
}

# Build bootc image if needed
build_bootc_image() {
    echo "Building bootc image from $BOOTC_DIR..."
    podman build -t "$IMAGE_NAME" -f "$BOOTC_DIR/Containerfile" "$BOOTC_DIR/"
}

# Parse command line options
BRANCH_NAME=""
CONTAINER_COMMAND=()
USE_GIT=0
GCP_CREDS_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        --gcp-credentials)
            GCP_CREDS_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            CONTAINER_COMMAND=("$@")
            break
            ;;
        *)
            CONTAINER_COMMAND=("$@")
            break
            ;;
    esac
done

# Determine if we should use git worktrees
if [[ -n "$BRANCH_NAME" && -d .git ]]; then
    USE_GIT=1
fi

# Check and build image if needed
if needs_bootc_rebuild; then
    build_bootc_image
fi

# Create the base directory if it doesn't exist
mkdir -p "$WORKTREE_BASE_DIR"

# Setup worktree or use current directory
if [[ "$USE_GIT" == 1 ]]; then
    REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
    WORKTREE_DIR="$WORKTREE_BASE_DIR/${REPO_NAME}-${BRANCH_NAME}"
    CONTAINER_NAME="${REPO_NAME}-${BRANCH_NAME}"

    # Create worktree if it doesn't exist
    if [[ -d "$WORKTREE_DIR" ]]; then
        echo "Worktree for branch '$BRANCH_NAME' already exists at $WORKTREE_DIR."
    else
        if git show-ref --verify --quiet "refs/heads/$BRANCH_NAME"; then
            echo "Adding worktree for existing branch '$BRANCH_NAME'..."
            git worktree add "$WORKTREE_DIR" "$BRANCH_NAME"
        else
            echo "Creating branch '$BRANCH_NAME' from current HEAD and adding worktree..."
            git worktree add -b "$BRANCH_NAME" "$WORKTREE_DIR"
        fi
    fi

    MAIN_REPO_DIR=$(awk '{ print $2 }' "${WORKTREE_DIR}/.git")
    MAIN_REPO_DIR="${MAIN_REPO_DIR%%.git*}"
else
    echo "Using current directory."
    REPO_NAME="$(basename "$(pwd)")"
    WORKTREE_DIR="$(pwd)"
    CONTAINER_NAME="local-$REPO_NAME"
    MAIN_REPO_DIR="$(realpath "$(pwd)")"
fi

# Build mount arguments
MOUNT_ARGS=(
    "-v" "$WORKTREE_DIR:$WORKTREE_DIR:rw"
    "-v" "agent-bootc-cache:$HOME/.cache"
)

# Add main repo mount if using git worktrees
if [[ "$USE_GIT" == 1 ]]; then
    MOUNT_ARGS+=("-v" "$MAIN_REPO_DIR:$MAIN_REPO_DIR:rw")
    echo "Mounting worktree: $WORKTREE_DIR (rw)"
    echo "Mounting main repo: $MAIN_REPO_DIR (rw)"
else
    echo "Mounting current directory: $WORKTREE_DIR (rw)"
fi

# Handle GCP credential injection
CREDENTIAL_ARGS=()
if [[ -n "$GCP_CREDS_PATH" && -f "$GCP_CREDS_PATH" ]]; then
    echo "Injecting GCP credentials from: $GCP_CREDS_PATH"
    GCP_CREDS_B64=$(base64 -w 0 "$GCP_CREDS_PATH")
    CREDENTIAL_ARGS+=("-e" "GCP_CREDENTIALS_B64=$GCP_CREDS_B64")
fi

# Start the container
if [[ ${#CONTAINER_COMMAND[@]} -gt 0 ]]; then
    echo "Starting bootc container on $WORKTREE_DIR and executing: ${CONTAINER_COMMAND[*]}"
else
    echo "Starting bootc container on $WORKTREE_DIR..."
fi

podman run --rm -it \
    --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
    "${MOUNT_ARGS[@]}" \
    -w "$WORKTREE_DIR" \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="$HOME" \
    -e USER="$USER" \
    "${CREDENTIAL_ARGS[@]}" \
    -e GEMINI_API_KEY \
    -e ANTHROPIC_API_KEY \
    -e ANTHROPIC_MODEL \
    -e ANTHROPIC_SMALL_FAST_MODEL \
    -e ANTHROPIC_VERTEX_PROJECT_ID \
    -e CLOUD_ML_REGION \
    -e CLAUDE_CODE_USE_VERTEX \
    "$IMAGE_NAME" "${CONTAINER_COMMAND[@]}"

# Remove the worktree after exiting the container
if [[ "$USE_GIT" == 1 ]]; then
    git worktree remove "$WORKTREE_DIR" || echo "Not removing worktree $(basename "$WORKTREE_DIR"), it may still be in use."
fi
```

**Step 2: Make executable**

```bash
chmod +x start-work
```

**Step 3: Commit start-work**

```bash
git add start-work
git commit -m "feat: create start-work with auto-build detection"
```

---

### Task 7: Test container mode build

**Step 1: Build the bootc image**

```bash
./start-work --help
# Should trigger build and show help
```

Expected output:
```
Building bootc image from bootc...
[build output]
Usage: ./start-work [options]...
```

**Step 2: Test container run with current directory**

```bash
./start-work
```

Expected: Drops into bash shell in container, current directory mounted.

**Step 3: Verify user mapping**

Inside container:
```bash
id
# Should show UID/GID matching host
touch test-file
exit
```

Outside container:
```bash
ls -l test-file
# Should be owned by your user
rm test-file
```

**Step 4: Document test results**

If successful, no commit needed. If issues found, fix and commit.

---

## Phase 3: VM Mode Implementation

### Task 8: Create terraform subdirectory

**Files:**
- Create: `terraform/.gitkeep`

**Step 1: Create terraform directory**

```bash
mkdir -p terraform
touch terraform/.gitkeep
```

**Step 2: Move VM terraform files**

```bash
git mv vm/main.tf terraform/
git mv vm/variables.tf terraform/
git mv vm/outputs.tf terraform/
git mv vm/cloud-init.yaml.tftpl terraform/
```

**Step 3: Commit terraform reorganization**

```bash
git add terraform/
git commit -m "refactor: move terraform files to terraform/ subdir"
```

---

### Task 9: Update terraform to use bootc qcow2

**Files:**
- Modify: `terraform/main.tf`

**Step 1: Replace Debian cloud image with local qcow2**

In `terraform/main.tf`, replace the `libvirt_volume.debian_base` resource (lines 99-115):

```hcl
# Use bootc-generated qcow2 as base image
resource "libvirt_volume" "bootc_base" {
  name = "bootc-base.qcow2"
  pool = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = "file://${abspath(path.module)}/../.build/disk.qcow2"
    }
  }
}
```

**Step 2: Update disk to use bootc base**

In `terraform/main.tf`, update `libvirt_volume.debian_disk` (line 130):

```hcl
  backing_store = {
    path = libvirt_volume.bootc_base.path
    format = {
      type = "qcow2"
    }
  }
```

**Step 3: Commit terraform updates**

```bash
git add terraform/main.tf
git commit -m "feat: update terraform to use bootc qcow2 image"
```

---

### Task 10: Simplify cloud-init for bootc

**Files:**
- Modify: `terraform/cloud-init.yaml.tftpl`

**Step 1: Remove package installation from cloud-init**

The bootc image has all packages pre-installed. Update `terraform/cloud-init.yaml.tftpl`:

Remove the entire `packages:` section (lines 151-167).

Remove `package_update: true` and `package_upgrade: true` (lines 148-149).

Remove the npm/python/go installation runcmd entries (lines 115-135).

**Step 2: Keep only user setup and runtime config**

The cloud-init should only:
- Create users with correct UID/GID
- Configure SSH keys
- Set up GCP credentials if provided
- Configure workspace directory

**Step 3: Update cloud-init template**

Replace `terraform/cloud-init.yaml.tftpl` with:

```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local
manage_etc_hosts: true

write_files:
%{ if gcp_service_account_key != "" ~}
  - path: /etc/google/application_default_credentials.json
    permissions: '0644'
    content: |
      ${indent(6, gcp_service_account_key)}
%{ endif ~}

users:
  - name: ${default_user}
    uid: ${user_uid}
    shell: /bin/bash
    sudo:
      - "ALL=(ALL) NOPASSWD: /usr/bin/dnf"
      - "ALL=(ALL) NOPASSWD: /usr/bin/rpm"
      - "ALL=(ALL) NOPASSWD: /usr/bin/systemctl"
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - ${key}
%{ endfor ~}
  - name: root
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - ${key}
%{ endfor ~}

ssh_pwauth: false
disable_root: false

runcmd:
  # Fix user's primary group to match host GID
  - groupmod -g ${user_gid} ${default_user}
  - usermod -g ${user_gid} ${default_user}
  # Add user to docker group
  - usermod -aG docker ${default_user}
  # Add user to libvirt and kvm groups
  - usermod -aG libvirt ${default_user}
  - usermod -aG kvm ${default_user}
  # Initialize libvirt default storage pool
  - mkdir -p /var/lib/libvirt/images
  - chmod 755 /var/lib/libvirt/images
  - virsh --connect qemu:///system pool-define-as default dir --target /var/lib/libvirt/images
  - virsh --connect qemu:///system pool-build default
  - virsh --connect qemu:///system pool-start default
  - virsh --connect qemu:///system pool-autostart default
  # Fix AppArmor for terraform-provider-libvirt
  - |
    cat > /etc/apparmor.d/libvirt/TEMPLATE.qemu <<'APPARMOR_EOF'
    #include <tunables/global>
    profile LIBVIRT_TEMPLATE flags=(attach_disconnected) {
      #include <abstractions/libvirt-qemu>
      /var/lib/libvirt/images/*.qcow2 rwk,
      /var/lib/libvirt/images/*.img rwk,
      /var/lib/libvirt/images/*.iso rwk,
    }
    APPARMOR_EOF
  - systemctl restart libvirtd
  - virsh --connect qemu:///system net-undefine default 2>/dev/null || true
%{ if gcp_service_account_key != "" ~}
  # Configure GCP environment variables
  - |
    cat > /etc/profile.d/gcp-ai-agent.sh <<EOF
    export GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json
    export ANTHROPIC_VERTEX_PROJECT_ID="${vertex_project_id}"
    export CLOUD_ML_REGION="${vertex_region}"
    export CLAUDE_CODE_USE_VERTEX="true"
    EOF
  - chmod 644 /etc/profile.d/gcp-ai-agent.sh
%{ endif ~}
  # Create workspace directory
  - mkdir -p /home/${default_user}/workspace
  - chown -R ${user_uid}:${user_gid} /home/${default_user}/workspace
  - chmod 755 /home/${default_user}/workspace

final_message: "Bootc VM ready. All packages pre-installed."
```

**Step 4: Commit simplified cloud-init**

```bash
git add terraform/cloud-init.yaml.tftpl
git commit -m "feat: simplify cloud-init for bootc (packages pre-installed)"
```

---

### Task 11: Remove unused cloud-init template variables

**Files:**
- Modify: `terraform/main.tf`

**Step 1: Remove package list variables from cloud-init call**

In `terraform/main.tf`, update `libvirt_cloudinit_disk.cloud_init` resource (around line 138-156):

Remove these template variables:
- `homedir_files`
- `apt_packages`
- `npm_packages`
- `python_packages`
- `golang_version`
- `hadolint_version`

Keep only:
- `hostname`
- `default_user`
- `user_uid`
- `user_gid`
- `ssh_keys`
- `gcp_service_account_key`
- `vertex_project_id`
- `vertex_region`

Updated resource:

```hcl
resource "libvirt_cloudinit_disk" "cloud_init" {
  name = "${var.vm_name}-cloud-init.iso"

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname                = var.vm_hostname
    default_user            = var.default_user
    user_uid                = var.user_uid
    user_gid                = var.user_gid
    ssh_keys                = local.ssh_keys
    gcp_service_account_key = local.gcp_service_account_key
    vertex_project_id       = var.vertex_project_id
    vertex_region           = var.vertex_region
  })

  meta_data = <<-EOF
    instance-id: ${var.vm_name}
    local-hostname: ${var.vm_hostname}
  EOF
}
```

**Step 2: Remove unused locals**

In `terraform/main.tf`, remove the `locals` block that reads package files and homedir (lines 42-70). Keep only:

```hcl
locals {
  ssh_keys = [tls_private_key.vm_ssh_key.public_key_openssh]
  gcp_service_account_key = var.gcp_service_account_key_path != "" ? file(var.gcp_service_account_key_path) : ""
}
```

**Step 3: Commit terraform cleanup**

```bash
git add terraform/main.tf
git commit -m "refactor: remove package installation from terraform"
```

---

### Task 12: Create vm-up.sh with auto-build

**Files:**
- Create: `vm-up.sh`

**Step 1: Create vm-up.sh script**

Create `vm-up.sh`:

```bash
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
  --gcp-credentials <path>    Path to GCP service account JSON key file
  -h, --help                  Show this help

The script will:
1. Build bootc image if source files changed
2. Generate qcow2 disk if bootc image updated
3. Apply terraform to launch VM

EOF
}

# Check if bootc image needs rebuild
needs_bootc_rebuild() {
    if ! podman image exists "$IMAGE_NAME"; then
        echo "bootc image doesn't exist"
        return 0
    fi

    local image_created=$(podman image inspect "$IMAGE_NAME" \
        --format '{{.Created}}' | xargs -I{} date -d {} +%s 2>/dev/null || echo 0)

    local newest_source=$(find "$BOOTC_DIR" -type f -printf '%T@\n' 2>/dev/null \
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

    local qcow2_time=$(stat -c %Y "$QCOW2_PATH")

    local image_created=$(podman image inspect "$IMAGE_NAME" \
        --format '{{.Created}}' | xargs -I{} date -d {} +%s 2>/dev/null || echo 0)

    if [ "$image_created" -gt "$qcow2_time" ]; then
        echo "bootc image updated"
        return 0
    fi

    return 1
}

# Parse arguments
GCP_CREDS_PATH=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --gcp-credentials)
            GCP_CREDS_PATH="$2"
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
    podman build -t "$IMAGE_NAME" -f "$BOOTC_DIR/Containerfile" "$BOOTC_DIR/"
    # Force qcow2 rebuild since image changed
    rm -f "$QCOW2_PATH"
fi

# Step 2: Generate qcow2 if needed
if needs_qcow2_rebuild; then
    echo "Generating VM disk image from bootc container..."
    podman run --rm --privileged \
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

# Handle GCP credentials
if [[ -z "$GCP_CREDS_PATH" ]]; then
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi

TFVARS=""
if [[ -f "$GCP_CREDS_PATH" ]]; then
    echo "Using GCP credentials from: $GCP_CREDS_PATH"
    TFVARS="-var gcp_service_account_key_path=$GCP_CREDS_PATH"
fi

# Step 4: Apply terraform
echo "Checking terraform plan..."
if ! terraform plan -detailed-exitcode $TFVARS > /dev/null 2>&1; then
    echo "Applying terraform changes..."
    terraform apply -auto-approve $TFVARS
else
    echo "No terraform changes needed, VM already up-to-date"
fi

cd ..

echo ""
echo "VM ready! Connect with: ./vm-connect.sh"
```

**Step 2: Make executable**

```bash
chmod +x vm-up.sh
```

**Step 3: Commit vm-up.sh**

```bash
git add vm-up.sh
git commit -m "feat: create vm-up.sh with auto-build pipeline"
```

---

### Task 13: Move VM utility scripts to top level

**Files:**
- Move: `vm/vm-*.sh` → `/`
- Move: `vm/vm-common.sh` → `/`

**Step 1: Move all vm scripts**

```bash
git mv vm/vm-connect.sh ./
git mv vm/vm-down.sh ./
git mv vm/vm-common.sh ./
git mv vm/vm-git-push ./
git mv vm/vm-git-fetch ./
git mv vm/vm-dir-push ./
git mv vm/vm-dir-pull ./
```

**Step 2: Update script paths to reference terraform/**

In each moved script, update references to find terraform outputs.

In `vm-common.sh`, change:
```bash
# Old
SCRIPT_DIR="$1"
# to
# New
SCRIPT_DIR="${1:-terraform}"
```

**Step 3: Test script moves**

```bash
./vm-connect.sh --help
# Should show help
```

**Step 4: Commit moved scripts**

```bash
git add vm-*.sh
git commit -m "refactor: move VM scripts to top level"
```

---

### Task 14: Update vm scripts terraform directory references

**Files:**
- Modify: `vm-connect.sh`
- Modify: `vm-down.sh`
- Modify: `vm-git-push`
- Modify: `vm-git-fetch`
- Modify: `vm-dir-push`
- Modify: `vm-dir-pull`

**Step 1: Update vm-connect.sh**

Change the SCRIPT_DIR line near the top:

```bash
# Old
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# New
SCRIPT_DIR="terraform"
```

**Step 2: Update vm-down.sh**

Same change as vm-connect.sh.

**Step 3: Update vm-git-* and vm-dir-* scripts**

Same change for all remaining scripts.

**Step 4: Commit script updates**

```bash
git add vm-*.sh
git commit -m "fix: update vm scripts to use terraform/ directory"
```

---

## Phase 4: Documentation and Cleanup

### Task 15: Create unified CLAUDE.md

**Files:**
- Create: `CLAUDE.md` (new unified version)

**Step 1: Write unified CLAUDE.md**

Create `CLAUDE.md`:

```markdown
# Claude Code Assistant Configuration - Bootc Unified

## Project Overview

This repository provides a **unified bootable container (bootc)** approach for
creating isolated AI development environments. A single bootc image can be
deployed in two modes:

1. **Container mode** - Fast startup with git worktrees
2. **VM mode** - Full isolation with nested virtualization and Docker

## Key Technologies

- **Base Image:** Fedora-bootc:43
- **Container Runtime:** Podman
- **VM Infrastructure:** Terraform + libvirt/KVM
- **Build Tool:** bootc-image-builder
- **AI Agents:** Claude Code, Gemini CLI

## Quick Start

### Container Mode (Fast)

```bash
# Start interactive session with git worktree
./start-work -b feature-branch

# Use current directory
./start-work
```

### VM Mode (Full Isolation)

```bash
# Launch VM (auto-builds everything)
./vm-up.sh

# Connect to VM
./vm-connect.sh

# Destroy VM
./vm-down.sh
```

## Architecture

### Single Image, Two Modes

```
bootc/Containerfile ──> bootc image ──┬──> Container (podman run)
                                      └──> qcow2 ──> VM (libvirt)
```

**Container mode:**
- Direct podman run of bootc image
- Git worktree workflow for isolated branches
- Fast startup, no VM overhead
- Read-only root, writable /var and /etc
- No Docker or nested virtualization

**VM mode:**
- Convert bootc image to qcow2 disk with bootc-image-builder
- Launch KVM/libvirt VM via Terraform
- Full OS with nested virtualization (host-passthrough CPU)
- Docker and libvirt available inside
- Runtime package installation via `sudo dnf install`

### Directory Structure

```
/
├── start-work              # Container mode launcher
├── vm-up.sh               # VM mode launcher (auto-build)
├── vm-down.sh             # Destroy VM
├── vm-connect.sh          # SSH to VM
├── vm-git-push            # Push git branch to VM
├── vm-git-fetch           # Fetch git branch from VM
├── vm-dir-push            # Rsync directory to VM
├── vm-dir-pull            # Rsync directory from VM
├── vm-common.sh           # Shared VM functions
├── CLAUDE.md              # This file
├── bootc/                 # Build inputs
│   ├── Containerfile      # Single source of truth
│   ├── entrypoint.sh      # Container mode startup
│   └── homedir/           # Configs copied to /etc/skel/
└── terraform/             # VM infrastructure
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── cloud-init.yaml.tftpl
```

## Development Workflow

### Container Mode Workflow

```bash
# Automatic build and run
./start-work -b my-feature

# Inside container
git status
# work on code
exit

# Changes preserved in git worktree
```

### VM Mode Workflow

```bash
# 1. Launch VM (builds bootc image + qcow2 if needed)
./vm-up.sh

# 2. Push your work to VM
./vm-git-push my-feature

# 3. Connect and work
./vm-connect.sh
# Inside VM: cd ~/workspace, work on code

# 4. Pull changes back
./vm-git-fetch my-feature

# 5. Cleanup
./vm-down.sh
```

## Smart Build System

Scripts automatically detect changes and rebuild only what's needed:

```
bootc/Containerfile changed → rebuild bootc image → regenerate qcow2 → update VM
terraform/*.tf changed → reapply terraform
No changes → skip rebuilds
```

**Change detection:**
- Compares file timestamps to built artifact creation times
- Cascading rebuilds (Containerfile → image → qcow2 → VM)
- Terraform plan diff detection

## Modifying the Environment

### Adding Packages

**Edit:** `bootc/Containerfile`

```dockerfile
RUN dnf install -y \
    postgresql-client \
    redis
```

**Apply:**
- Container mode: `./start-work` (auto-rebuilds)
- VM mode: `./vm-up.sh` (auto-rebuilds)

### Adding Homedir Configs

**Add files to:** `bootc/homedir/`

Files are copied to `/etc/skel/` and then to user home directory.

### Runtime Package Installation (VM Only)

Inside running VM:

```bash
sudo dnf install postgresql-server
# Persists across reboots (bootc layering)
```

## VM File Transfer

### Git-based transfer

```bash
# Push branch to VM
./vm-git-push feature-auth

# Fetch branch from VM
./vm-git-fetch feature-auth
```

### Directory-based transfer

```bash
# Push directory to VM workspace
./vm-dir-push ./my-project

# Pull directory from VM workspace
./vm-dir-pull ./my-project
```

## Testing and Quality

### Pre-commit Hooks

```bash
# Run before committing
pre-commit run --all-files
```

### Testing Changes

**Container mode:**
```bash
./start-work
# Test functionality inside container
```

**VM mode:**
```bash
./vm-up.sh
./vm-connect.sh
# Test inside VM
```

## Security Model

### Container Mode Isolation

**Agent can access:**
- Workspace directory (read-write)
- Main git repository (read-write)
- Cache volume (shared)

**Agent cannot access:**
- Host filesystem outside workspace
- Docker socket
- Host credentials

### VM Mode Isolation

**Agent can access:**
- Full VM filesystem
- Docker inside VM
- Nested virtualization

**Agent cannot access:**
- Host filesystem (use vm-dir-* for transfers)
- Host Docker
- Host credentials (injected via cloud-init if provided)

## Troubleshooting

### Rebuild from scratch

```bash
# Container mode
podman rmi ghcr.io/johnstrunk/agent-bootc:latest
./start-work

# VM mode
rm -rf .build/
./vm-down.sh
./vm-up.sh
```

### VM won't start

```bash
cd terraform
terraform destroy -auto-approve
cd ..
./vm-up.sh
```

### Check build artifacts

```bash
# Check bootc image
podman images | grep agent-bootc

# Check qcow2
ls -lh .build/disk.qcow2
```

## Benefits of Unified Approach

- **Consistency** - Same packages, configs, tools in both modes
- **Faster VM boot** - Pre-installed packages (no cloud-init installs)
- **Atomic updates** - `bootc upgrade` for reproducible VM state
- **Simpler maintenance** - One Containerfile vs two build processes
- **Flexibility** - Choose deployment mode per use case
```

**Step 2: Commit unified CLAUDE.md**

```bash
git add CLAUDE.md
git commit -m "docs: create unified bootc CLAUDE.md"
```

---

### Task 16: Update root README if it exists

**Files:**
- Modify: `README.md` (if exists)

**Step 1: Check if README.md exists**

```bash
ls README.md
```

**Step 2: Update README to point to CLAUDE.md**

If README.md exists, update it to reference the unified approach:

```markdown
# Agent Development Environment

Unified bootable container (bootc) environment for AI coding agents.

**See [CLAUDE.md](CLAUDE.md) for complete documentation.**

## Quick Start

Container mode (fast):
```bash
./start-work -b my-branch
```

VM mode (isolated):
```bash
./vm-up.sh
./vm-connect.sh
```
```

**Step 3: Commit README updates**

```bash
git add README.md
git commit -m "docs: update README for unified bootc approach"
```

---

### Task 17: Remove old container/ and vm/ directories

**Files:**
- Remove: `container/`
- Remove: `vm/`
- Remove: `common/`

**Step 1: Verify all files migrated**

```bash
# Check nothing important left
ls container/
ls vm/
ls common/
```

**Step 2: Remove old directories**

```bash
git rm -r container/
git rm -r vm/
git rm -r common/
```

**Step 3: Commit removal**

```bash
git commit -m "refactor: remove old container/ vm/ common/ directories"
```

---

### Task 18: Update .gitignore for bootc

**Files:**
- Modify: `.gitignore`

**Step 1: Review current .gitignore**

```bash
cat .gitignore
```

**Step 2: Ensure bootc-specific ignores present**

Add if missing:

```
# Build artifacts
.build/
!.build/.gitkeep
*.qcow2

# Terraform state
terraform/.terraform/
terraform/terraform.tfstate
terraform/terraform.tfstate.backup
terraform/.terraform.lock.hcl
terraform/vm-ssh-key
terraform/vm-ssh-key.pub

# Cache volumes
agent-bootc-cache/
```

**Step 3: Commit .gitignore**

```bash
git add .gitignore
git commit -m "chore: update .gitignore for bootc structure"
```

---

### Task 19: Update pre-commit config if needed

**Files:**
- Check: `.pre-commit-config.yaml`

**Step 1: Review pre-commit config**

```bash
cat .pre-commit-config.yaml
```

**Step 2: Verify paths still correct**

Check that pre-commit hooks still apply to relevant files:
- Shell scripts now in top level (vm-*.sh, start-work)
- Containerfile in bootc/
- Terraform in terraform/

**Step 3: Update if needed and commit**

If changes needed:
```bash
git add .pre-commit-config.yaml
git commit -m "chore: update pre-commit paths for bootc structure"
```

---

### Task 20: Run pre-commit on all files

**Step 1: Install pre-commit hooks**

```bash
pre-commit install
```

**Step 2: Run pre-commit on all files**

```bash
pre-commit run --all-files
```

**Step 3: Fix any issues found**

Address any pre-commit failures:
- Markdown formatting
- Shell script issues
- Trailing whitespace
- File endings

**Step 4: Commit fixes**

```bash
git add .
git commit -m "fix: address pre-commit issues"
```

---

### Task 21: Test full container mode workflow

**Step 1: Test container mode with worktree**

```bash
./start-work -b test-bootc-container
```

Expected:
- Builds bootc image if not present
- Creates git worktree
- Drops into container shell

**Step 2: Verify environment inside container**

Inside container:
```bash
# Check user
id
whoami

# Check configs
cat ~/.claude.json
ls ~/.local/bin/start-claude

# Check tools
which git node python3 go terraform
go version
node --version
python3 --version

# Test git
git status
```

**Step 3: Exit and verify cleanup**

```bash
exit
```

Outside container:
```bash
# Worktree should be removed automatically
git worktree list
```

**Step 4: Document any issues**

If issues found, create fixes and commit. Otherwise, no action needed.

---

### Task 22: Test full VM mode workflow

**Step 1: Launch VM**

```bash
./vm-up.sh
```

Expected:
- Builds bootc image if not present
- Generates qcow2 if not present
- Applies terraform
- VM boots in <1 minute

**Step 2: Connect to VM**

```bash
./vm-connect.sh
```

**Step 3: Verify VM environment**

Inside VM:
```bash
# Check user and groups
id
groups
# Should be in docker, libvirt, kvm groups

# Check tools
which git docker terraform libvirt
docker version
virsh version

# Test nested virtualization
cat /proc/cpuinfo | grep vmx
# Should show CPU virtualization flags

# Test Docker
docker run --rm hello-world

# Test package installation
sudo dnf install -y htop
which htop
```

**Step 4: Test file transfer**

Exit VM, then:
```bash
# Create test directory
mkdir /tmp/test-transfer
echo "test" > /tmp/test-transfer/file.txt

# Push to VM
./vm-dir-push /tmp/test-transfer

# Connect and verify
./vm-connect.sh
ls ~/workspace/test-transfer/
cat ~/workspace/test-transfer/file.txt
exit

# Pull back
./vm-dir-pull /tmp/test-transfer-pulled

# Verify
cat /tmp/test-transfer-pulled/file.txt

# Cleanup
rm -rf /tmp/test-transfer /tmp/test-transfer-pulled
```

**Step 5: Destroy VM**

```bash
./vm-down.sh
```

**Step 6: Document any issues**

If issues found, fix and commit. Otherwise, no action needed.

---

### Task 23: Test change detection

**Step 1: Test bootc image rebuild detection**

```bash
# Modify Containerfile
echo "# Test comment" >> bootc/Containerfile

# Run start-work
./start-work
```

Expected: Should detect change and rebuild image.

**Step 2: Test no rebuild when unchanged**

```bash
# Run again without changes
./start-work
```

Expected: Should skip rebuild ("No image rebuild needed" or similar).

**Step 3: Test qcow2 rebuild on image update**

```bash
# Modify Containerfile
echo "# Another test comment" >> bootc/Containerfile

# Run vm-up
./vm-up.sh
```

Expected: Should rebuild both image and qcow2.

**Step 4: Test terraform-only changes**

```bash
# Modify terraform
echo "# Comment" >> terraform/variables.tf

# Run vm-up
./vm-up.sh
```

Expected: Should skip bootc/qcow2 builds, only apply terraform.

**Step 5: Clean up test modifications**

```bash
git checkout bootc/Containerfile terraform/variables.tf
```

**Step 6: Document results**

If issues with change detection, fix and commit. Otherwise complete.

---

### Task 24: Final integration test

**Step 1: Test container → VM workflow**

```bash
# Start in container mode
./start-work -b bootc-final-test

# Inside container, make a change
echo "Test from container" > test-file.txt
git add test-file.txt
git commit -m "test: bootc integration"
exit

# Push to VM
./vm-up.sh
./vm-git-push bootc-final-test

# Verify in VM
./vm-connect.sh
cd ~/workspace
cat test-file.txt
# Should show "Test from container"

# Make VM change
echo "Test from VM" >> test-file.txt
git add test-file.txt
git commit -m "test: vm addition"
exit

# Pull back
./vm-git-fetch bootc-final-test

# Verify locally
git checkout bootc-final-test
cat test-file.txt
# Should show both lines
```

**Step 2: Clean up test**

```bash
git checkout bootc
git branch -D bootc-final-test
git worktree prune
./vm-down.sh
```

**Step 3: Final verification**

```bash
# Verify clean state
git status
git worktree list
```

**Step 4: Success**

If all tests pass, the implementation is complete!

---

## Completion Checklist

After completing all tasks, verify:

- [ ] Bootc image builds successfully from Containerfile
- [ ] Container mode works with start-work script
- [ ] VM mode launches with vm-up.sh
- [ ] Qcow2 generated correctly from bootc image
- [ ] VM supports nested virtualization (Docker works)
- [ ] VM allows runtime package installation (dnf)
- [ ] vm-git-* scripts work for git transfer
- [ ] vm-dir-* scripts work for directory transfer
- [ ] Change detection rebuilds only what's needed
- [ ] Pre-commit hooks pass on all files
- [ ] Documentation complete and accurate
- [ ] Old directories removed (container/, vm/, common/)

## Notes for Implementation

- **Fedora package names**: Some packages may have different names than Debian. Check `dnf search <package>` if installation fails.
- **bootc-image-builder**: Requires privileged mode and may need SELinux disabled (`--security-opt label=disable`).
- **Terraform state**: Currently local. For team use, consider remote backend.
- **Image size**: Expect 3-5GB for bootc image, 2-3GB for qcow2.
- **Build time**: Initial bootc build ~10-15 minutes, qcow2 generation ~5 minutes.
- **VM boot**: First boot ~1 minute with bootc (vs 5-10 min with cloud-init package installs).

## Success Criteria Met

Upon completion:
- Single source of truth (bootc/Containerfile)
- Both deployment modes working
- Automated builds with smart detection
- Clean directory structure
- Complete documentation
- All existing workflows preserved (git worktrees, vm-* scripts)
