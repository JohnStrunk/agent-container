# SSHFS Mount Lifecycle Design

**Date:** 2026-02-24
**Status:** Approved
**Author:** Claude Sonnet 4.5

## Overview

Change the VM sshfs mounting lifecycle so that the filesystem is mounted when the VM starts (via `./agent-vm start`) and persists until the VM is destroyed. Currently, sshfs is only mounted when running `./agent-vm connect <branch>`, which requires an unnecessary extra step to access the filesystem.

## Current Behavior

1. User runs `./agent-vm start` → VM created/started
2. User runs `./agent-vm connect <branch>` → sshfs mounted (agent-vm:654-655)
3. User runs `./agent-vm destroy` → sshfs unmounted, VM destroyed

**Problem:** The filesystem is not available immediately after VM start. Users must run `connect` with a branch name to trigger the mount, even if they just want to browse files on the host.

## Proposed Behavior

1. User runs `./agent-vm start` → VM created/started → **sshfs mounted automatically**
2. User runs `./agent-vm connect <branch>` → uses existing mount (no mount operation)
3. User runs `./agent-vm destroy` → sshfs unmounted, VM destroyed

**Benefits:**
- Filesystem available immediately after start
- No need to run `connect` just to get filesystem access
- Clearer lifecycle: start → mount, destroy → unmount
- Consistent with user expectation that "start" makes everything ready

## Architecture

### Approach Selection

Three approaches were considered:

1. **Mount in start_vm function** ✅ **Selected**
   - Add sshfs mount at end of `start_vm()`, after VM is ready
   - Simple and clear - mount happens immediately after VM start
   - Easy to debug - all mount logic stays in shell script
   - Respects `ensure_vm_running` flow

2. **Mount in ensure_vm_running function**
   - Add mount at end of `ensure_vm_running()`
   - Single location for mount logic
   - Less explicit - mount happens as side effect
   - May attempt to mount multiple times

3. **Mount via Lima provisioning**
   - Add Lima provision step for reverse SSHFS
   - Requires VM to access host (security concern)
   - Doesn't align with current forward-SSHFS architecture

**Selected:** Approach 1 (Mount in start_vm) - clearest and most explicit.

### Key Changes

**start_vm function (agent-vm:92-226):**
- Add SSH wait loop after VM creation/start
- Add `mount_vm_workspace || true` after SSH is ready
- Handle three cases:
  1. New VM creation (after line 225)
  2. Existing VM was stopped (after line 121)
  3. VM already running (after line 120)

**connect_to_vm function (agent-vm:598-687):**
- Remove mount operation (lines 654-655)
- Mount already exists from `start_vm`, just use it

**ensure_vm_running function (agent-vm:573-596):**
- No changes needed - calls `start_vm` which handles mounting

### Data Flow

```
./agent-vm start
  ├─> VM doesn't exist
  │   ├─> limactl start (creates VM)
  │   ├─> Wait for SSH ready
  │   └─> mount_vm_workspace
  │       ├─> sshfs available: mount succeeds
  │       └─> sshfs not available: warning, continue
  │
  ├─> VM exists, stopped
  │   ├─> limactl start (starts VM)
  │   ├─> Wait for SSH ready
  │   └─> mount_vm_workspace
  │
  └─> VM exists, running
      └─> mount_vm_workspace (ensures mount exists)

./agent-vm connect [branch]
  ├─> ensure_vm_running (calls start_vm if needed)
  └─> SSH to workspace (mount already available)

./agent-vm destroy
  ├─> unmount_vm_workspace
  └─> limactl delete
```

## Error Handling

### SSH Readiness
- After `limactl start`, wait for SSH to be ready (max 5 minutes)
- Use same pattern as `ensure_vm_running`: `ssh -F "$SSH_CONFIG" -o ConnectTimeout=5 -o BatchMode=yes "$VM_HOST" "exit"`
- If SSH fails after timeout, error and exit (VM is not usable)

### SSHFS Mount Failure
- If sshfs is not installed: show warning, continue without mount
- If sshfs command fails: show warning, continue without mount
- VM remains usable even without mount (users can still SSH in)
- User can manually mount later if needed

### Already Mounted
- `mount_vm_workspace` already handles this (agent-vm:56-58)
- If already mounted, function returns success immediately
- No duplicate mount attempts

