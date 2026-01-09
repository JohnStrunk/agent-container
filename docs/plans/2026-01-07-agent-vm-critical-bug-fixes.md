# agent-vm Critical Bug Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix 6 critical bugs in agent-vm that risk data loss, resource leaks, and race conditions

**Architecture:** Fix data flow ordering (dirty check before unmount), add file-based locking for IP allocation, add error propagation for cleanup operations, fix subshell variable scoping, add mount directory cleanup

**Tech Stack:** Bash scripting, file locking (flock), Terraform, libvirt, git, SSHFS

**Background:** Code review identified 6 critical issues:
1. SSHFS unmount before dirty check → data loss
2. Concurrent IP allocation → race condition
3. Terraform destroy failures → orphaned resources
4. Workspace recovery → incomplete error handling
5. cleanup_stopped_vms → subshell variable loss
6. Mount directories → accumulation over time

---

## Task 1: Fix Data Loss Risk in fetch_branch_from_vm (CRITICAL)

**Files:**
- Modify: `vm/agent-vm:99-148`

**Issue:** SSHFS unmounts BEFORE checking for uncommitted changes, causing editor buffers to lose unsaved work.

**Step 1: Review current code structure**

Read: `vm/agent-vm` lines 99-148

Current flow:
1. Unmount SSHFS (line 106-112)
2. Check for uncommitted changes (line 117-127)
3. Fetch from VM (line 133-147)

**Step 2: Reorder operations - check dirty state first**

```bash
function fetch_branch_from_vm {
  local vm_ip="$1"
  local branch_name="$2"
  local ssh_key="$SCRIPT_DIR/vm-ssh-key"

  echo "Fetching '$branch_name' from VM..."

  cd "$(git rev-parse --show-toplevel)" || exit 1

  # Check for uncommitted changes in VM FIRST (before unmounting)
  if ssh -i "$ssh_key" -o StrictHostKeyChecking=no "user@$vm_ip" \
     "cd /worktree && ! git diff --quiet || ! git diff --cached --quiet" 2>/dev/null; then
    echo ""
    echo "⚠️  WARNING: VM has uncommitted changes"
    echo ""
    echo "Commit them first:"
    echo "  ./agent-vm -b $branch_name"
    echo "  git commit -am 'Your message'"
    echo ""
    return 1
  fi

  # ONLY AFTER dirty check passes, unmount SSHFS
  local mount_point="$HOME/.agent-vm-mounts/${REPO_NAME}-${branch_name}"
  if mountpoint -q "$mount_point" 2>/dev/null; then
    echo "Unmounting SSHFS..."
    fusermount -u "$mount_point" 2>/dev/null || umount "$mount_point" 2>/dev/null
    sleep 1
  fi

  # Set up SSH key for git
  export GIT_SSH_COMMAND="ssh -i $ssh_key -o StrictHostKeyChecking=no"

  # Fetch branch from VM
  if git fetch "ssh://user@${vm_ip}/worktree" "$branch_name:$branch_name" 2>&1; then
    echo ""
    echo "✓ Branch '$branch_name' updated in main repo"
    echo ""
    echo "To view changes:"
    echo "  git checkout $branch_name"
    echo "  git log"
    echo ""
  else
    echo "Error: Could not fetch from VM"
    unset GIT_SSH_COMMAND
    return 1
  fi

  unset GIT_SSH_COMMAND
}
```

**Step 3: Apply the fix**

Run: `vim vm/agent-vm` and replace lines 99-148 with the corrected function above

Key changes:
- Lines 117-127 (dirty check) moved to lines 107-118 (BEFORE unmount)
- Lines 106-112 (unmount) moved to lines 120-126 (AFTER dirty check)
- Added explanatory comments

**Step 4: Test the fix manually**

```bash
cd vm
./agent-vm -b test-dirty-check -- bash -c "cd /worktree && echo 'test' >> README.md"
./agent-vm -b test-dirty-check --fetch
```

Expected output: WARNING message about uncommitted changes, fetch aborted

**Step 5: Clean up and commit in VM**

```bash
./agent-vm -b test-dirty-check -- bash -c "cd /worktree && git checkout -- README.md"
./agent-vm -b test-dirty-check --destroy
```

**Step 6: Commit the fix**

