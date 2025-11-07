#! /bin/bash

set -e -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

./vm-up.sh

VM_IP=$(terraform output -raw vm_ip)
VM_USER=$(terraform output -raw default_user)
ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP"