### VM Already Exists
- When VM already exists and is stopped, start it and mount
- When VM already running, ensure mount exists
- Check if mounted, mount if not mounted

## Implementation Details

### start_vm Function Modifications

**Location 1: After new VM creation (after line 225)**

```bash
echo "✓ VM created successfully: $VM_NAME"

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

**Location 2: After existing VM start (after line 118)**

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

**Location 3: VM already running (after line 120)**

```bash
echo "VM is already running"

# Ensure mount exists
mount_vm_workspace || true
```

### connect_to_vm Function Modifications

**Remove mount operation (delete lines 654-655):**

```bash
# OLD CODE (remove these lines):
# Mount workspace via SSHFS (if not already mounted)
mount_vm_workspace || true

# NEW CODE (none needed):
# Mount already exists from start_vm
```

## Testing Strategy

### Manual Testing

1. **Clean start test:**
   ```bash
   ./agent-vm destroy
   ./agent-vm start
   # Verify mount exists
   mountpoint ~/.agent-vm-mounts/workspace
   ```

2. **VM restart test:**
   ```bash
   ./agent-vm destroy
   ./agent-vm start
   limactl stop agent-vm
   ./agent-vm start
   # Verify mount exists after restart
   mountpoint ~/.agent-vm-mounts/workspace
   ```

3. **Connect without mount operation:**
   ```bash
   ./agent-vm start
   ./agent-vm connect test-branch
   # Verify workspace created, mount already available
   ls ~/.agent-vm-mounts/workspace/
   ```

4. **Missing sshfs test:**
   ```bash
   # Temporarily rename sshfs
   sudo mv /usr/bin/sshfs /usr/bin/sshfs.bak
   ./agent-vm start
   # Verify: warning shown, VM starts successfully
   sudo mv /usr/bin/sshfs.bak /usr/bin/sshfs
   ```

5. **Integration test:**
   ```bash
   cd ..
   ./test-integration.sh --vm
   ```

### Integration Test Updates

**Add to test-integration.sh (after VM start verification):**

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

**Test coverage:**
- Mount exists immediately after start
- Mount is accessible (not stale)
- Connect operations work with pre-existing mount
- Destroy properly unmounts filesystem

## Mount Persistence

- Mount persists as long as VM is running
- Mount survives across multiple `connect` sessions
- Mount survives VM stop/start cycle (remounted on start)
- Mount removed only on `destroy`

## Backward Compatibility

### No Breaking Changes

- All existing commands work the same way
- `connect` behavior unchanged from user perspective
- `destroy` behavior unchanged
- Status output unchanged (already shows mount status)

### User Experience Improvements

- ✅ Mount available immediately after start
- ✅ No need to run `connect` to get filesystem access
- ✅ Clearer lifecycle: start → mount, destroy → unmount
- ✅ Consistent with user expectations

## Documentation Updates

Files that need updates:

1. **vm/CLAUDE.md**
   - Workflow section (lines 710-716)
   - Update step 2: "Create workspace (mount already available)"

2. **vm/README.md**
   - File sharing section
   - Update workflow to reflect mount happens at start

3. **vm/agent-vm** (usage function, lines 710-716)
   - Update workflow example
   - Clarify that mount happens during start

### Example Documentation Change

**Before:**
```
Workflow:
  1. ./agent-vm start                         # Create/start VM
  2. ./agent-vm connect feature-auth          # Create workspace, mount SSHFS
```

**After:**
```
Workflow:
  1. ./agent-vm start                         # Create/start VM, mount SSHFS
  2. ./agent-vm connect feature-auth          # Create workspace (mount already available)
```

## Security Considerations

No security changes - the same forward SSHFS architecture is maintained:
- VM cannot access host filesystem (forward mount only)
- No agent forwarding
- SSH keys managed by Lima
- Mount only accessible to user running the VM

## Success Criteria

1. ✅ Running `./agent-vm start` mounts sshfs automatically
2. ✅ Mount is available before any `connect` operation
3. ✅ Missing sshfs shows warning but doesn't fail VM start
4. ✅ Integration tests pass with new mount verification
5. ✅ Documentation updated to reflect new behavior
6. ✅ No breaking changes to existing workflows
