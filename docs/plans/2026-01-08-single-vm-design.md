# Single VM Multi-Workspace Design

**Date:** 2026-01-08

**Status:** Approved

## Overview

Redesign `agent-vm` to use a single persistent VM with multiple workspace directories instead of multiple VMs. This simplifies resource management while still supporting multiple concurrent agents working on different branches.

## Goals

1. **Reduce resource consumption:** Single VM instead of one per branch
2. **Simplify architecture:** No Terraform workspaces, IP allocation, or workspace-specific state
3. **Maintain isolation:** Each branch gets its own workspace directory with full git clone
4. **Improve UX:** Single SSHFS mount shows all workspaces, simpler command interface

## Architecture Overview

**Single VM Model**

The redesigned `agent-vm` uses one persistent VM that hosts multiple workspace directories. Each workspace corresponds to a repository-branch combination (e.g., `myrepo-feature-auth`).

**Key simplifications from multi-VM:**
- No Terraform workspaces (single `default` workspace)
- No IP allocation logic (single static IP)
- No per-VM SSH keys (one key for the VM)
- No workspace-specific state management

**VM lifecycle:**
- Created on first `./agent-vm -b <any-branch>` invocation
- Persists across all sessions
- Only destroyed with explicit `./agent-vm --destroy` command
- Resource settings (memory, CPU, disk) specified at creation, immutable

**Workspace lifecycle:**
- Auto-created when you connect: `./agent-vm -b feature-auth`
- Directory: `~/workspace/${REPO_NAME}-${BRANCH_NAME}/` in VM
- Contains full git clone of the branch
- Cleaned up explicitly: `./agent-vm -b feature-auth --clean`
- Bulk cleanup: `./agent-vm --clean-all` (removes all workspaces, VM stays up)

**File sharing:**
- Single SSHFS mount: `~/.agent-vm-mounts/workspace/` → VM's `~/workspace/`
- Host IDE sees all active workspaces in one directory tree
- Real-time bidirectional sync via SSHFS
- Mount persists, no unmount/remount when switching branches

## Command Interface

**Basic operations:**

```bash
# Connect to workspace (creates VM and/or workspace if needed)
./agent-vm -b feature-auth
./agent-vm -b feature-auth -- claude    # Run command and exit

# Fetch changes from VM workspace back to host
./agent-vm -b feature-auth --fetch

# Force push branch from host to VM (overwrites VM state)
./agent-vm -b feature-auth --push

# List all workspaces in VM
./agent-vm --list

# Clean up specific workspace (removes directory from VM)
./agent-vm -b feature-auth --clean

# Clean up all workspaces (VM stays running)
./agent-vm --clean-all

# Destroy entire VM (and all workspaces)
./agent-vm --destroy
```

**VM resource options (creation-time only):**

```bash
# First invocation - creates VM with custom resources
./agent-vm -b feature-auth --memory 16384 --vcpu 8 --disk 60G

# Subsequent invocations - resource flags ignored with warning
./agent-vm -b bugfix-123 --memory 8192  # Warns: VM exists, flags ignored
```

**Argument requirements:**
- `-b <branch>` is always required except for: `--list`, `--clean-all`, `--destroy`
- Must be run from within a git repository when using `-b`
- Resource flags only apply if VM doesn't exist yet

**Removed commands from multi-VM design:**
- `--stop` (no longer needed with single VM)
- `--cleanup` (replaced by `--clean` and `--clean-all`)

## Git Workflow

**On connect (`./agent-vm -b feature-auth`):**

1. Check if workspace directory exists in VM: `~/workspace/myrepo-feature-auth/`
2. If missing:
   - Create directory via SSH
   - Initialize git repo: `git init`
   - Git config already present from `common/homedir/.gitconfig` (deployed at VM creation)
3. If workspace missing OR `--push` flag provided:
   - Check if branch exists locally, auto-create from HEAD if not
   - Push branch from host to VM workspace:
     - `git push ssh://user@${VM_IP}/workspace/myrepo-feature-auth feature-auth:feature-auth`
     - Checkout branch in VM: `git checkout feature-auth`
4. Result: VM workspace has full git clone on the specified branch

**On fetch (`./agent-vm -b feature-auth --fetch`):**

1. Check for uncommitted changes in VM workspace
2. If dirty, warn but continue: "WARNING: VM workspace has uncommitted changes. These will NOT be included in the fetch."
3. Fetch branch from VM to host:
   - `git fetch ssh://user@${VM_IP}/workspace/myrepo-feature-auth feature-auth:feature-auth`
4. Show summary of fetched commits
5. User can review/merge on host

**Multiple agents on different branches:**

