#! /bin/bash

set -e -o pipefail

# Parse arguments for root connection flag
CONNECT_AS_ROOT=false
if [[ "$1" == "-r" || "$1" == "--root" ]]; then
  CONNECT_AS_ROOT=true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Source common functions
# shellcheck source=vm-common.sh
# shellcheck disable=SC1091
source "$SCRIPT_DIR/vm-common.sh"

./vm-up.sh

VM_IP=$(cd terraform && terraform output -raw vm_ip)

if [[ "$CONNECT_AS_ROOT" == "true" ]]; then
  vm_ssh "terraform" "root" "$VM_IP"
else
  VM_USER=$(cd terraform && terraform output -raw default_user)
  vm_ssh "terraform" "$VM_USER" "$VM_IP"
fi
