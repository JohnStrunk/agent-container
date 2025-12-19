#! /bin/bash

set -e -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Get current user's UID and GID to match permissions with host
USER_UID=$(id -u)
USER_GID=$(id -g)

# Auto-detect GCP credentials (same as container version)
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"
GCP_CREDS_PATH="${GCP_CREDENTIALS_PATH:-$GCP_CREDS_DEFAULT}"

# Build terraform variable arguments
TERRAFORM_VARS=(
  -var="user_uid=$USER_UID"
  -var="user_gid=$USER_GID"
)

# Add GCP credentials if file exists
if [[ -f "$GCP_CREDS_PATH" ]]; then
  echo "Auto-detected GCP credentials from: $GCP_CREDS_PATH"
  TERRAFORM_VARS+=(-var="gcp_service_account_key_path=$GCP_CREDS_PATH")

  # Add project ID and region from environment if set
  if [[ -n "$ANTHROPIC_VERTEX_PROJECT_ID" ]]; then
    echo "Using Vertex AI project: $ANTHROPIC_VERTEX_PROJECT_ID"
    TERRAFORM_VARS+=(-var="vertex_project_id=$ANTHROPIC_VERTEX_PROJECT_ID")
  fi

  if [[ -n "$CLOUD_ML_REGION" ]]; then
    echo "Using Vertex AI region: $CLOUD_ML_REGION"
    TERRAFORM_VARS+=(-var="vertex_region=$CLOUD_ML_REGION")
  fi
else
  echo "No GCP credentials found at: $GCP_CREDS_PATH"
  echo "Claude Code in VM will use API key authentication"
  echo "To use Vertex AI, set ANTHROPIC_VERTEX_PROJECT_ID and ensure credentials are available"
fi

# Autodetect network subnet for nested VMs
# If running inside a VM on 192.168.X.0/24, use a different subnet
if [ -z "$NETWORK_SUBNET" ]; then
  # Get the current VM's IP address (if any) on 192.168.x.x
  CURRENT_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.\d+\.\d+(?=/)' | head -1)

  if [ -n "$CURRENT_IP" ]; then
    # Extract third octet from current IP
    CURRENT_THIRD_OCTET=$(echo "$CURRENT_IP" | cut -d. -f3)

    # Use different subnet: if we're on 122 or 123, use 200
    # Otherwise use current + 1 (wrapping at 255)
    if [ "$CURRENT_THIRD_OCTET" -eq 122 ] || [ "$CURRENT_THIRD_OCTET" -eq 123 ]; then
      NETWORK_SUBNET=200
      echo "Detected outer VM network: 192.168.$CURRENT_THIRD_OCTET.0/24"
      echo "Using subnet 192.168.$NETWORK_SUBNET.0/24 for nested VM"
    else
      NETWORK_SUBNET=$(( (CURRENT_THIRD_OCTET + 1) % 256 ))
      echo "Detected outer VM network: 192.168.$CURRENT_THIRD_OCTET.0/24"
      echo "Using subnet 192.168.$NETWORK_SUBNET.0/24 for nested VM"
    fi
  else
    # Not inside a VM on 192.168.x.x, use default
    NETWORK_SUBNET=123
  fi
fi

TERRAFORM_VARS+=(-var="network_subnet_third_octet=$NETWORK_SUBNET")

terraform apply --auto-approve "${TERRAFORM_VARS[@]}"

VM_IP=$(terraform output -raw vm_ip)
ssh-keygen -R "$VM_IP"
