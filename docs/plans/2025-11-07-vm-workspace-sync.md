# VM Workspace Sync Design

**Date:** 2025-11-07

**Status:** Approved

## Overview

This design adds helper scripts to synchronize files and git repositories
between the host and the yolo-vm workspace directory over SSH. The scripts
enable a workflow where code is pushed to the VM, AI coding agents (Claude
Code) work on it autonomously, and results are pulled back to the host.

## Use Cases

### Primary Workflow

1. Developer has code on host (either simple directory or git repository)
2. Push code to VM workspace using helper script
3. SSH into VM and run AI coding agent (Claude Code)
4. Agent makes changes, creates commits (for git repos)
5. Pull results back to host using helper script
6. Review and integrate changes on host

### Scenario 1: Simple Directory Sync

For non-git projects or directories that don't need version control:

- Copy directory contents to VM workspace
- AI agent modifies files
- Copy modified contents back to host

### Scenario 2: Git Repository Sync

For git repositories where commit history and branching matter:

- Push git branch to VM workspace
- AI agent creates commits on that branch
- Fetch commits back to host repository
- Review commits using standard git tools
- Merge branch when satisfied

## Requirements

### Functional Requirements

- Support both directory sync and git repository workflows
- Use SSH as transport (already configured with keys)
- Unidirectional sync: host → VM at start, VM → host at end
- Optional workspace subdirectories for organizing multiple projects
- Default behavior: place files directly in workspace root
- Scripts should be idempotent and safe to re-run

### Non-Functional Requirements

- Efficient transfers (incremental, compressed where applicable)
- Clear error messages with actionable suggestions
- Consistent interface across all four scripts
- Follow existing VM helper script patterns
- No additional dependencies (use tools available in Debian)

## Design

### Script Overview

Four new helper scripts in `yolo-vm/` directory:

| Script | Purpose | Transport |
|--------|---------|-----------|
| `vm-dir-push` | Copy directory to VM | rsync over SSH |
| `vm-dir-pull` | Copy directory from VM | rsync over SSH |
| `vm-git-push` | Push git branch to VM | git over SSH |
| `vm-git-fetch` | Fetch git commits from VM | git over SSH |

### Common Patterns

All scripts share:

- Consistent argument structure: `<primary-arg> [workspace-subpath]`
- VM IP detection via terraform output
- SSH connection to `debian@<vm-ip>`
- Workspace base directory: `/home/debian/workspace/`
- Default behavior: workspace root (no subpath)
- Optional subpath for organization

### vm-dir-push

**Interface:**

```bash
./vm-dir-push <local-directory> [workspace-subpath]
```

**Behavior:**

- Validates local directory exists
- Gets VM IP from terraform state
- Uses rsync to copy directory contents to VM
- Default target: `/home/debian/workspace/`
- With subpath: `/home/debian/workspace/<subpath>/`
- Excludes: `.git/`, `node_modules/`, `__pycache__/`, `.venv/`, etc.
- Shows progress during transfer

**Implementation:**

```bash
# Key rsync command structure
rsync -avz --progress \
  --exclude='.git/' \
  --exclude='node_modules/' \
  --exclude='__pycache__/' \
  --exclude='.venv/' \
  "$LOCAL_DIR/" \
  "debian@$VM_IP:~/workspace/$SUBPATH/"
```

**Examples:**

```bash
./vm-dir-push ./my-project
# → /home/debian/workspace/* (contents directly)

./vm-dir-push ./my-project myapp
# → /home/debian/workspace/myapp/*

./vm-dir-push ~/src/foo bar/baz
# → /home/debian/workspace/bar/baz/*
```

### vm-dir-pull

**Interface:**

```bash
./vm-dir-pull <local-directory> [workspace-subpath]
```

**Behavior:**

- Gets VM IP from terraform state
- Uses rsync to copy from VM to local directory
- Default source: `/home/debian/workspace/`
- With subpath: `/home/debian/workspace/<subpath>/`
- Uses `--delete` to ensure exact mirror
- Creates local directory if it doesn't exist
- Shows progress during transfer

**Implementation:**

```bash
# Key rsync command structure
rsync -avz --progress --delete \
  "debian@$VM_IP:~/workspace/$SUBPATH/" \
  "$LOCAL_DIR/"
```

