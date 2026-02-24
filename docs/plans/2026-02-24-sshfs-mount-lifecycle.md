# SSHFS Mount Lifecycle Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Mount sshfs automatically when VM starts, rather than waiting for connect operation.

**Architecture:** Modify `start_vm` function to mount sshfs after SSH is ready. Remove mount operation from `connect_to_vm`. Update integration tests to verify mount exists immediately after start.

**Tech Stack:** Bash, Lima, SSHFS, integration tests

---

## Task 1: Add SSH wait and mount to new VM creation path

**Files:**
- Modify: `vm/agent-vm:225-226`

**Step 1: Add SSH readiness wait after new VM creation**

After line 225 (`echo "✓ VM created successfully: $VM_NAME"`), add:

```bash
  # Wait for SSH to be ready
  echo "Waiting for VM to be ready..."
  local max_wait=300
  local elapsed=0
  while ! ssh -F "$SSH_CONFIG" -o ConnectTimeout=5 -o BatchMode=yes \
       "$VM_HOST" "exit" 2>/dev/null; do
    sleep 5
    elapsed=$((elapsed + 5))
    if [[ $elapsed -ge $max_wait ]]; then
      echo "ERROR: VM failed to start within 5 minutes" >&2
      exit 1
    fi
  done
  echo "✓ VM is ready"

  # Mount workspace via SSHFS
  mount_vm_workspace || true
```

**Step 2: Verify syntax**

Run: `bash -n vm/agent-vm`
Expected: No output (syntax valid)

**Step 3: Commit**

```bash
git add vm/agent-vm
git commit -m "feat(vm): mount sshfs after new VM creation

Add SSH readiness wait and mount operation after creating new VM.
This ensures the filesystem is available immediately after start.

Part of SSHFS mount lifecycle changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Add SSH wait and mount to existing VM start path

**Files:**
- Modify: `vm/agent-vm:118-121`

**Step 1: Add SSH readiness wait after existing VM start**

After line 118 (`limactl start --tty=false "$VM_NAME"`), replace the existing return statement with:

```bash
      limactl start --tty=false "$VM_NAME"

      # Wait for SSH to be ready
      echo "Waiting for VM to be ready..."
      local max_wait=300
      local elapsed=0
      while ! ssh -F "$SSH_CONFIG" -o ConnectTimeout=5 -o BatchMode=yes \
           "$VM_HOST" "exit" 2>/dev/null; do
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ $elapsed -ge $max_wait ]]; then
          echo "ERROR: VM failed to start within 5 minutes" >&2
          exit 1
        fi
      done
      echo "✓ VM is ready"

      # Mount workspace via SSHFS
      mount_vm_workspace || true
```

**Step 2: Verify syntax**

Run: `bash -n vm/agent-vm`
Expected: No output (syntax valid)

**Step 3: Commit**

```bash
git add vm/agent-vm
git commit -m "feat(vm): mount sshfs after starting stopped VM

Add SSH readiness wait and mount operation when starting an existing
but stopped VM. Ensures mount is available after VM restart.

Part of SSHFS mount lifecycle changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Add mount check to already-running VM path

**Files:**
- Modify: `vm/agent-vm:120-121`

**Step 1: Add mount check after already-running message**

After line 120 (`echo "VM is already running"`), add before the return:

```bash
      echo "VM is already running"

      # Ensure mount exists
      mount_vm_workspace || true
```

**Step 2: Verify syntax**

Run: `bash -n vm/agent-vm`
Expected: No output (syntax valid)

**Step 3: Commit**

```bash
git add vm/agent-vm
git commit -m "feat(vm): ensure mount exists when VM already running

When VM is already running, verify mount exists and create it if not.
This handles cases where mount may have been manually unmounted.

Part of SSHFS mount lifecycle changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Remove mount operation from connect_to_vm

**Files:**
- Modify: `vm/agent-vm:654-655`

**Step 1: Remove mount operation**

Delete lines 654-655:

```bash
  # Mount workspace via SSHFS (if not already mounted)
  mount_vm_workspace || true