```bash
git add vm/agent-vm
git commit -m "fix(vm): check for uncommitted changes before unmounting SSHFS

Prevent data loss by checking git dirty state BEFORE unmounting SSHFS.
Previously, unmounting first could cause editors to lose unsaved buffers.

Fixes: Issue #1 - Data loss risk in fetch_branch_from_vm"
```

---

## Task 2: Fix Race Condition in IP Allocation (CRITICAL)

**Files:**
- Modify: `vm/vm-common.sh:145-188`

**Issue:** Two concurrent agent-vm processes can allocate the same IP address.

**Step 1: Review current IP allocation logic**

Read: `vm/vm-common.sh` lines 145-188

Current flow has no locking:
1. Read used IPs from all workspaces
2. Find first available IP
3. Return IP

**Step 2: Add file-based locking with flock**

```bash
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
  local lock_file="/tmp/agent-vm-ip-allocation.lock"

  cd "$script_dir" || exit 1

  # Acquire exclusive lock for IP allocation (prevents race conditions)
  # Lock is automatically released when script exits
  exec 200>"$lock_file"
  if ! flock -x -w 30 200; then
    echo "Error: Could not acquire IP allocation lock after 30 seconds" >&2
    echo "Another agent-vm process may be allocating IPs" >&2
    exit 1
  fi

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
      # Lock released automatically via file descriptor 200
      return 0
    fi
  done

  # No IPs available
  echo "Error: No available IPs in subnet ${base_ip}.0/24" >&2
  echo "Run: agent-vm --cleanup to remove stopped VMs" >&2
  exit 1
}
```

**Step 3: Apply the fix**

Run: `vim vm/vm-common.sh` and replace lines 145-188 with the corrected function above

Key changes:
- Line 155: Add `lock_file` variable
- Lines 160-167: Acquire exclusive lock with flock -x -w 30
- Line 184: Comment noting automatic lock release

**Step 4: Test concurrent IP allocation**

```bash
cd vm

# Start two VM creations in parallel
./agent-vm -b race-test-1 &
PID1=$!
./agent-vm -b race-test-2 &
PID2=$!

# Wait for both to complete
wait $PID1
wait $PID2

# Verify both VMs have different IPs
./agent-vm --list
```

Expected: Both VMs created with different IPs (e.g., 192.168.3.10 and 192.168.3.11)

**Step 5: Clean up test VMs**

```bash
./agent-vm -b race-test-1 --destroy
./agent-vm -b race-test-2 --destroy
```

**Step 6: Commit the fix**

```bash
git add vm/vm-common.sh
git commit -m "fix(vm): add file locking to prevent IP allocation race condition

Use flock to ensure only one agent-vm process allocates IPs at a time.
Prevents concurrent processes from allocating the same IP address.

Lock automatically released when process exits.
30-second timeout with clear error message if lock unavailable.

Fixes: Issue #2 - Race condition in IP allocation"
```

---

## Task 3: Fix Incomplete Error Handling in destroy_vm (CRITICAL)

**Files:**
- Modify: `vm/agent-vm:25-54`

**Issue:** Workspace deleted even if terraform destroy fails, leaving orphaned resources.

**Step 1: Review current destroy_vm logic**

Read: `vm/agent-vm` lines 25-54

Current flow:
1. Stop and destroy domain (lines 38-41)
2. Switch to workspace (line 44)
3. Run terraform destroy (line 46)
4. Delete workspace (lines 49-50) **← Always runs, even if destroy fails**

**Step 2: Add error checking for terraform destroy**

