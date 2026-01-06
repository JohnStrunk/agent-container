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
#   $1 - Script directory (to locate SSH key)
#   $2 - VM IP address
#   $3 - VM user
# Exits: 2 if VM not reachable
check_vm_reachable() {
  local script_dir="$1"
  local vm_ip="$2"
  local vm_user="$3"
  local ssh_key="$script_dir/vm-ssh-key"

  if ! ssh -i "$ssh_key" -o ConnectTimeout=5 -o BatchMode=yes \
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

# Execute SSH command to VM
# Args:
#   $1 - Script directory (to locate SSH key)
#   $2 - VM user
#   $3 - VM IP
#   $@ (remaining) - Command to execute on VM (optional, omit for interactive)
# Returns: SSH command output
# Exits: With SSH exit code
vm_ssh() {
  local script_dir="$1"
  local vm_user="$2"
  local vm_ip="$3"
  shift 3

  local ssh_key="$script_dir/vm-ssh-key"

  ssh -i "$ssh_key" -o StrictHostKeyChecking=no "$vm_user@$vm_ip" "$@"
}

# Get SSH command string for rsync
# Args:
#   $1 - Script directory (to locate SSH key)
# Returns: SSH command string for rsync -e option
get_rsync_ssh_cmd() {
  local script_dir="$1"
  local ssh_key="$script_dir/vm-ssh-key"

  echo "ssh -i $ssh_key -o StrictHostKeyChecking=no"
}

# Check if Terraform workspace exists
# Args:
#   $1 - Workspace name
# Returns: 0 if exists, 1 if not
workspace_exists() {
  local workspace_name="$1"
  terraform workspace list 2>/dev/null | grep -q "^[* ] *${workspace_name}$"
}

# Check if libvirt domain (VM) exists
# Args:
#   $1 - Domain name
# Returns: 0 if exists, 1 if not
vm_domain_exists() {
  local domain_name="$1"
  virsh list --all 2>/dev/null | tail -n +3 | awk '{print $2}' | grep -q "^${domain_name}$"
}

# Check if VM is running
# Args:
#   $1 - Domain name
# Returns: 0 if running, 1 if not
vm_is_running() {
  local domain_name="$1"
  virsh list --state-running 2>/dev/null | tail -n +3 | awk '{print $2}' | grep -q "^${domain_name}$"
}

# Find first available IP in subnet
# Args:
#   $1 - Script directory
#   $2 - Subnet third octet (e.g., 123 for 192.168.123.0/24)
# Returns: Available IP address
# Exits: 1 if no IPs available
find_available_ip() {
  local script_dir="$1"
  local subnet_third_octet="$2"
  local base_ip="192.168.${subnet_third_octet}"
  local start=10
  local end=254

  cd "$script_dir" || exit 1

  # Get current workspace to restore later
  local current_workspace
  current_workspace=$(terraform workspace show 2>/dev/null || echo "default")

  # Get all IPs currently in use from all workspaces
  local used_ips
  used_ips=$(terraform workspace list 2>/dev/null | grep -v default | sed 's/^[* ] *//' | \
    while read -r ws; do
      terraform workspace select "$ws" >/dev/null 2>&1
      terraform output -raw vm_ip 2>/dev/null || true
    done | sort -V)

  # Restore original workspace
  terraform workspace select "$current_workspace" >/dev/null 2>&1

  # Find first gap in IP range
  for ip_last_octet in $(seq $start $end); do
    local candidate_ip="${base_ip}.${ip_last_octet}"
    if ! echo "$used_ips" | grep -q "^${candidate_ip}$"; then
      echo "$candidate_ip"
      return 0
    fi
  done

  # No IPs available
  echo "Error: No available IPs in subnet ${base_ip}.0/24" >&2
  echo "Run: agent-vm --cleanup to remove stopped VMs" >&2
  exit 1
}
