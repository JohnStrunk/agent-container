# Unified VM Workflow Design

**Date:** 2026-01-06

**Status:** Approved

## Overview

Unify the VM workflow to match the container's simple `agent-container [-b branch]`
experience. The new `agent-vm` command will provide seamless multi-VM support
with worktrees, filesystem sharing, and simple reconnection.

## Goals

1. **Simple workflow:** Single command like container's `agent-container`
2. **Multi-VM support:** Run multiple VMs on different branches simultaneously
3. **Host file access:** Edit files on host, build/run in VM (real-time sync)
4. **Easy reconnection:** Open multiple terminals to same VM
5. **Resource flexibility:** Override VM resources at creation time
6. **Safety:** Prevent accidental VM recreation and data loss

## Architecture

### Command Interface

**Single command:** `vm/agent-vm`

**Basic usage:**

```bash
agent-vm -b feature-auth           # Create/connect to VM
agent-vm -b feature-auth -- claude # Run claude directly
agent-vm                           # Use current directory (no git)
```

**VM resource options (creation-time only):**

```bash
agent-vm -b feature-auth --memory 8192 --vcpu 8 --disk 60G
```

**VM management:**

```bash
agent-vm --list                    # List all VMs and status
agent-vm -b feature --stop         # Stop VM
agent-vm -b feature --destroy      # Destroy VM + workspace
agent-vm --cleanup                 # Remove all stopped VMs
```

### Naming Convention

Matches container naming exactly:

```bash
REPO_NAME="$(basename "$(git rev-parse --show-toplevel)")"
WORKTREE_DIR="~/src/worktrees/${REPO_NAME}-${BRANCH_NAME}"
VM_NAME="${REPO_NAME}-${BRANCH_NAME}"
```

**Example:** For repo `agent-container` and branch `feature-auth`:

- Worktree: `~/src/worktrees/agent-container-feature-auth/`
- Container name: `agent-container-feature-auth`
- VM domain name: `agent-container-feature-auth`
- VM hostname: `agent-container-feature-auth`

### Multi-VM Architecture

**Resource isolation:**

1. **Terraform workspaces:** Each VM = one workspace
   - Workspace name: `${VM_NAME}`
   - Enables multiple VMs with isolated state
   - Single `vm/` directory manages all

2. **IP allocation:** Sequential within dynamic subnet
   - Keeps existing subnet detection (nested VM support)
   - Range: `192.168.${SUBNET}.10-254`
   - Finds first unused IP (no collisions)
   - Automatic gap filling when VMs destroyed

3. **SSH keys:** Per-VM keys
   - Path: `vm/.ssh/vm-ssh-key-${VM_NAME}`
   - Prevents key conflicts between VMs

4. **VM lifecycle:**
   - VMs persist after exit (not destroyed like containers)
   - Reconnection reuses existing VM (fast)
   - Manual cleanup via `--destroy` or `--cleanup`

### Filesystem Sharing

**Technology:** virtio-9p (9pfs)

**Two mounts (like container):**

1. **Worktree:** `/worktree` (working directory)
2. **Main repo:** `/mainrepo` (for git commits)

**Terraform configuration:**

```hcl
resource "libvirt_domain" "agent_vm" {
  filesystem {
    source     = var.worktree_path
    target     = "worktree"
    readonly   = false
    accessmode = "mapped"
  }

  filesystem {
    source     = var.main_repo_path
    target     = "mainrepo"
    readonly   = false
    accessmode = "mapped"
  }
}
```

**VM mount (cloud-init):**

```yaml
runcmd:
  - mkdir -p /worktree /mainrepo
  - echo "worktree /worktree 9p trans=virtio,version=9p2000.L,rw,_netdev 0 0" >> /etc/fstab
  - echo "mainrepo /mainrepo 9p trans=virtio,version=9p2000.L,rw,_netdev 0 0" >> /etc/fstab
  - mount -a
```

**Benefits:**

- Real-time sync (no rsync needed)
- Edit on host with IDE, build in VM
- Handles ungraceful shutdown safely
- No manual unmount required
- Permissions already matched (VM uses host UID/GID)

### IP Allocation Algorithm