```

The mount now exists from `start_vm`, so this is no longer needed.

**Step 2: Verify syntax**

Run: `bash -n vm/agent-vm`
Expected: No output (syntax valid)

**Step 3: Commit**

```bash
git add vm/agent-vm
git commit -m "refactor(vm): remove mount operation from connect

Mount is now handled by start_vm, so connect_to_vm no longer needs
to mount. This simplifies the connect flow and ensures mount is
always available before any connect operation.

Part of SSHFS mount lifecycle changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Update integration test to verify mount after start

**Files:**
- Modify: `test-integration.sh`

**Step 1: Find VM start verification section**

Search for where the test runs `./agent-vm start` and verifies success.

Run: `grep -n "agent-vm start" test-integration.sh`

**Step 2: Add mount verification after start**

After the start command succeeds (but before any connect operation), add:

```bash
# Verify SSHFS mount exists after start
if ! mountpoint -q "$HOME/.agent-vm-mounts/workspace" 2>/dev/null; then
  echo "FAIL: SSHFS mount not created during VM start"
  exit 1
fi
echo "✓ SSHFS mount exists after VM start"

# Verify mount is accessible
if ! ls "$HOME/.agent-vm-mounts/workspace/" >/dev/null 2>&1; then
  echo "FAIL: SSHFS mount not accessible"
  exit 1
fi
echo "✓ SSHFS mount is accessible"
```

**Step 3: Verify syntax**

Run: `bash -n test-integration.sh`
Expected: No output (syntax valid)

**Step 4: Commit**

```bash
git add test-integration.sh
git commit -m "test(vm): verify sshfs mount exists after start

Add integration test verification that sshfs is mounted immediately
after VM start, before any connect operation. This ensures the mount
lifecycle change works correctly.

Part of SSHFS mount lifecycle changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Update CLAUDE.md workflow documentation

**Files:**
- Modify: `vm/CLAUDE.md:710-716`

**Step 1: Update workflow section**

Find the workflow section (around line 710-716) and update step 2:

**Before:**
```markdown
Workflow:
  1. ./agent-vm start                         # Create/start VM
  2. ./agent-vm connect feature-auth          # Create workspace, mount SSHFS
  3. Edit files at ~/.agent-vm-mounts/workspace/<repo>-<branch>/
```

**After:**
```markdown
Workflow:
  1. ./agent-vm start                         # Create/start VM, mount SSHFS
  2. ./agent-vm connect feature-auth          # Create workspace (mount already available)
  3. Edit files at ~/.agent-vm-mounts/workspace/<repo>-<branch>/
```

**Step 2: Update examples section**

Find the examples section (around line 723-736) and update the workflow comments:

Update line 725 comment from:
```bash
  $0 start                                # Create/start VM
```

To:
```bash
  $0 start                                # Create/start VM, mount SSHFS
```

**Step 3: Commit**

```bash
git add vm/CLAUDE.md
git commit -m "docs(vm): update workflow to reflect mount at start

Update CLAUDE.md to reflect that sshfs is mounted during start,
not during connect. This clarifies the new mount lifecycle for
future development.

Part of SSHFS mount lifecycle changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Update agent-vm usage documentation

**Files:**
- Modify: `vm/agent-vm:710-716`

**Step 1: Update usage function workflow**

In the `usage` function (lines 689-747), update the workflow section:

**Before:**
```bash
Workflow:
  1. ./agent-vm start                         # Create/start VM
  2. ./agent-vm connect feature-auth          # Create workspace, mount SSHFS
```

**After:**
```bash
Workflow:
  1. ./agent-vm start                         # Create/start VM, mount SSHFS
  2. ./agent-vm connect feature-auth          # Create workspace (mount already available)
```