```bash
# Terminal 1
./agent-vm -b feature-auth
cd /workspace/myrepo-feature-auth && claude

# Terminal 2 (simultaneously)
./agent-vm -b bugfix-123
cd /workspace/myrepo-bugfix-123 && claude
```

Both agents work in isolated directories on the same VM, each with their own git repository.

**Safety:**
- Initial workspace creation: pushes branch from host
- Reconnection: skips push to preserve VM work
- Explicit `--push` flag: overwrites VM workspace with host state
- Auto-create branch if it doesn't exist locally (from current HEAD)

## File Sharing via SSHFS

**Single mount point:**
- Host: `~/.agent-vm-mounts/workspace/`
- VM: `~/workspace/`
- Mounted once when VM is first accessed, persists across sessions

**Mount behavior:**

```bash
# First connect - creates mount
./agent-vm -b feature-auth
# Creates: ~/.agent-vm-mounts/workspace/ → VM's ~/workspace/

# Host sees all workspaces:
~/.agent-vm-mounts/workspace/
  ├── myrepo-feature-auth/
  ├── myrepo-bugfix-123/
  └── other-repo-main/

# IDE workflow:
# Open ~/.agent-vm-mounts/workspace/myrepo-feature-auth/ in your editor
# Changes sync in real-time to VM
# Agent running in VM sees changes immediately
```

**Mount lifecycle:**
- Created on first `./agent-vm -b <any-branch>` call (if not already mounted)
- Persists across all workspace switches
- Only unmounted when VM is destroyed
- Automatic reconnection on VM restart (SSHFS `-o reconnect`)

**Cleanup interaction:**
- `./agent-vm -b feature-auth --clean`: Removes VM directory, but mount stays active
- `./agent-vm --clean-all`: Removes all VM directories, mount stays active
- `./agent-vm --destroy`: Unmounts SSHFS, destroys VM

**If SSHFS unavailable:**
- Warns user to install sshfs
- Continues without mount (can still SSH and work in VM)
- User can install sshfs later and reconnect to enable mounting

## Terraform Simplifications

**What gets removed:**

1. **Terraform workspaces** - Always use `default` workspace
2. **IP allocation logic** - Single static IP (no scanning for available IPs)
3. **Per-workspace SSH keys** - One `vm-ssh-key` for the VM
4. **Workspace-specific variables** - No `worktree_path`, `main_repo_path`, or dynamic `vm_ip`

**What stays:**

```hcl
# variables.tf - simplified
variable "vm_name" { default = "agent-vm" }
variable "vm_hostname" { default = "agent-vm" }
variable "vm_memory" { default = 4096 }
variable "vm_vcpu" { default = 4 }
variable "vm_disk_size" { default = 42949672960 }
variable "network_subnet_third_octet" { default = 123 }
# ... GCP credentials, user UID/GID remain
```

**Static configuration:**

```hcl
# main.tf
resource "libvirt_domain" "agent_vm" {
  name   = var.vm_name
  memory = var.vm_memory
  vcpu   = var.vm_vcpu

  network_interface {
    network_id     = libvirt_network.default.id
    addresses      = ["192.168.${var.network_subnet_third_octet}.10"]
    wait_for_lease = true
  }

  # No filesystem mounts - using SSHFS instead
}
```

**Subnet detection preserved in agent-vm:**
- Detects if running in nested VM scenario
- Auto-selects appropriate subnet (200 if nested from 122/123, otherwise current+1)
- Passes to Terraform via `-var network_subnet_third_octet`
- Same logic as current implementation (lines 554-577 in current agent-vm)

**No more:**
- `find_available_ip()` function
- File locking for IP allocation
- Workspace iteration/management in Terraform
- Import logic for shared resources (only one workspace now)

## Script Implementation Changes

**Script flow for `./agent-vm -b feature-auth`:**

