# Dynamic SSH Key Generation for yolo-vm

**Date:** 2025-12-11

**Status:** Approved

## Overview

Replace the static SSH public key storage in the `ssh-keys/` directory with
dynamically generated SSH key pairs managed by Terraform. This improves
security and simplifies the VM lifecycle by creating unique keys per VM
instance.

## Current State

The yolo-vm infrastructure currently:

- Stores SSH public keys in `ssh-keys/` directory
- Reads all `*.pub` files from that directory via Terraform
- Injects these keys into both root and default user accounts via cloud-init
- Relies on SSH's default key discovery for connections

## Goals

- Generate SSH key pairs dynamically when VM is created
- Manage key lifecycle through Terraform (create/destroy)
- Use a single key pair per VM instance
- Remove the `ssh-keys/` directory entirely
- Centralize SSH connection logic in vm-common.sh

## Design

### 1. Terraform Key Generation

**Key Generation with tls_private_key:**

Add a new `tls_private_key` resource to `main.tf`:

```hcl
resource "tls_private_key" "vm_ssh_key" {
  algorithm = "ED25519"
}
```

**Algorithm Choice:** ED25519 provides:

- Better security per byte than RSA
- Faster cryptographic operations
- Smaller key sizes
- Full support in Debian 13 (Trixie)
- Native support in Terraform's tls provider

**Writing Keys to Files:**

Use `local_file` resources to write keys to disk:

```hcl
resource "local_file" "ssh_private_key" {
  content         = tls_private_key.vm_ssh_key.private_key_openssh
  filename        = "${path.module}/vm-ssh-key"
  file_permission = "0600"
}

resource "local_file" "ssh_public_key" {
  content         = tls_private_key.vm_ssh_key.public_key_openssh
  filename        = "${path.module}/vm-ssh-key.pub"
  file_permission = "0644"
}
```

Files created:

- `yolo-vm/vm-ssh-key` (private key, mode 0600)
- `yolo-vm/vm-ssh-key.pub` (public key, mode 0644)

**Cloud-init Integration:**

Replace the current `local.ssh_keys` logic with:

```hcl
locals {
  ssh_keys = [tls_private_key.vm_ssh_key.public_key_openssh]
  # ... other locals remain unchanged
}
```

This removes the `ssh_keys_dir` variable and fileset logic entirely.

**Terraform Provider:**

Add the `tls` provider to the required_providers block:

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}
```

### 2. Centralized SSH Functions

**New vm_ssh Function in vm-common.sh:**

```bash
# Execute SSH command to VM
# Args:
#   $1 - Script directory (to locate SSH key)
#   $2 - VM user
#   $3 - VM IP
#   $@ (remaining) - Command to execute on VM
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
```

**New get_rsync_ssh_cmd Function:**

For scripts using rsync:

```bash
# Get SSH command string for rsync
# Args:
#   $1 - Script directory (to locate SSH key)
# Returns: SSH command string for rsync -e option
get_rsync_ssh_cmd() {
  local script_dir="$1"
  local ssh_key="$script_dir/vm-ssh-key"

  echo "ssh -i $ssh_key -o StrictHostKeyChecking=no"
}
```

**Script Updates:**

All vm-* scripts will use these functions:

- `vm-connect.sh`: Use `vm_ssh` for interactive sessions
- `vm-dir-push`, `vm-dir-pull`: Use `get_rsync_ssh_cmd` for rsync
- `vm-workspace-mount`, `vm-workspace-unmount`: Use `get_rsync_ssh_cmd`
- `vm-git-fetch`, `vm-git-push`: Use `vm_ssh` for git operations
- `check_vm_reachable` in vm-common.sh: Update to use `vm_ssh`

### 3. Cleanup and Migration

**Remove Old Infrastructure:**

1. Delete `ssh-keys/` directory (if exists)
2. Remove `ssh_keys_dir` variable from `variables.tf`
3. Remove `local.ssh_key_files` logic from `main.tf`

**New .gitignore:**

Create `yolo-vm/.gitignore`:

```
# Dynamically generated VM SSH keys
vm-ssh-key
vm-ssh-key.pub
```

**Preserved Functionality:**

- `vm-up.sh` continues to run `ssh-keygen -R "$VM_IP"` to clean old host
  keys from known_hosts (still needed for VM recreations with reused IPs)

### 4. Testing and Verification

**Test Plan:**

1. **Clean slate test:**
   - `terraform destroy` to remove existing VM
   - Remove any leftover key files
   - Run `./vm-up.sh` and verify keys are generated
   - Check key files exist with correct permissions (0600/0644)

2. **Connection test:**
   - Run `./vm-connect.sh` (default user)
   - Run `./vm-connect.sh --root`
   - Verify no password prompts (key auth working)

3. **Script functionality test:**
   - Test `vm-dir-push` and `vm-dir-pull`
   - Test workspace mount/unmount
   - Test git fetch/push operations
   - Verify all SSH operations succeed

4. **Lifecycle test:**
   - Run `terraform destroy` and verify keys are removed
   - Run `terraform apply` and verify new keys are generated
   - Confirm old keys don't work, new keys do

**Expected Behavior:**

- Keys appear after `terraform apply`
- Keys have correct permissions (0600 private, 0644 public)
- Keys are NOT committed to git (gitignore working)
- All SSH-based scripts work without user workflow changes
- Keys disappear after `terraform destroy`

## Benefits

1. **Security:** Unique keys per VM instance
2. **Simplicity:** No manual key management
3. **Lifecycle:** Keys automatically cleaned up on destroy
4. **Maintainability:** Centralized SSH logic in vm-common.sh
5. **Modern crypto:** ED25519 is faster and more secure than RSA

## Migration Impact

**Breaking Changes:**

- Existing VMs created with old keys will need to be recreated
- Any external systems relying on specific SSH keys will break

**User Action Required:**

- Run `terraform destroy && terraform apply` to recreate VM with new keys
- Remove or archive old `ssh-keys/` directory

## Implementation Order

1. Add tls provider to terraform block
2. Add tls_private_key and local_file resources
3. Update locals.ssh_keys to use generated key
4. Remove ssh_keys_dir variable and old fileset logic
5. Add vm_ssh and get_rsync_ssh_cmd functions to vm-common.sh
6. Update all vm-* scripts to use centralized functions
7. Create yolo-vm/.gitignore
8. Remove ssh-keys directory (if exists)
9. Test complete workflow
