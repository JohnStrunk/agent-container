# agent-vm Troubleshooting Guide

## Common Issues and Solutions

### Terraform Destroy Failed

**Symptom**: `terraform destroy` fails during VM destruction

**Solution**:

```bash
# Inspect the workspace state
terraform workspace select <workspace-name>
terraform state list

# Manually destroy resources
terraform destroy -auto-approve

# If that fails, force delete workspace (may leave orphaned resources)
terraform workspace select default
terraform workspace delete -force <workspace-name>

# Clean up any remaining libvirt resources
virsh destroy <vm-name>
virsh undefine <vm-name>
```

### IP Allocation Lock Timeout

**Symptom**: "Could not acquire IP allocation lock after 30 seconds"

**Cause**: Another agent-vm process is allocating an IP, or previous
process crashed while holding lock

**Solution**:

```bash
# Check for stuck agent-vm processes
ps aux | grep agent-vm

# If no processes running, remove stale lock
rm -f /tmp/agent-vm-ip-allocation.lock
```

### Uncommitted Changes Warning

**Symptom**: `--fetch` reports uncommitted changes and aborts

**Cause**: You have uncommitted work in the VM that hasn't been committed

**Solution**:

```bash
# Connect to VM and commit changes
./agent-vm -b <branch-name>

# In VM:
cd /worktree
git status
git add .
git commit -m "Save work before fetch"
exit

# Now fetch will succeed
./agent-vm -b <branch-name> --fetch
```

### Orphaned Workspace

**Symptom**: Workspace exists but VM is missing

**Cause**: VM was manually destroyed outside of agent-vm

**Solution**:

agent-vm automatically detects this and recreates. If recreation fails:

```bash
# Manual cleanup
terraform workspace select <workspace-name>
terraform destroy -auto-approve
terraform workspace select default
terraform workspace delete <workspace-name>

# Recreate VM
./agent-vm -b <branch-name>
```

### SSHFS Mount Stale

**Symptom**: Cannot access files at `~/.agent-vm-mounts/<repo>-<branch>/`

**Solution**:

```bash
# Force unmount
fusermount -u ~/.agent-vm-mounts/<repo>-<branch>
# or
umount ~/.agent-vm-mounts/<repo>-<branch>

# Reconnect to VM (will remount)
./agent-vm -b <branch-name>
```

### Mount Directories Accumulating

**Symptom**: Many empty directories in `~/.agent-vm-mounts/`

**Cause**: Fixed in 2026-01-07 bug fixes, but old directories may remain

**Solution**:

```bash
# Safe cleanup (only removes empty directories)
find ~/.agent-vm-mounts -type d -empty -delete
```

## Diagnostic Commands

### Check VM Status

```bash
./agent-vm --list                    # List all managed VMs
virsh list --all                     # List all libvirt VMs
terraform workspace list             # List all workspaces
```

### Check Network Configuration

```bash
virsh net-list --all                 # List networks
virsh net-dhcp-leases default        # Show DHCP leases
ip addr show | grep 192.168          # Show host IPs
```

### Check Terraform State

```bash
terraform workspace select <name>
terraform state list                 # Show managed resources
terraform show                       # Show full state
```

### Check for Resource Leaks

```bash
# Orphaned VMs (not managed by terraform)
virsh list --all

# Orphaned workspaces (no corresponding VM)
terraform workspace list

# Orphaned volumes
virsh vol-list default

# Mount directories
ls -la ~/.agent-vm-mounts/
```

## Getting Help

If you encounter issues not covered here:

1. Check the logs: `/var/log/cloud-init-output.log` (in VM)
2. Review recent commits: `git log --oneline -- vm/`
3. Report issue with:
   - Output of `./agent-vm --list`
   - Output of `virsh list --all`
   - Output of `terraform workspace list`
   - Error messages from agent-vm
