#!/bin/bash
# Common functions for VM workspace sync scripts

# Get the VM IP from terraform output
# Returns: VM IP address
# Exits: 1 if VM IP not available
get_vm_ip() {
  local script_dir="$1"
  cd "$script_dir" || exit 1

  local vm_ip
  vm_ip=$(terraform output -raw vm_ip 2>/dev/null)

  if [[ -z "$vm_ip" || "$vm_ip" == "IP not yet assigned" ]]; then
    echo "Error: VM IP not available" >&2
    echo "Run './vm-up.sh' first to start the VM" >&2
    exit 1
  fi

  echo "$vm_ip"
}

# Get the default VM user from terraform output
# Returns: Username
# Exits: 1 if username not available
get_vm_user() {
  local script_dir="$1"
  cd "$script_dir" || exit 1

  local vm_user
  vm_user=$(terraform output -raw default_user 2>/dev/null)

  if [[ -z "$vm_user" ]]; then
    echo "Error: VM default user not available" >&2
    echo "Run './vm-up.sh' first to start the VM" >&2
    exit 1
  fi

  echo "$vm_user"
}

# Get the workspace path on the VM
# Returns: Absolute path to workspace directory
get_vm_workspace_path() {
  local script_dir="$1"
  local vm_user
  vm_user=$(get_vm_user "$script_dir")

  echo "/home/$vm_user/workspace"
}

# Check if VM is reachable via SSH
# Args:
#   $1 - VM IP address
#   $2 - VM user
# Exits: 2 if VM not reachable
check_vm_reachable() {
  local vm_ip="$1"
  local vm_user="$2"

  if ! ssh -o ConnectTimeout=5 -o BatchMode=yes \
       "$vm_user@$vm_ip" "exit" 2>/dev/null; then
    echo "Error: Cannot connect to VM at $vm_ip" >&2
    echo "Check that VM is running: virsh list" >&2
    exit 2
  fi
}

# Get absolute path of a directory
# Args:
#   $1 - Directory path (relative or absolute)
# Returns: Absolute path
# Exits: 1 if directory doesn't exist
get_absolute_path() {
  local path="$1"

  if [[ ! -d "$path" ]]; then
    echo "Error: Directory '$path' does not exist" >&2
    exit 1
  fi

  cd "$path" && pwd
}
