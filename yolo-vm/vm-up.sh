#! /bin/bash

set -e -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Get current user's UID and GID to match permissions with host
USER_UID=$(id -u)
USER_GID=$(id -g)

terraform apply --auto-approve \
  -var="user_uid=$USER_UID" \
  -var="user_gid=$USER_GID"

VM_IP=$(terraform output -raw vm_ip)
ssh-keygen -R "$VM_IP"