```bash
function destroy_vm {
  local vm_name="$1"
  local workspace_name="$2"

  echo "Destroying VM: $vm_name"

  # Extract branch name from VM name (format: repo-branch)
  local branch_name="${vm_name#*-}"

  # Unmount SSHFS if mounted
  unmount_vm_worktree "$branch_name"

  # Stop and destroy domain if exists
  if vm_domain_exists "$vm_name"; then
    virsh destroy "$vm_name" 2>/dev/null || true
    virsh undefine "$vm_name" 2>/dev/null || true
  fi

  # Switch to workspace and destroy Terraform resources
  if workspace_exists "$workspace_name"; then
    terraform workspace select "$workspace_name" >/dev/null 2>&1

    echo "Destroying Terraform resources..."
    if ! terraform destroy -auto-approve; then
      echo ""
      echo "ERROR: terraform destroy failed"
      echo ""
      echo "Workspace '$workspace_name' preserved for manual inspection."
      echo ""
      echo "To retry:"
      echo "  terraform workspace select $workspace_name"
      echo "  terraform destroy -auto-approve"
      echo "  terraform workspace select default"
      echo "  terraform workspace delete $workspace_name"
      echo ""
      echo "Or force cleanup (may leave orphaned resources):"
      echo "  terraform workspace select default"
      echo "  terraform workspace delete -force $workspace_name"
      echo ""
      return 1
    fi

    # Only delete workspace if destroy succeeded
    terraform workspace select default >/dev/null 2>&1
    terraform workspace delete "$workspace_name"

    # Clean up mount directory
    local mount_point="$HOME/.agent-vm-mounts/${vm_name}"
    if [ -d "$mount_point" ]; then
      rmdir "$mount_point" 2>/dev/null || true
    fi
  fi

  echo "VM destroyed: $vm_name"
}
```

**Step 3: Apply the fix**

Run: `vim vm/agent-vm` and replace lines 25-54 with the corrected function above