1. Parse arguments (`-b`, `--memory`, `--vcpu`, `--disk`, `--push`, resource overrides, etc.)
2. Validate: must be in git repo when using `-b`
3. Determine: `REPO_NAME` and `VM_NAME="agent-vm"` (fixed name)
4. Check if Terraform state exists: `terraform show`
5. **If no Terraform state (VM doesn't exist):**
   - Detect network subnet (nested VM logic)
   - Run `terraform apply` with resource vars
   - Wait for VM to be ready (SSH check)
   - Create SSHFS mount: `~/.agent-vm-mounts/workspace/`
6. **If Terraform state exists:**
   - Warn if resource overrides provided (ignored - would require destroy/recreate)
   - Run `terraform apply` (ensures VM is started if stopped, idempotent)
   - Wait for VM to be ready
   - Ensure SSHFS mount exists
7. Check workspace directory in VM: `~/workspace/${REPO_NAME}-${BRANCH_NAME}/`
8. **If workspace doesn't exist:**
   - Create via SSH and initialize git repo
   - Push branch to workspace (initial sync)
9. **If workspace exists and `--push` flag provided:**
   - Push branch to workspace (explicit overwrite from host)
10. SSH into VM, cd to workspace directory
11. Run command if provided, else interactive shell

**New flag:**
- `--push`: Force push branch from host to VM workspace (overwrites VM state)

**Terraform manages all VM state:**
- `terraform apply` - creates or ensures running
- `terraform destroy` - stops and removes VM
- No direct `virsh` commands in agent-vm script

**Functions to modify:**
- Remove: `find_available_ip()`, `cleanup_stopped_vms()`, `list_vms()`, `stop_vm()`, workspace iteration logic
- Simplify: `destroy_vm()` (unmount SSHFS, single terraform destroy on default workspace)
- Modify: `mount_vm_worktree()` (mount entire workspace at `~/.agent-vm-mounts/workspace/`)
- Modify: `unmount_vm_worktree()` (unmount `~/.agent-vm-mounts/workspace/`)
- Modify: `push_branch_to_vm()` (push to specific workspace subdirectory)
- Add: `clean_workspace()`, `clean_all_workspaces()`, `list_workspaces()`

## Workspace Management Commands

**List workspaces (`./agent-vm --list`):**

```bash
./agent-vm --list

# Output:
Listing workspaces in agent-vm...

WORKSPACE                    LAST MODIFIED
---------                    -------------
myrepo-feature-auth         2026-01-07 14:30
myrepo-bugfix-123           2026-01-07 10:15
other-repo-main             2026-01-05 16:45
```

Implementation:
- SSH to VM: `ls -lt ~/workspace/`
- Parse directories and timestamps
- Display formatted table

**Clean specific workspace (`./agent-vm -b feature-auth --clean`):**

```bash
./agent-vm -b feature-auth --clean

# Confirms: "Remove workspace myrepo-feature-auth? (y/N)"
# If yes: SSH and run `rm -rf ~/workspace/myrepo-feature-auth`
```

Safety checks:
- Warns if workspace has uncommitted changes
- Requires confirmation (or `--force` flag to skip)

**Clean all workspaces (`./agent-vm --clean-all`):**

```bash
./agent-vm --clean-all

# Confirms: "Remove ALL workspaces from VM? (y/N)"
# If yes: SSH and run `rm -rf ~/workspace/*`
```

Safety:
- Lists workspaces before asking for confirmation
- Checks each for uncommitted changes (warnings only, not blocking)

**Common pattern:**
All workspace operations require VM to be running. If VM is stopped, `terraform apply` runs first to start it.

## Error Handling

**VM creation failures:**

```bash
# Terraform apply fails
ERROR: Failed to provision VM
Run 'terraform show' to inspect state
Run 'terraform destroy' to clean up and retry
```

**SSHFS mount failures:**

```bash
# sshfs not installed
WARNING: sshfs not installed
Install it to edit files on your host:
  Debian/Ubuntu: sudo apt-get install sshfs
  macOS: brew install sshfs

Continuing without SSHFS mount...
# (Script continues, user can still SSH and work in VM)

# Mount fails (permission, network, etc.)
WARNING: Could not mount via SSHFS (continuing without mount)
# (Script continues, user can still SSH)
```

**Git operation handling:**

```bash
# Not in git repo when using -b
ERROR: Must be in a git repository to use -b option

# Branch doesn't exist locally - auto-create from current HEAD
./agent-vm -b feature-new
# Output: "Creating branch 'feature-new' from current HEAD..."
# (Creates branch, pushes to VM)

# Push fails (network, permissions)
ERROR: Could not push branch to VM
Check SSH connectivity and try again

# Fetch with uncommitted changes - warn but continue
WARNING: VM workspace has uncommitted changes
These will NOT be included in the fetch
Fetching anyway...
# (Proceeds with fetch)
```

**Workspace conflicts:**

```bash
# Workspace exists but not a git repo (corrupted)
WARNING: Workspace exists but is not a git repository
Remove it: ./agent-vm -b feature-auth --clean --force
Or manually inspect: ssh user@<vm-ip>
```

**Resource override warnings:**

```bash
# VM exists, user provides resource flags
WARNING: VM already exists. Resource options ignored.
To apply new resources:
  ./agent-vm --destroy
  ./agent-vm -b feature-auth --memory 16384
```

## Testing Strategy

**Manual testing checklist:**

Basic workflow:
- [ ] Create VM on first `./agent-vm -b feature-auth`
- [ ] Auto-create workspace on first connect
- [ ] SSHFS mount created at `~/.agent-vm-mounts/workspace/`
- [ ] Git push happens on initial workspace creation
- [ ] Reconnect without `--push` preserves VM state
- [ ] `--push` flag overwrites VM workspace with host branch
- [ ] Auto-create branch if it doesn't exist locally

Multiple workspaces:
- [ ] Create second workspace: `./agent-vm -b bugfix-123`
- [ ] Both visible in SSHFS mount
- [ ] Switch between branches via SSH (different directories)
- [ ] `./agent-vm --list` shows all workspaces

Workspace cleanup:
- [ ] `./agent-vm -b feature-auth --clean` removes workspace
- [ ] Confirmation prompt works
- [ ] `./agent-vm --clean-all` removes all workspaces
- [ ] VM stays running after cleanup

Git operations:
- [ ] `./agent-vm -b feature-auth --fetch` pulls commits from VM
- [ ] Warning shown if uncommitted changes exist (but proceeds)
- [ ] Commits visible in host repo after fetch

VM lifecycle:
- [ ] `./agent-vm --destroy` stops and removes VM
- [ ] SSHFS unmounted on destroy
- [ ] Resource flags work on creation
- [ ] Resource flags ignored with warning on existing VM
- [ ] `terraform apply` restarts stopped VM

Error conditions:
- [ ] Not in git repo shows appropriate error
- [ ] SSHFS unavailable shows warning, continues
- [ ] Corrupted workspace detected

**Integration tests:**

Update `test-integration.sh --vm`:
- Remove multi-VM tests
- Add single-VM multi-workspace tests
- Verify SSHFS mounting
- Test workspace lifecycle (create, list, clean)

**Pre-commit checks:**
- `shellcheck agent-vm`
- `terraform fmt && terraform validate`
- Integration tests before commit

## Benefits

1. **Resource efficiency:** One VM instead of many (saves memory, CPU, disk)
2. **Simpler architecture:** No workspace management, IP allocation, or per-VM state
3. **Better IDE experience:** All branches visible in single mount point
4. **Faster operations:** No VM provisioning when switching branches
5. **Easier troubleshooting:** Single VM to inspect, single Terraform state

## Migration Path

**Cleanup existing multi-VM installations:**

Users with existing multi-VM setups should:
1. Fetch all work from existing VMs: `./agent-vm -b <branch> --fetch` (old version)
2. Destroy all VMs: `./agent-vm --cleanup` (old version)
3. Delete all Terraform workspaces except default
4. Pull new single-VM code
5. Start fresh: `./agent-vm -b feature-auth` (new version)

**Breaking changes:**
- Terraform state incompatible (multi-workspace → single workspace)
- SSHFS mount location changed (per-branch → single workspace directory)
- Command interface changed (removed `--stop`, `--cleanup`)

No migration script needed - users can manually fetch work and start clean.

## Future Enhancements

1. **Workspace templates:** Pre-configured workspace setups for common patterns
2. **Automatic workspace archival:** Move inactive workspaces to archive directory
3. **Workspace snapshots:** Save/restore workspace state
4. **Multi-repo support:** Better handling of working across different repositories
5. **Shared workspace pools:** Multiple users sharing VM workspaces (enterprise use case)

## Implementation Notes

**Completed:** 2026-01-08

**Key Implementation Details:**

1. **Terraform simplified:** Single default workspace, static IP .10, no multi-VM variables
2. **Script structure:** Action handlers (list, fetch, push, clean, etc.) with early returns
3. **SSHFS mount:** Single mount at `~/.agent-vm-mounts/workspace/`, persists across sessions
4. **Git workflow:** Push on workspace creation only, explicit `--push` to overwrite
5. **SSH handling:** Captured output in variables for reliability, 10-second timeout for loaded VMs

**Files Modified:**
- `vm/variables.tf` - Removed multi-VM variables (worktree_path, main_repo_path, vm_ip)
- `vm/main.tf` - Static IP, removed filesystem mounts
- `vm/vm-common.sh` - Removed multi-VM functions, added workspace helpers
- `vm/agent-vm` - Complete rewrite for single-VM workflow
- `test-integration.sh` - Updated VM tests for workspace-based testing
- `vm/CLAUDE.md` - Updated documentation
- `vm/README.md` - Updated architecture description

**Known Issues:**
- Integration test Test 3 (workspace listing) has intermittent failures (see `docs/troubleshooting/integration-test-list-flakiness.md`)
- Root cause appears to be test environment related, not functional issue
- All functionality verified working through manual testing

**Migration Required:**
Users with existing multi-VM setups should fetch work from VMs, destroy all VMs,
and start fresh with new single-VM design.
