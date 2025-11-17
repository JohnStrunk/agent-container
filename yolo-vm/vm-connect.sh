#! /bin/bash

set -e -o pipefail

# Parse arguments for root connection flag
CONNECT_AS_ROOT=false
if [[ "$1" == "-r" || "$1" == "--root" ]]; then
  CONNECT_AS_ROOT=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

./vm-up.sh

VM_IP=$(terraform output -raw vm_ip)

if [[ "$CONNECT_AS_ROOT" == "true" ]]; then
  ssh -o StrictHostKeyChecking=no "root@$VM_IP"
else
  VM_USER=$(terraform output -raw default_user)
  ssh -o StrictHostKeyChecking=no "$VM_USER@$VM_IP"
fi