Key changes:
- Line 46: Check `if ! terraform destroy -auto-approve; then`
- Lines 47-62: Error message with recovery instructions
- Line 63: `return 1` to propagate error
- Lines 66-67: Workspace deletion ONLY after successful destroy
- Lines 69-73: Added mount directory cleanup (fixes Issue #6)

**Step 4: Test error handling with simulated failure**

Cannot easily test terraform destroy failure without breaking actual infrastructure. Instead, verify error messages are correct:

```bash
# Review the error message text
vim vm/agent-vm +47
```

Expected: Clear recovery instructions visible in lines 47-62

**Step 5: Test successful destroy**

```bash
cd vm
./agent-vm -b destroy-test -- echo "test"
./agent-vm -b destroy-test --destroy
```

Expected: Clean destroy with "VM destroyed: workspace-destroy-test"

**Step 6: Commit the fix**

```bash
git add vm/agent-vm
git commit -m "fix(vm): verify terraform destroy succeeds before deleting workspace

Previously, workspace was deleted even if terraform destroy failed,
causing Terraform to lose track of resources (orphaned VMs).

Now:
- Check terraform destroy exit code
- Preserve workspace if destroy fails
- Provide clear recovery instructions
- Only delete workspace after successful destroy

Also fixes Issue #6 by cleaning up mount directories.

Fixes: Issue #3 - Incomplete cleanup in destroy_vm
Fixes: Issue #6 - SSHFS mount point accumulation"
```

---

## Task 4: Fix Workspace Orphan Recovery (IMPORTANT)

**Files:**
- Modify: `vm/agent-vm:552-560`

**Issue:** When recovering from orphaned workspace (exists but VM missing), destroys without verifying success.

**Step 1: Review current orphan recovery logic**

Read: `vm/agent-vm` lines 552-560

Current flow:
1. Detect workspace exists but VM domain missing (line 552)
2. Run terraform destroy (line 554)
3. Delete workspace (lines 555-556)
4. Fall through to creation (line 559)

**Step 2: Add error checking for orphan recovery**

```bash
  else
    echo "Warning: Workspace exists but VM domain missing. Recreating..."
    # Workspace exists but VM doesn't - clean up and recreate

    echo "Cleaning up orphaned workspace resources..."
    if ! terraform destroy -auto-approve; then
      echo ""
      echo "ERROR: Failed to destroy orphaned workspace resources"
      echo ""
      echo "Manual cleanup required:"
      echo "  terraform workspace select $VM_NAME"
      echo "  terraform state list"
      echo "  terraform destroy -auto-approve"
      echo ""
      echo "Or force deletion (may leave orphaned resources):"
      echo "  terraform workspace select default"
      echo "  terraform workspace delete -force $VM_NAME"
      echo ""
      exit 1
    fi

    terraform workspace select default
    terraform workspace delete "$VM_NAME"

    # Fall through to creation below
    CREATE_NEW_VM=1
  fi
```

**Step 3: Apply the fix**

Run: `vim vm/agent-vm` and replace lines 552-560 with the corrected code above

Key changes:
- Line 554: Changed to `if ! terraform destroy -auto-approve; then`
- Lines 555-569: Error message with recovery instructions
- Line 570: `exit 1` instead of continuing
- Lines 572-573: Workspace deletion ONLY after successful destroy

**Step 4: Test orphan recovery manually**

Create orphaned state:
```bash
cd vm
./agent-vm -b orphan-test -- echo "test"
virsh destroy workspace-orphan-test
virsh undefine workspace-orphan-test
```

Verify recovery:
```bash
./agent-vm -b orphan-test -- echo "recovered"
```

Expected: "Warning: Workspace exists but VM domain missing. Recreating..." followed by successful VM creation

**Step 5: Clean up**

```bash
./agent-vm -b orphan-test --destroy
```

**Step 6: Commit the fix**

```bash
git add vm/agent-vm
git commit -m "fix(vm): verify terraform destroy succeeds in orphan recovery

When workspace exists but VM is missing, verify terraform destroy
succeeds before deleting workspace. Prevents cascading failures.

Provides clear recovery instructions if destroy fails.

Fixes: Issue #4 - Workspace orphan recovery lacks verification"
```

---

## Task 5: Fix cleanup_stopped_vms Subshell Variable Loss (IMPORTANT)

**Files:**
- Modify: `vm/agent-vm:223-255`

**Issue:** Pipe creates subshell, so `cleaned_count` updates are lost. Always reports 0 VMs cleaned.

**Step 1: Review current cleanup_stopped_vms logic**

Read: `vm/agent-vm` lines 223-255

Current flow uses pipe which creates subshell:
```bash
terraform workspace list | while read -r ws; do
  cleaned_count=$((cleaned_count + 1))  # Lost in subshell
done
echo "Cleaned up $cleaned_count stopped VMs."  # Always 0
```

**Step 2: Fix subshell issue with process substitution**

```bash
function cleanup_stopped_vms {
  echo "Cleaning up stopped VMs..."
  local cleaned_count=0

  # Use process substitution instead of pipe to avoid subshell
  # This preserves the cleaned_count variable updates
  while read -r ws; do
    terraform workspace select "$ws" >/dev/null 2>&1

    local vm_name="$ws"

    # Check if VM exists and is stopped
    if vm_domain_exists "$vm_name" && ! vm_is_running "$vm_name"; then
      echo "Destroying stopped VM: $vm_name"
      virsh destroy "$vm_name" 2>/dev/null || true
      virsh undefine "$vm_name" 2>/dev/null || true

      # Destroy Terraform resources
      if ! terraform destroy -auto-approve >/dev/null 2>&1; then
        echo "  WARNING: terraform destroy failed for $vm_name, skipping workspace deletion"
        continue
      fi

      # Switch back and delete workspace (only if destroy succeeded)
      terraform workspace select default >/dev/null 2>&1
      terraform workspace delete "$ws" 2>/dev/null

      # Clean up mount directory
      local mount_point="$HOME/.agent-vm-mounts/${vm_name}"
      if [ -d "$mount_point" ]; then
        rmdir "$mount_point" 2>/dev/null || true
      fi

      cleaned_count=$((cleaned_count + 1))
    fi
  done < <(terraform workspace list 2>/dev/null | grep -v default | sed 's/^[* ] *//')

  # Return to default workspace
  terraform workspace select default >/dev/null 2>&1

  echo "Cleaned up $cleaned_count stopped VMs."
}
```

**Step 3: Apply the fix**

Run: `vim vm/agent-vm` and replace lines 223-255 with the corrected function above

Key changes:
- Line 248: Changed from `| while` to `done < <(...)` (process substitution)
- Lines 241-244: Added error checking for terraform destroy
- Line 245: `continue` instead of incrementing counter if destroy fails
- Lines 252-256: Added mount directory cleanup

**Step 4: Test cleanup function**

Create stopped VMs:
```bash
cd vm
./agent-vm -b cleanup-test-1 -- echo "test1"
./agent-vm -b cleanup-test-2 -- echo "test2"

# Stop them
virsh shutdown workspace-cleanup-test-1
virsh shutdown workspace-cleanup-test-2

# Wait for shutdown
sleep 5
```

Run cleanup:
```bash
./agent-vm --cleanup
```

Expected output: "Cleaned up 2 stopped VMs." (not 0)

**Step 5: Verify cleanup completed**

```bash
./agent-vm --list
virsh list --all
```

Expected: No cleanup-test VMs listed

**Step 6: Commit the fix**

```bash
git add vm/agent-vm
git commit -m "fix(vm): fix cleanup_stopped_vms to correctly count cleaned VMs

Use process substitution instead of pipe to prevent subshell variable loss.
Previously always reported 0 VMs cleaned due to subshell scoping.

Also adds:
- Error checking for terraform destroy in cleanup loop
- Mount directory cleanup
- Skip workspace deletion if destroy fails

Fixes: Issue #5 - cleanup_stopped_vms hides errors in subshell"
```

---

## Task 6: Add Integration Tests for Bug Fixes

**Files:**
- Modify: `test-integration.sh:329-402`

**Goal:** Add integration tests to verify all 6 bug fixes work correctly.

**Step 1: Create helper function for test assertions**

Add after line 328 in `test-integration.sh`:

```bash
# Test assertion helper
assert_success() {
  if [ $? -ne 0 ]; then
    echo "FAIL: $1"
    return 1
  fi
  echo "PASS: $1"
  return 0
}

assert_failure() {
  if [ $? -eq 0 ]; then
    echo "FAIL: $1 (expected failure)"
    return 1
  fi
  echo "PASS: $1"
  return 0
}
```

**Step 2: Add test for Issue #1 (dirty check before unmount)**

Add before cleanup section (before line 394):

```bash
  # Test 7: Verify dirty check prevents fetch (Issue #1)
  echo "Test: Dirty check prevents fetch with uncommitted changes"
  ./agent-vm -b test-branch-1 -- bash -c "cd /worktree && echo 'dirty' >> test-dirty.txt"

  # Try to fetch (should fail with uncommitted changes)
  if ./agent-vm -b test-branch-1 --fetch 2>&1 | grep -q "uncommitted changes"; then
    echo "PASS: Fetch correctly blocked on dirty working tree"
  else
    echo "FAIL: Fetch should have been blocked on dirty working tree"
    ./agent-vm -b test-branch-1 --destroy
    ./agent-vm -b test-branch-2 --destroy
    return 1
  fi

  # Clean up the dirty file
  ./agent-vm -b test-branch-1 -- bash -c "cd /worktree && rm -f test-dirty.txt"
```

**Step 3: Add test for Issue #2 (concurrent IP allocation)**

```bash
  # Test 8: Verify concurrent creation doesn't cause IP conflicts (Issue #2)
  echo "Test: Concurrent VM creation with different IPs"
  ./agent-vm -b test-concurrent-1 -- echo "VM 1" &
  PID1=$!
  ./agent-vm -b test-concurrent-2 -- echo "VM 2" &
  PID2=$!

  wait $PID1
  wait $PID2

  # Get IPs and verify they're different
  IP1=$(./agent-vm --list | grep test-concurrent-1 | awk '{print $3}')
  IP2=$(./agent-vm --list | grep test-concurrent-2 | awk '{print $3}')

  if [ "$IP1" != "$IP2" ] && [ -n "$IP1" ] && [ -n "$IP2" ]; then
    echo "PASS: Concurrent VMs have different IPs ($IP1 vs $IP2)"
  else
    echo "FAIL: Concurrent VMs have same IP or missing IP"
    ./agent-vm -b test-concurrent-1 --destroy
    ./agent-vm -b test-concurrent-2 --destroy
    ./agent-vm -b test-branch-1 --destroy
    ./agent-vm -b test-branch-2 --destroy
    return 1
  fi

  # Clean up concurrent test VMs
  ./agent-vm -b test-concurrent-1 --destroy
  ./agent-vm -b test-concurrent-2 --destroy
```

**Step 4: Add test for Issue #5 (cleanup count)**

```bash
  # Test 9: Verify cleanup reports correct count (Issue #5)
  echo "Test: Cleanup correctly counts stopped VMs"

  # Create and stop a VM
  ./agent-vm -b test-cleanup -- echo "test"
  virsh shutdown workspace-test-cleanup
  sleep 5

  # Run cleanup and verify count
  if ./agent-vm --cleanup 2>&1 | grep -q "Cleaned up 1 stopped"; then
    echo "PASS: Cleanup correctly reported 1 VM cleaned"
  else
    echo "FAIL: Cleanup did not report correct count"
    ./agent-vm -b test-cleanup --destroy 2>/dev/null || true
    ./agent-vm -b test-branch-1 --destroy
    ./agent-vm -b test-branch-2 --destroy
    return 1
  fi
```

**Step 5: Apply all test additions**

Run: `vim test-integration.sh` and add the test code above before the cleanup section (before line 394)

**Step 6: Run the full integration test suite**

```bash
cd ..  # Back to repo root
./test-integration.sh --vm
```

Expected: All tests pass including the 3 new tests

**Step 7: Commit the test additions**

```bash
git add test-integration.sh
git commit -m "test(vm): add integration tests for critical bug fixes

Add tests verifying:
- Issue #1: Dirty check prevents fetch with uncommitted changes
- Issue #2: Concurrent creation assigns different IPs
- Issue #5: Cleanup correctly counts stopped VMs

These tests ensure the bug fixes work correctly and prevent regression."
```

---

## Task 7: Update Documentation

**Files:**
- Modify: `vm/CLAUDE.md`
- Create: `vm/TROUBLESHOOTING.md`

**Step 1: Document the bug fixes in CLAUDE.md**

Add new section after line 218 in `vm/CLAUDE.md`:

```markdown
## Recent Bug Fixes (2026-01-07)

Six critical bugs were fixed to improve safety and robustness:

1. **Data Loss Prevention**: `--fetch` now checks for uncommitted changes BEFORE unmounting SSHFS, preventing editor buffer loss
2. **Race Condition Fix**: IP allocation uses file locking to prevent concurrent processes from allocating the same IP
3. **Resource Leak Prevention**: Workspace deletion only occurs after successful `terraform destroy`
4. **Orphan Recovery**: Workspace orphan recovery verifies destroy success before recreation
5. **Cleanup Accuracy**: `--cleanup` now correctly counts cleaned VMs (fixed subshell issue)
6. **Mount Cleanup**: Mount directories are cleaned up when VMs are destroyed

See `docs/plans/2026-01-07-agent-vm-critical-bug-fixes.md` for full details.

```

**Step 2: Create troubleshooting guide**

Create `vm/TROUBLESHOOTING.md`:

```markdown
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

**Cause**: Another agent-vm process is allocating an IP, or previous process crashed while holding lock

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
```

**Step 3: Apply documentation changes**

```bash
vim vm/CLAUDE.md  # Add bug fixes section
vim vm/TROUBLESHOOTING.md  # Create new file with content above
```

**Step 4: Commit documentation**

```bash
git add vm/CLAUDE.md vm/TROUBLESHOOTING.md
git commit -m "docs(vm): document critical bug fixes and add troubleshooting guide

- Document 6 critical bug fixes in CLAUDE.md
- Create comprehensive troubleshooting guide
- Add diagnostic commands for common issues
- Provide recovery procedures for failure scenarios"
```

---

## Task 8: Final Verification and Testing

**Files:**
- Run tests on: All modified files

**Step 1: Run shellcheck on modified scripts**

```bash
cd vm
shellcheck agent-vm vm-common.sh
```

Expected: No errors (or only minor style warnings)

**Step 2: Run full integration test suite**

```bash
cd ..
./test-integration.sh --vm
```

Expected: All tests pass, including the 3 new bug fix tests

**Step 3: Manual smoke test of all operations**

```bash
cd vm

# Test 1: Create VM
./agent-vm -b final-test -- echo "VM created"

# Test 2: Reconnect
./agent-vm -b final-test -- echo "Reconnected"

# Test 3: List VMs
./agent-vm --list

# Test 4: Create file in VM and commit
./agent-vm -b final-test -- bash -c "cd /worktree && echo 'test' > test.txt && git add test.txt && git commit -m 'test commit'"

# Test 5: Fetch from VM
./agent-vm -b final-test --fetch

# Test 6: Verify file exists in host repo
git checkout final-test
test -f test.txt && echo "✓ File fetched successfully"
git checkout -

# Test 7: Destroy VM
./agent-vm -b final-test --destroy

# Test 8: Verify cleanup
./agent-vm --list | grep -q final-test && echo "✗ VM still exists" || echo "✓ VM destroyed"
```

Expected: All steps succeed with ✓ marks

**Step 4: Check for resource leaks**

```bash
# No orphaned VMs
virsh list --all | grep -v "Id\|---\|^$" | wc -l

# No orphaned workspaces
terraform workspace list | grep -v default | wc -l

# No orphaned mount directories
ls ~/.agent-vm-mounts/ 2>/dev/null | wc -l
```

Expected: All counts should be 0 (or only expected VMs/workspaces)

**Step 5: Review all commits**

```bash
git log --oneline -8 -- vm/ test-integration.sh docs/
```

Expected output:
```
<sha> docs(vm): document critical bug fixes and add troubleshooting guide
<sha> test(vm): add integration tests for critical bug fixes
<sha> fix(vm): fix cleanup_stopped_vms to correctly count cleaned VMs
<sha> fix(vm): verify terraform destroy succeeds in orphan recovery
<sha> fix(vm): verify terraform destroy succeeds before deleting workspace
<sha> fix(vm): add file locking to prevent IP allocation race condition
<sha> fix(vm): check for uncommitted changes before unmounting SSHFS
<sha> (previous commit)
```

**Step 6: Create summary commit if needed**

If you want a single reference point:

```bash
git tag -a v1.1.0-vm-bug-fixes -m "agent-vm critical bug fixes

Fixed 6 critical bugs:
1. Data loss in fetch (SSHFS unmount timing)
2. IP allocation race condition
3. Resource leaks in destroy
4. Orphan recovery errors
5. Cleanup counting bug
6. Mount directory accumulation

All fixes tested with integration tests."
```

**Step 7: Final verification complete**

Review checklist:
- [ ] All 6 bugs fixed
- [ ] All commits have descriptive messages
- [ ] Integration tests added and passing
- [ ] Documentation updated
- [ ] No shellcheck errors
- [ ] Manual smoke test passed
- [ ] No resource leaks detected

---

## Completion Criteria

All tasks complete when:

1. ✅ All 6 bug fixes applied and committed
2. ✅ Integration tests added for critical fixes
3. ✅ Documentation updated with bug fix details
4. ✅ Troubleshooting guide created
5. ✅ All integration tests passing
6. ✅ No shellcheck errors
7. ✅ Manual smoke test successful
8. ✅ No resource leaks detected

## Risk Assessment

**Low Risk Changes:**
- Task 1 (dirty check reordering) - pure reordering, no new logic
- Task 5 (subshell fix) - standard bash pattern
- Task 7 (documentation) - no code changes

**Medium Risk Changes:**
- Task 2 (file locking) - introduces new dependency on flock
- Task 6 (integration tests) - new test code

**Higher Risk Changes:**
- Task 3 (destroy error handling) - changes error flow, must test carefully
- Task 4 (orphan recovery) - similar to Task 3

**Mitigation:**
- Test each change individually before moving to next task
- Keep git commits granular for easy rollback
- Run integration tests after each significant change
- Manual testing of error paths

## Notes for Engineer

- All file paths are exact - use them as-is
- Test after EACH task, don't batch
- Commit after EACH task (8 commits expected)
- If a test fails, stop and investigate before proceeding
- The fixes are ordered by criticality (most critical first)
- Pay special attention to error message formatting (they guide users in recovery)

---

## ADDENDUM: Resource Override Bug Fix (2026-01-07)

**Status:** ✅ FIXED (Commit: 165af0b)

### Bug 7: Resource Overrides Completely Broken (CRITICAL)

**Files:**
- Modified: `vm/agent-vm:600-609, 623-628`

**Issue:** The `--memory`, `--vcpu`, and `--disk` flags were advertised but completely non-functional due to broken command substitution pattern.

**Root Cause:**

Lines 600-602, 616-617 used the pattern:

```bash
$([[ test ]] && echo "ARRAY+=(value)" || true)
```

This pattern **does not work** because:

1. `echo "ARRAY+=(value)"` produces a string
2. `$()` tries to **execute that string as a command**
3. Bash interprets `ARRAY+=()` as a command name, not an assignment
4. Result: `bash: ARRAY+=(value): command not found`
5. Array remains unchanged, overrides silently ignored

**Example Demonstration:**

```bash
# What users expected:
ARR=(a)
$([[ -n "x" ]] && echo "ARR+=(b)" || true)
# Expected: ARR=(a b)

# What actually happened:
# Output: bash: ARR+=(b): command not found
echo "${ARR[@]}"  # Still just "a" - override ignored!
```

**Impact:**

- `--memory` flag was non-functional
- `--vcpu` flag was non-functional
- `--disk` flag was non-functional
- `ANTHROPIC_VERTEX_PROJECT_ID` override was non-functional
- `CLOUD_ML_REGION` override was non-functional

VMs were always created with default resources (4GB RAM, 2 vCPU, 40GB disk), silently ignoring user-specified overrides.

**The Fix:**

Replace command substitution with proper if statements:

```diff
 # Add resource overrides if provided
-$([[ -n "$MEMORY_OVERRIDE" ]] && echo "TERRAFORM_VARS+=(-var=\"vm_memory=$MEMORY_OVERRIDE\")" || true)
-$([[ -n "$VCPU_OVERRIDE" ]] && echo "TERRAFORM_VARS+=(-var=\"vm_vcpu=$VCPU_OVERRIDE\")" || true)
-$([[ -n "$DISK_OVERRIDE" ]] && echo "DISK_BYTES=\$(numfmt --from=iec \"$DISK_OVERRIDE\") && TERRAFORM_VARS+=(-var=\"vm_disk_size=\$DISK_BYTES\")" || true)
+if [[ -n "$MEMORY_OVERRIDE" ]]; then
+  TERRAFORM_VARS+=(-var="vm_memory=$MEMORY_OVERRIDE")
+fi
+if [[ -n "$VCPU_OVERRIDE" ]]; then
+  TERRAFORM_VARS+=(-var="vm_vcpu=$VCPU_OVERRIDE")
+fi
+if [[ -n "$DISK_OVERRIDE" ]]; then
+  DISK_BYTES=\$(numfmt --from=iec "$DISK_OVERRIDE")
+  TERRAFORM_VARS+=(-var="vm_disk_size=\$DISK_BYTES")
+fi
```

And for GCP variables:

```diff
-$([[ -n "$ANTHROPIC_VERTEX_PROJECT_ID" ]] && echo "TERRAFORM_VARS+=(-var=\"vertex_project_id=$ANTHROPIC_VERTEX_PROJECT_ID\")" || true)
-$([[ -n "$CLOUD_ML_REGION" ]] && echo "TERRAFORM_VARS+=(-var=\"vertex_region=$CLOUD_ML_REGION\")" || true)
+if [[ -n "$ANTHROPIC_VERTEX_PROJECT_ID" ]]; then
+  TERRAFORM_VARS+=(-var="vertex_project_id=$ANTHROPIC_VERTEX_PROJECT_ID")
+fi
+if [[ -n "$CLOUD_ML_REGION" ]]; then
+  TERRAFORM_VARS+=(-var="vertex_region=$CLOUD_ML_REGION")
+fi
```

**Testing:**

Verified with terraform plan output showing correct values:

```bash
# Test 1: Memory override (8GB)
./agent-vm -b test-memory --memory 8192 -- echo "test"
# Terraform plan showed: memory = 8192 ✓

# Test 2: VCPU override (2 cores)
./agent-vm -b test-vcpu --vcpu 2 -- echo "test"
# VM created with: vcpu = 2 ✓
```

**Commit:**

```
fix(vm): fix resource override feature to actually work

Replace broken command substitution pattern with if statements.
The $(...) pattern tried to execute array assignments as commands,
causing resource overrides to be silently ignored.

Now --memory, --vcpu, --disk flags work correctly.
```

**Commit Hash:** 165af0b

**Lessons Learned:**

1. **Command substitution executes output as commands** - `$(echo "X=1")` tries to run `X=1` as a command, not as an assignment
2. **Array assignments are NOT commands** - they're shell syntax that only works in the main shell context
3. **If statements are the correct pattern** for conditional array modifications
4. **Silent failures are extremely dangerous** - the `|| true` suppressed all errors, making this bug undetectable without careful inspection
5. **Test advertised features** - this feature was documented but never actually worked

**Related to:** This bug was independent of the other 6 bugs but equally critical as it made a documented feature completely non-functional.