**Step 2: Update examples section**

Update line 725 from:
```bash
  $0 start                                # Create/start VM
```

To:
```bash
  $0 start                                # Create/start VM, mount SSHFS
```

**Step 3: Verify syntax**

Run: `bash -n vm/agent-vm`
Expected: No output (syntax valid)

**Step 4: Commit**

```bash
git add vm/agent-vm
git commit -m "docs(vm): update usage text for mount lifecycle

Update agent-vm usage documentation to reflect that sshfs mounting
happens during start, not during connect. This ensures users have
accurate information when running --help.

Part of SSHFS mount lifecycle changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Run integration tests

**Files:**
- None (verification only)

**Step 1: Run VM integration tests**

Run: `./test-integration.sh --vm`
Expected: All tests pass, including new mount verification

**Step 2: Verify test output**

Look for:
```
✓ SSHFS mount exists after VM start
✓ SSHFS mount is accessible
```

**Step 3: If tests fail, debug**

Check:
- VM started successfully
- SSH is ready
- sshfs command succeeded
- Mount point exists and is accessible

**Step 4: Document results**

If tests pass, no commit needed. If tests revealed issues, fix and commit with:

```bash
git add <affected-files>
git commit -m "fix(vm): address integration test failures

<description of fix>

Part of SSHFS mount lifecycle changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Manual testing verification

**Files:**
- None (verification only)

**Step 1: Clean start test**

```bash
cd vm
./agent-vm destroy
./agent-vm start
mountpoint ~/.agent-vm-mounts/workspace
```

Expected: "~/.agent-vm-mounts/workspace is a mountpoint"

**Step 2: VM restart test**

```bash
./agent-vm destroy
./agent-vm start
limactl stop agent-vm
./agent-vm start
mountpoint ~/.agent-vm-mounts/workspace
```

Expected: Mount exists after restart

**Step 3: Connect test**

```bash
./agent-vm start
./agent-vm connect test-branch
ls ~/.agent-vm-mounts/workspace/
```

Expected: Workspace directory visible, no mount errors

**Step 4: Document results**

Create a brief summary of manual testing results. No commit needed unless issues found.

---

## Task 10: Final verification and cleanup

**Files:**
- None (verification only)

**Step 1: Review all commits**

Run: `git log --oneline | head -10`

Expected: See all commits from this implementation

**Step 2: Verify no uncommitted changes**

Run: `git status`
Expected: "nothing to commit, working tree clean"

**Step 3: Run pre-commit on all modified files**

Run: `pre-commit run --files vm/agent-vm vm/CLAUDE.md test-integration.sh`
Expected: All checks pass

**Step 4: Create summary of changes**

List all modified files and briefly describe changes:
- `vm/agent-vm` - Added mount operations to start_vm, removed from connect_to_vm
- `vm/CLAUDE.md` - Updated workflow documentation
- `test-integration.sh` - Added mount verification after start
- `docs/plans/` - Design and implementation plan documents

---

## Success Criteria

- ✅ `./agent-vm start` mounts sshfs automatically
- ✅ Mount exists before any `connect` operation
- ✅ Integration tests verify mount exists after start
- ✅ Manual testing confirms expected behavior
- ✅ Documentation updated to reflect new lifecycle
- ✅ All tests pass
- ✅ No uncommitted changes

## Rollback Plan

If issues are discovered:

1. Revert commits in reverse order:
   ```bash
   git revert HEAD~7..HEAD
   ```

2. Original behavior restored:
   - Mount happens in `connect_to_vm`
   - No mount in `start_vm`
   - Integration tests don't check for mount after start

## Notes

- The `mount_vm_workspace` function already handles "already mounted" case (line 56-58)
- Error handling for missing sshfs already exists (shows warning, continues)
- No changes needed to `destroy_vm` - it already unmounts correctly
- No changes needed to `ensure_vm_running` - it calls `start_vm` which now handles mounting