```bash
find_available_ip() {
  local subnet_third_octet="${1:-123}"  # From existing detection
  local base_ip="192.168.${subnet_third_octet}"
  local start=10
  local end=254

  # Get all IPs currently in use from Terraform workspaces
  local used_ips=$(terraform workspace list | grep -v default | \
    while read -r ws; do
      terraform workspace select "$ws" 2>/dev/null
      terraform output -raw vm_ip 2>/dev/null || true
    done | sort -V)

  # Find first gap in this subnet
  for ip in $(seq $start $end); do
    if ! echo "$used_ips" | grep -q "${base_ip}.${ip}"; then
      echo "${base_ip}.${ip}"
      return
    fi
  done
}
```

**Preserves existing subnet detection:**

- Default: `192.168.123.0/24`
- Nested (from 122/123): `192.168.200.0/24`
- Nested (other): `192.168.(current+1).0/24`

## Implementation Details

### Script Flow

```bash
agent-vm [-b branch] [options] [-- command...]

1. Parse arguments (same as container's agent-container)
2. Determine worktree/VM naming
3. Create/reuse worktree on host
4. Determine Terraform workspace name
5. Check if VM exists (terraform workspace list)
6. If VM doesn't exist:
   - Validate resource options (if provided)
   - Create new workspace
   - Find available IP
   - Run terraform apply with:
     * vm_name=${VM_NAME}
     * worktree_path=${WORKTREE_DIR}
     * main_repo_path=${MAIN_REPO_DIR}
     * vm_ip=${NEXT_AVAILABLE_IP}
     * vm_memory, vm_vcpu, vm_disk (if overridden)
7. If VM exists but stopped:
   - Start with: virsh start ${VM_NAME}
   - Warn if resource options provided (ignored)
8. If VM exists and running:
   - Reuse it
   - Warn if resource options provided (ignored)
9. SSH into VM:
   - Auto-change to /worktree
   - Run command if provided, else interactive shell
10. On exit:
   - VM stays running
   - Worktree remains on host
```

### Safety Mechanisms

**1. Resource option validation:**

```bash
if vm_exists(VM_NAME); then
  if [[ -n "$MEMORY_OVERRIDE" || -n "$VCPU_OVERRIDE" || -n "$DISK_OVERRIDE" ]]; then
    echo "WARNING: VM already exists. Resource options ignored."
    echo "To apply new resources, destroy and recreate:"
    echo "  agent-vm -b $BRANCH_NAME --destroy"
    echo "  agent-vm -b $BRANCH_NAME --memory $MEMORY_OVERRIDE"
  fi
  # Connect to existing VM (ignore resource flags)
fi
```

**2. Prevents accidental recreation**

Resource flags only apply during creation, never trigger rebuild.

### Terraform Changes

**New variables (variables.tf):**

```hcl
variable "worktree_path" {
  description = "Path to host worktree directory"
  type        = string
}

variable "main_repo_path" {
  description = "Path to main git repository"
  type        = string
}

variable "vm_ip" {
  description = "Static IP for this VM"
  type        = string
}
```

**Network resource (main.tf):**

- Shared `libvirt_network` across all VMs
- Name: `agent-vm-network`
- Use `lifecycle { ignore_changes = [name] }` to prevent conflicts

**Static IP assignment (main.tf):**

```hcl
resource "libvirt_domain" "agent_vm" {
  network_interface {
    network_id     = libvirt_network.agent_network.id
    addresses      = [var.vm_ip]
    wait_for_lease = true
  }
}
```

**Cloud-init updates (cloud-init.yaml.tftpl):**

- Add filesystem mounts to `/worktree` and `/mainrepo`
- Remove `~/workspace` creation (not needed)
- Change default directory to `/worktree`

### Error Handling

**1. VM fails to start:**

```bash
if ! wait_for_vm_ready "$VM_IP" 300; then
  echo "ERROR: VM failed to start within 5 minutes"
  ssh -i vm-ssh-key-${VM_NAME} root@${VM_IP} \
    "tail -100 /var/log/cloud-init-output.log"
  exit 1
fi
```

**2. Filesystem mount fails:**