**Examples:**

```bash
./vm-dir-pull ./my-project
# ← /home/debian/workspace/* (all contents)

./vm-dir-pull ./my-project myapp
# ← /home/debian/workspace/myapp/*
```

### vm-git-push

**Interface:**

```bash
./vm-git-push <branch-name> [workspace-subpath]
```

**Behavior:**

- Must be run from within a git repository
- Validates branch exists locally
- Gets VM IP from terraform state
- Determines target path on VM
- Initializes git repository on VM if needed
- Adds temporary git remote pointing to VM
- Pushes specified branch to VM
- Checks out branch on VM (non-bare repo)
- Removes temporary remote
- Shows summary of what was pushed

**Implementation approach:**

1. Validate we're in a git repo: `git rev-parse --git-dir`
2. Check branch exists: `git rev-parse --verify "$BRANCH"`
3. Determine workspace path (root or subpath)
4. SSH to VM and initialize repo if needed
5. Add temporary remote: `git remote add vm-workspace
   ssh://debian@$VM_IP/~/workspace/$SUBPATH/.git`
6. Push branch: `git push vm-workspace "$BRANCH:$BRANCH"`
7. SSH to VM: `cd ~/workspace/$SUBPATH && git checkout "$BRANCH"`
8. Remove remote: `git remote remove vm-workspace`

**Git repository setup on VM:**

```bash
# First-time setup via SSH
ssh debian@$VM_IP "cd ~/workspace/$SUBPATH && \
  git init && \
  git config receive.denyCurrentBranch updateInstead"
```

The `receive.denyCurrentBranch updateInstead` allows pushing to checked-out
branch.

**Examples:**

```bash
./vm-git-push feature-auth
# → /home/debian/workspace/.git (branch: feature-auth)

./vm-git-push feature-auth myapp
# → /home/debian/workspace/myapp/.git

./vm-git-push feature-auth path/to/repo
# → /home/debian/workspace/path/to/repo/.git
```

### vm-git-fetch

**Interface:**

```bash
./vm-git-fetch <branch-name> [workspace-subpath]
```

**Behavior:**

- Must be run from within a git repository
- Gets VM IP from terraform state
- Determines source path on VM (must match push location)
- Adds temporary git remote pointing to VM
- Fetches specified branch from VM
- Updates local branch with fetched commits
- Removes temporary remote
- Displays summary of commits fetched

**Implementation approach:**

1. Validate we're in a git repo
2. Determine workspace path (must match what was used in push)
3. Add temporary remote: `git remote add vm-workspace
   ssh://debian@$VM_IP/~/workspace/$SUBPATH/.git`
4. Fetch branch: `git fetch vm-workspace "$BRANCH:$BRANCH"`
5. Remove remote: `git remote remove vm-workspace`
6. Show log: `git log "$BRANCH" --oneline -10`

**Examples:**

```bash
./vm-git-fetch feature-auth
# Fetches from /home/debian/workspace/

./vm-git-fetch feature-auth myapp
# Fetches from /home/debian/workspace/myapp/

# Review and merge
git checkout feature-auth
git log
git diff main..feature-auth
git checkout main
git merge feature-auth
```

### Common Infrastructure

#### VM IP Detection

```bash
get_vm_ip() {
  local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  cd "$script_dir" || exit 1

  local vm_ip
  vm_ip=$(terraform output -raw vm_ip 2>/dev/null)

  if [[ -z "$vm_ip" || "$vm_ip" == "IP not yet assigned" ]]; then
    echo "Error: VM IP not available" >&2
    echo "Run 'terraform apply' first" >&2
    exit 1
  fi

  echo "$vm_ip"
}
```

#### SSH Reachability Check

```bash
check_vm_reachable() {
  local vm_ip="$1"

  if ! ssh -o ConnectTimeout=5 -o BatchMode=yes \
       "debian@$vm_ip" "exit" 2>/dev/null; then
    echo "Error: Cannot connect to VM at $vm_ip" >&2
    echo "Check that VM is running: virsh list" >&2
    exit 1
  fi
}
```

#### Script Structure

All scripts follow this pattern:

```bash
#!/bin/bash
set -e -o pipefail

# Get script directory for terraform commands
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions (if we create a common lib)
# source "$SCRIPT_DIR/vm-common.sh"

# Argument parsing and validation
# ...

# Get VM IP
VM_IP=$(get_vm_ip)

# Check VM reachable
check_vm_reachable "$VM_IP"

# Perform main operation
# ...
```

## Error Handling

### Common Error Scenarios

| Error | Detection | User Message |
|-------|-----------|--------------|
| VM not running | terraform output | "VM not running. Run './vm-up.sh'" |
| SSH fails | ssh exit code | "Cannot connect to VM" |
| Not a git repo | git rev-parse | "Must run from git repository" |
| Branch missing | git rev-parse | "Branch 'X' not found" |
| Dir doesn't exist | test -d | "Directory 'X' not found" |
| Remote path missing | ssh test -d | "Workspace path 'X' not on VM" |

### Exit Codes

- `0` - Success
- `1` - General error (invalid arguments, preconditions not met)
- `2` - SSH/network error
- `3` - Git operation error

## Testing Strategy

### Manual Testing Checklist

**Directory sync:**

- [ ] Push empty directory
- [ ] Push directory with files
- [ ] Push with subpath
- [ ] Pull from workspace root
- [ ] Pull from subpath
- [ ] Pull to non-existent local directory
- [ ] Verify excluded patterns work (.git/, node_modules/, etc.)

**Git sync:**

- [ ] Push branch to workspace root
- [ ] Push branch to subpath
- [ ] Push when VM repo doesn't exist (first time)
- [ ] Push when VM repo exists (update)
- [ ] Fetch after commits made on VM
- [ ] Fetch when local branch doesn't exist
- [ ] Fetch when local branch exists (update)
- [ ] Verify full commit history preserved

**Error conditions:**

- [ ] Run when VM is not running
- [ ] Run git commands from non-git directory
- [ ] Try to fetch from non-existent workspace path
- [ ] Push non-existent branch

### Integration Testing

Full workflow test:

```bash
# Setup
cd ~/test-project
git init
echo "test" > file.txt
git add file.txt
git commit -m "Initial commit"
git checkout -b test-branch

# Push to VM
cd ~/yolo-vm
./vm-git-push test-branch

# Modify on VM
ssh debian@$(terraform output -raw vm_ip)
cd ~/workspace
echo "modified" >> file.txt
git add file.txt
git commit -m "Modified on VM"
exit

# Fetch back
./vm-git-fetch test-branch

# Verify
cd ~/test-project
git checkout test-branch
git log --oneline  # Should show both commits
cat file.txt       # Should contain "modified"
```

## Security Considerations

- All transfers use SSH with existing key-based authentication
- No passwords or credentials in scripts
- Scripts only operate on user-specified paths
- No privilege escalation required
- VM workspace is owned by `debian` user (non-root)

## Future Enhancements

Potential future improvements:

1. **Automatic conflict detection**: Warn if pulling would overwrite
   uncommitted local changes
2. **Dry-run mode**: Add `--dry-run` flag to preview operations
3. **Multiple workspace management**: Helper to list/clean workspace
   contents
4. **Background sync**: Watch mode for continuous sync during development
5. **Compression options**: Configurable compression levels for rsync
6. **Git worktree support**: Integrate with host-side worktrees
7. **Progress bars**: Enhanced visual feedback for large transfers

## File Structure

```text
yolo-vm/
├── vm-up.sh              # Existing: Start VM
├── vm-down.sh            # Existing: Stop VM
├── vm-connect.sh         # Existing: SSH to VM
├── vm-dir-push           # New: Push directory to VM
├── vm-dir-pull           # New: Pull directory from VM
├── vm-git-push           # New: Push git branch to VM
└── vm-git-fetch          # New: Fetch git branch from VM
```

All new scripts should be executable (`chmod +x`).

## References

- [rsync documentation](https://rsync.samba.org/documentation.html)
- [git push options](https://git-scm.com/docs/git-push)
- [git remote configuration](https://git-scm.com/docs/git-remote)
- SSH configuration: [yolo-vm/README.md](../yolo-vm/README.md)