```bash
ssh -i vm-ssh-key-${VM_NAME} user@${VM_IP} \
  "mountpoint -q /worktree && mountpoint -q /mainrepo"
if [ $? -ne 0 ]; then
  echo "ERROR: Filesystem mounts failed"
  exit 1
fi
```

**3. IP exhaustion:**

```bash
if [[ -z "$AVAILABLE_IP" ]]; then
  echo "ERROR: No available IPs in subnet 192.168.${SUBNET}.0/24"
  echo "Run: agent-vm --cleanup to remove stopped VMs"
  exit 1
fi
```

**4. Worktree conflicts:**

```bash
if [[ -d "$WORKTREE_DIR" ]] && ! git worktree list | grep -q "$WORKTREE_DIR"; then
  echo "ERROR: Directory exists but is not a git worktree: $WORKTREE_DIR"
  exit 1
fi
```

**5. Terraform workspace corruption:**

```bash
if workspace_exists && ! virsh_domain_exists; then
  echo "WARNING: Terraform workspace exists but VM is missing"
  echo "Cleaning up workspace and recreating VM..."
  terraform workspace select default
  terraform workspace delete ${VM_NAME}
fi
```

**6. SSH key management:**

```bash
# Per-VM SSH keys: vm/.ssh/vm-ssh-key-${VM_NAME}
# Auto-update known_hosts on IP changes
ssh-keygen -R "$VM_IP" 2>/dev/null || true
```

## Testing Strategy

**1. Integration tests:**

Update `test-integration.sh --vm`:

```bash
test_vm_multi_instance() {
  cd vm/

  # Create first VM
  ./agent-vm -b test-branch-1 -- echo "VM 1 ready"

  # Create second VM (parallel)
  ./agent-vm -b test-branch-2 -- echo "VM 2 ready"

  # Verify both running
  virsh list | grep -q "test-branch-1"
  virsh list | grep -q "test-branch-2"

  # Test reconnection
  ./agent-vm -b test-branch-1 -- echo "Reconnected"

  # Cleanup
  ./agent-vm -b test-branch-1 --destroy
  ./agent-vm -b test-branch-2 --destroy
}
```

**2. Manual testing checklist:**

- Basic workflow with filesystem sync
- Resource customization
- Multi-connection (2+ terminals)
- Git operations via main repo mount
- VM lifecycle (stop/restart/destroy)

**3. Pre-commit checks:**

- `shellcheck` on `agent-vm` script
- `terraform fmt && terraform validate`
- Integration tests before commit

## Migration Path

**Remove old scripts:**

- `vm-up.sh`
- `vm-connect.sh`
- `vm-git-push`
- `vm-git-fetch`
- `vm-dir-push`
- `vm-dir-pull`

**Keep:**

- `vm-down.sh` (becomes `agent-vm --destroy` internally)
- `vm-common.sh` (reuse helper functions)

**Backward compatibility:**

None needed - this is a breaking change but significant UX improvement.

## Benefits

1. **Unified experience:** VM workflow matches container exactly
2. **Multi-VM support:** Work on multiple branches simultaneously
3. **Host file access:** Edit with local IDE, run in VM
4. **Simple reconnection:** Just run same command again
5. **Flexible resources:** Override memory/CPU/disk per VM
6. **Safe:** Prevents accidental data loss from recreation

## Risks and Mitigations

**Risk 1:** 9pfs performance slower than native disk

- **Mitigation:** Only code files shared, builds run on VM disk
- **Mitigation:** Performance adequate for typical development

**Risk 2:** Complex Terraform workspace management

- **Mitigation:** Clear error messages and recovery paths
- **Mitigation:** `--cleanup` command for stuck states

**Risk 3:** IP exhaustion (245 VM limit)

- **Mitigation:** Warning when low, cleanup command
- **Mitigation:** Realistic limit for single-user development

## Future Enhancements

1. **Auto-cleanup:** Destroy VMs idle for N days
2. **VM templates:** Pre-configured resource profiles (small/medium/large)
3. **Snapshot support:** Save/restore VM state
4. **Remote virsh:** Support VMs on remote KVM hosts
