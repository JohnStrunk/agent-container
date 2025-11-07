# VM Workspace Sync Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task.

**Goal:** Implement four helper scripts to sync files and git repositories
between host and VM workspace over SSH.

**Architecture:** Four bash scripts using rsync for directory sync and git
remotes over SSH for repository sync. All scripts share common patterns for
VM IP detection, SSH connectivity, and error handling.

**Tech Stack:** Bash, rsync, git, SSH, terraform CLI

---

## Task 1: Common Infrastructure Functions

**Files:**

- Create: `yolo-vm/vm-common.sh`

### Step 1: Write the common functions library

Create `yolo-vm/vm-common.sh`:

```bash
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

# Check if VM is reachable via SSH
# Args:
#   $1 - VM IP address
# Exits: 2 if VM not reachable
check_vm_reachable() {
  local vm_ip="$1"

  if ! ssh -o ConnectTimeout=5 -o BatchMode=yes \
       "debian@$vm_ip" "exit" 2>/dev/null; then
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
```

### Step 2: Make vm-common.sh executable

Run:

```bash
chmod +x yolo-vm/vm-common.sh
```

### Step 3: Verify vm-common.sh passes shellcheck

Run:

```bash
pre-commit run shellcheck --files yolo-vm/vm-common.sh
```

Expected: PASS

### Step 4: Commit vm-common.sh

```bash
git add yolo-vm/vm-common.sh
git commit -m "feat: add common functions for VM workspace sync scripts

Add shared library with VM IP detection, SSH connectivity checks, and
path utilities for use by all sync scripts.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 2: Implement vm-dir-push

**Files:**

- Create: `yolo-vm/vm-dir-push`

### Step 1: Write the vm-dir-push script

Create `yolo-vm/vm-dir-push`:

```bash
#!/bin/bash
set -e -o pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=vm-common.sh
source "$SCRIPT_DIR/vm-common.sh"

# Usage information
usage() {
  cat << EOF
Usage: $0 <local-directory> [workspace-subpath]

Push directory contents to VM workspace over SSH using rsync.

Arguments:
  local-directory     Local directory to push (required)
  workspace-subpath   Optional subdirectory within workspace (default: root)

Examples:
  $0 ./my-project              # Push to /home/debian/workspace/
  $0 ./my-project myapp        # Push to /home/debian/workspace/myapp/
  $0 ~/src/foo bar/baz         # Push to /home/debian/workspace/bar/baz/

Notes:
  - Directory contents (not the directory itself) are copied
  - Excludes: .git/, node_modules/, __pycache__/, .venv/, venv/
  - Uses rsync for efficient incremental transfers
EOF
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

LOCAL_DIR="$1"
WORKSPACE_SUBPATH="${2:-}"

# Validate local directory exists
if [[ ! -d "$LOCAL_DIR" ]]; then
  echo "Error: Local directory '$LOCAL_DIR' does not exist" >&2
  exit 1
fi

# Get absolute path
LOCAL_DIR=$(get_absolute_path "$LOCAL_DIR")

# Get VM IP
VM_IP=$(get_vm_ip "$SCRIPT_DIR")

# Check VM reachable
check_vm_reachable "$VM_IP"

# Construct remote path
if [[ -z "$WORKSPACE_SUBPATH" ]]; then
  REMOTE_PATH="/home/debian/workspace/"
else
  REMOTE_PATH="/home/debian/workspace/$WORKSPACE_SUBPATH/"
fi

# Create remote directory if it doesn't exist
ssh "debian@$VM_IP" "mkdir -p $REMOTE_PATH"

# Perform rsync
echo "Pushing $LOCAL_DIR to debian@$VM_IP:$REMOTE_PATH"

rsync -avz --progress \
  --exclude='.git/' \
  --exclude='node_modules/' \
  --exclude='__pycache__/' \
  --exclude='.venv/' \
  --exclude='venv/' \
  --exclude='.pytest_cache/' \
  --exclude='*.pyc' \
  --exclude='.DS_Store' \
  "$LOCAL_DIR/" \
  "debian@$VM_IP:$REMOTE_PATH"

echo "Done! Directory pushed successfully."
```

### Step 2: Make vm-dir-push executable

Run:

```bash
chmod +x yolo-vm/vm-dir-push
```

### Step 3: Verify vm-dir-push passes shellcheck

Run:

```bash
pre-commit run shellcheck --files yolo-vm/vm-dir-push
```

Expected: PASS

### Step 4: Manual test - push to workspace root

Run:

```bash
# Create test directory
mkdir -p /tmp/test-push
echo "test content" > /tmp/test-push/test.txt

# Push to VM
cd yolo-vm
./vm-dir-push /tmp/test-push

# Verify on VM
ssh debian@$(terraform output -raw vm_ip) "ls -la ~/workspace/ && cat ~/workspace/test.txt"
```

Expected: Output shows `test.txt` in workspace with "test content"

### Step 5: Manual test - push to subpath

Run:

```bash
# Push to subpath
./vm-dir-push /tmp/test-push testdir

# Verify on VM
ssh debian@$(terraform output -raw vm_ip) "ls -la ~/workspace/testdir/ && cat ~/workspace/testdir/test.txt"
```

Expected: Output shows `test.txt` in workspace/testdir/ with "test content"

### Step 6: Clean up vm-dir-push test data

Run:

```bash
ssh debian@$(terraform output -raw vm_ip) "rm -rf ~/workspace/test.txt ~/workspace/testdir"
rm -rf /tmp/test-push
```

### Step 7: Commit vm-dir-push script

```bash
git add yolo-vm/vm-dir-push
git commit -m "feat: add vm-dir-push script for directory sync to VM

Implements rsync-based directory push to VM workspace with optional
subpath support and common exclusions.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 3: Implement vm-dir-pull

**Files:**

- Create: `yolo-vm/vm-dir-pull`

### Step 1: Write the vm-dir-pull script

Create `yolo-vm/vm-dir-pull`:

```bash
#!/bin/bash
set -e -o pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=vm-common.sh
source "$SCRIPT_DIR/vm-common.sh"

# Usage information
usage() {
  cat << EOF
Usage: $0 <local-directory> [workspace-subpath]

Pull directory contents from VM workspace over SSH using rsync.

Arguments:
  local-directory     Local directory to pull into (required)
  workspace-subpath   Optional subdirectory within workspace (default: root)

Examples:
  $0 ./my-project              # Pull from /home/debian/workspace/
  $0 ./my-project myapp        # Pull from /home/debian/workspace/myapp/
  $0 ~/src/foo bar/baz         # Pull from /home/debian/workspace/bar/baz/

Notes:
  - Directory contents are mirrored (uses --delete)
  - Local directory will be created if it doesn't exist
  - Uses rsync for efficient incremental transfers
EOF
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

LOCAL_DIR="$1"
WORKSPACE_SUBPATH="${2:-}"

# Create local directory if it doesn't exist
mkdir -p "$LOCAL_DIR"

# Get absolute path
LOCAL_DIR=$(get_absolute_path "$LOCAL_DIR")

# Get VM IP
VM_IP=$(get_vm_ip "$SCRIPT_DIR")

# Check VM reachable
check_vm_reachable "$VM_IP"

# Construct remote path
if [[ -z "$WORKSPACE_SUBPATH" ]]; then
  REMOTE_PATH="/home/debian/workspace/"
else
  REMOTE_PATH="/home/debian/workspace/$WORKSPACE_SUBPATH/"
fi

# Check if remote path exists
if ! ssh "debian@$VM_IP" "test -d $REMOTE_PATH"; then
  echo "Error: Remote path '$REMOTE_PATH' does not exist on VM" >&2
  exit 1
fi

# Perform rsync
echo "Pulling from debian@$VM_IP:$REMOTE_PATH to $LOCAL_DIR"

rsync -avz --progress --delete \
  "debian@$VM_IP:$REMOTE_PATH" \
  "$LOCAL_DIR/"

echo "Done! Directory pulled successfully."
```

### Step 2: Make vm-dir-pull executable

Run:

```bash
chmod +x yolo-vm/vm-dir-pull
```

### Step 3: Verify vm-dir-pull passes shellcheck

Run:

```bash
pre-commit run shellcheck --files yolo-vm/vm-dir-pull
```

Expected: PASS

### Step 4: Manual test - pull from workspace root

Run:

```bash
# Create test data on VM
ssh debian@$(cd yolo-vm && terraform output -raw vm_ip) "echo 'pull test' > ~/workspace/pulltest.txt"

# Pull from VM
cd yolo-vm
./vm-dir-pull /tmp/test-pull

# Verify locally
cat /tmp/test-pull/pulltest.txt
```

Expected: Output shows "pull test"

### Step 5: Manual test - pull from subpath

Run:

```bash
# Create test data in subpath on VM
ssh debian@$(terraform output -raw vm_ip) \
  "mkdir -p ~/workspace/pulldir && echo 'subpath test' > ~/workspace/pulldir/sub.txt"

# Pull from subpath
./vm-dir-pull /tmp/test-pull-sub pulldir

# Verify locally
cat /tmp/test-pull-sub/sub.txt
```

Expected: Output shows "subpath test"

### Step 6: Clean up vm-dir-pull test data

Run:

```bash
ssh debian@$(terraform output -raw vm_ip) "rm -rf ~/workspace/pulltest.txt ~/workspace/pulldir"
rm -rf /tmp/test-pull /tmp/test-pull-sub
```

### Step 7: Commit vm-dir-pull

```bash
git add yolo-vm/vm-dir-pull
git commit -m "feat: add vm-dir-pull script for directory sync from VM

Implements rsync-based directory pull from VM workspace with optional
subpath support and mirror mode.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 4: Implement vm-git-push

**Files:**

- Create: `yolo-vm/vm-git-push`

### Step 1: Write the vm-git-push script

Create `yolo-vm/vm-git-push`:

```bash
#!/bin/bash
set -e -o pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=vm-common.sh
source "$SCRIPT_DIR/vm-common.sh"

# Usage information
usage() {
  cat << EOF
Usage: $0 <branch-name> [workspace-subpath]

Push a git branch to VM workspace over SSH.

Arguments:
  branch-name         Git branch to push (required)
  workspace-subpath   Optional subdirectory within workspace (default: root)

Examples:
  $0 feature-auth              # Push to /home/debian/workspace/
  $0 feature-auth myapp        # Push to /home/debian/workspace/myapp/
  $0 bugfix-123 path/to/repo   # Push to /home/debian/workspace/path/to/repo/

Notes:
  - Must be run from within a git repository
  - Creates/updates git repository on VM
  - Branch will be checked out on VM for working
  - Uses temporary git remote that is cleaned up after push
EOF
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

BRANCH_NAME="$1"
WORKSPACE_SUBPATH="${2:-}"

# Verify we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Error: Must run from within a git repository" >&2
  exit 3
fi

# Verify branch exists
if ! git rev-parse --verify "$BRANCH_NAME" > /dev/null 2>&1; then
  echo "Error: Branch '$BRANCH_NAME' not found" >&2
  exit 3
fi

# Get VM IP
VM_IP=$(get_vm_ip "$SCRIPT_DIR")

# Check VM reachable
check_vm_reachable "$VM_IP"

# Construct remote path
if [[ -z "$WORKSPACE_SUBPATH" ]]; then
  REMOTE_PATH="/home/debian/workspace"
else
  REMOTE_PATH="/home/debian/workspace/$WORKSPACE_SUBPATH"
fi

# Initialize git repository on VM if needed
echo "Initializing repository on VM at $REMOTE_PATH"
ssh "debian@$VM_IP" "mkdir -p $REMOTE_PATH && cd $REMOTE_PATH && \
  (git rev-parse --git-dir > /dev/null 2>&1 || \
   (git init && git config receive.denyCurrentBranch updateInstead))"

# Add temporary remote
REMOTE_NAME="vm-workspace-$$"
git remote add "$REMOTE_NAME" "ssh://debian@$VM_IP$REMOTE_PATH/.git"

# Ensure cleanup happens
cleanup() {
  git remote remove "$REMOTE_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Push branch to VM
echo "Pushing branch '$BRANCH_NAME' to VM..."
git push "$REMOTE_NAME" "$BRANCH_NAME:$BRANCH_NAME"

# Checkout branch on VM
echo "Checking out branch on VM..."
ssh "debian@$VM_IP" "cd $REMOTE_PATH && git checkout $BRANCH_NAME"

echo "Done! Branch '$BRANCH_NAME' pushed successfully to VM."
echo "SSH to VM and work in: $REMOTE_PATH"
```

### Step 2: Make vm-git-push script executable

Run:

```bash
chmod +x yolo-vm/vm-git-push
```

### Step 3: Verify vm-git-push script passes shellcheck

Run:

```bash
pre-commit run shellcheck --files yolo-vm/vm-git-push
```

Expected: PASS

### Step 4: Test vm-git-push with git repository

Run:

```bash
# Create test git repo
mkdir -p /tmp/test-git-repo
cd /tmp/test-git-repo
git init
echo "test" > file.txt
git add file.txt
git commit -m "Initial commit"
git checkout -b test-branch
echo "branch content" >> file.txt
git add file.txt
git commit -m "Branch commit"

# Push to VM
cd -
cd yolo-vm
./vm-git-push test-branch

# Verify on VM
ssh debian@$(terraform output -raw vm_ip) \
  "cd ~/workspace && git log --oneline && cat file.txt"
```

Expected: Shows both commits and "branch content" in file.txt

### Step 5: Manual test - error handling (non-git directory)

Run:

```bash
# Try from non-git directory
cd /tmp
../yolo-vm/vm-git-push test-branch 2>&1
```

Expected: Error message "Must run from within a git repository"

### Step 6: Clean up vm-git-push test data

Run:

```bash
ssh debian@$(cd yolo-vm && terraform output -raw vm_ip) \
  "rm -rf ~/workspace/.git ~/workspace/file.txt"
rm -rf /tmp/test-git-repo
```

### Step 7: Commit vm-git-push

```bash
git add yolo-vm/vm-git-push
git commit -m "feat: add vm-git-push script for git branch sync to VM

Implements git remote-based branch push to VM workspace with automatic
repository initialization and branch checkout.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 5: Implement vm-git-fetch

**Files:**

- Create: `yolo-vm/vm-git-fetch`

### Step 1: Write the vm-git-fetch script

Create `yolo-vm/vm-git-fetch`:

```bash
#!/bin/bash
set -e -o pipefail

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source common functions
# shellcheck source=vm-common.sh
source "$SCRIPT_DIR/vm-common.sh"

# Usage information
usage() {
  cat << EOF
Usage: $0 <branch-name> [workspace-subpath]

Fetch a git branch from VM workspace over SSH.

Arguments:
  branch-name         Git branch to fetch (required)
  workspace-subpath   Optional subdirectory within workspace (default: root)

Examples:
  $0 feature-auth              # Fetch from /home/debian/workspace/
  $0 feature-auth myapp        # Fetch from /home/debian/workspace/myapp/
  $0 bugfix-123 path/to/repo   # Fetch from /home/debian/workspace/path/to/repo/

Notes:
  - Must be run from within a git repository
  - Fetches commits from VM and updates local branch
  - Uses temporary git remote that is cleaned up after fetch
  - After fetch, checkout the branch and review changes
EOF
}

# Parse arguments
if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

if [[ "$1" == "-h" || "$1" == "--help" ]]; then
  usage
  exit 0
fi

BRANCH_NAME="$1"
WORKSPACE_SUBPATH="${2:-}"

# Verify we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "Error: Must run from within a git repository" >&2
  exit 3
fi

# Get VM IP
VM_IP=$(get_vm_ip "$SCRIPT_DIR")

# Check VM reachable
check_vm_reachable "$VM_IP"

# Construct remote path
if [[ -z "$WORKSPACE_SUBPATH" ]]; then
  REMOTE_PATH="/home/debian/workspace"
else
  REMOTE_PATH="/home/debian/workspace/$WORKSPACE_SUBPATH"
fi

# Verify remote repository exists
if ! ssh "debian@$VM_IP" "test -d $REMOTE_PATH/.git"; then
  echo "Error: Git repository not found at $REMOTE_PATH on VM" >&2
  echo "Did you push with vm-git-push first?" >&2
  exit 1
fi

# Verify branch exists on VM
if ! ssh "debian@$VM_IP" \
     "cd $REMOTE_PATH && git rev-parse --verify $BRANCH_NAME > /dev/null 2>&1"; then
  echo "Error: Branch '$BRANCH_NAME' not found on VM" >&2
  exit 3
fi

# Add temporary remote
REMOTE_NAME="vm-workspace-$$"
git remote add "$REMOTE_NAME" "ssh://debian@$VM_IP$REMOTE_PATH/.git"

# Ensure cleanup happens
cleanup() {
  git remote remove "$REMOTE_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# Fetch branch from VM
echo "Fetching branch '$BRANCH_NAME' from VM..."
git fetch "$REMOTE_NAME" "$BRANCH_NAME:$BRANCH_NAME"

echo "Done! Branch '$BRANCH_NAME' fetched successfully."
echo ""
echo "To review changes:"
echo "  git checkout $BRANCH_NAME"
echo "  git log --oneline -10"
echo "  git diff main..$BRANCH_NAME"
echo ""
echo "To merge when ready:"
echo "  git checkout main"
echo "  git merge $BRANCH_NAME"
```

### Step 2: Make vm-git-fetch script executable

Run:

```bash
chmod +x yolo-vm/vm-git-fetch
```

### Step 3: Verify vm-git-fetch script passes shellcheck

Run:

```bash
pre-commit run shellcheck --files yolo-vm/vm-git-fetch
```

Expected: PASS

### Step 4: Manual test - fetch after vm-git-push

Run:

```bash
# Create test git repo
mkdir -p /tmp/test-git-fetch
cd /tmp/test-git-fetch
git init
echo "initial" > file.txt
git add file.txt
git commit -m "Initial commit"
git checkout -b fetch-test
echo "local change" >> file.txt
git add file.txt
git commit -m "Local commit"

# Push to VM
cd -
cd yolo-vm
./vm-git-push fetch-test

# Make changes on VM
ssh debian@$(terraform output -raw vm_ip) \
  "cd ~/workspace && echo 'VM change' >> file.txt && \
   git add file.txt && git commit -m 'VM commit'"

# Fetch back
./vm-git-fetch fetch-test

# Verify in test repo
cd /tmp/test-git-fetch
git checkout fetch-test
git log --oneline
cat file.txt
```

Expected: Shows both "Local commit" and "VM commit", file contains "VM change"

### Step 5: Manual test - error handling (no repo on VM)

Run:

```bash
# Clean VM workspace
ssh debian@$(cd yolo-vm && terraform output -raw vm_ip) \
  "rm -rf ~/workspace/.git ~/workspace/file.txt"

# Try to fetch
cd yolo-vm
./vm-git-fetch fetch-test 2>&1
```

Expected: Error message "Git repository not found at /home/debian/workspace on VM"

### Step 6: Clean up vm-git-fetch test data

Run:

```bash
rm -rf /tmp/test-git-fetch
```

### Step 7: Commit vm-git-fetch

```bash
git add yolo-vm/vm-git-fetch
git commit -m "feat: add vm-git-fetch script for git branch sync from VM

Implements git remote-based branch fetch from VM workspace with
validation and helpful next-step instructions.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 6: Update Documentation

**Files:**

- Modify: `yolo-vm/README.md`

### Step 1: Add workspace sync section to README

Add after the "Using AI Coding Agents" section in `yolo-vm/README.md`:

```markdown
## Syncing Files with VM Workspace

Four helper scripts enable syncing files and git repositories between the
host and VM workspace:

### Directory Sync

**Push directory to VM:**

```bash
./vm-dir-push <local-directory> [workspace-subpath]

# Examples:
./vm-dir-push ./my-project              # → /home/debian/workspace/
./vm-dir-push ./my-project myapp        # → /home/debian/workspace/myapp/
```

**Pull directory from VM:**

```bash
./vm-dir-pull <local-directory> [workspace-subpath]

# Examples:
./vm-dir-pull ./my-project              # ← /home/debian/workspace/
./vm-dir-pull ./my-project myapp        # ← /home/debian/workspace/myapp/
```

### Git Repository Sync

**Push git branch to VM:**

```bash
./vm-git-push <branch-name> [workspace-subpath]

# Examples:
./vm-git-push feature-auth              # → /home/debian/workspace/
./vm-git-push feature-auth myapp        # → /home/debian/workspace/myapp/
```

**Fetch git branch from VM:**

```bash
./vm-git-fetch <branch-name> [workspace-subpath]

# Examples:
./vm-git-fetch feature-auth             # ← /home/debian/workspace/
./vm-git-fetch feature-auth myapp       # ← /home/debian/workspace/myapp/

# Then review and merge
git checkout feature-auth
git log
git checkout main
git merge feature-auth
```

### Typical Workflow

**For git repositories:**

```bash
# 1. Push your branch to VM
./vm-git-push feature-branch

# 2. SSH into VM and work with AI agent
./vm-connect.sh
claude-code  # Work on the feature

# 3. Back on host, fetch the changes
./vm-git-fetch feature-branch

# 4. Review and merge
git checkout feature-branch
git log
git checkout main
git merge feature-branch
```

**For simple directories:**

```bash
# 1. Push directory to VM
./vm-dir-push ./my-project

# 2. SSH into VM and work
./vm-connect.sh
cd ~/workspace/my-project
# Make changes...

# 3. Pull changes back
./vm-dir-pull ./my-project
```

### Step 2: Verify markdown passes pre-commit

Run:

```bash
pre-commit run markdownlint --files yolo-vm/README.md
```

Expected: PASS (you may need to adjust line lengths)

### Step 3: Commit documentation update

```bash
git add yolo-vm/README.md
git commit -m "docs: add workspace sync scripts documentation

Document the four new workspace sync helper scripts (vm-dir-push,
vm-dir-pull, vm-git-push, vm-git-fetch) with usage examples and
typical workflows.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Task 7: Final Verification and Testing

**Files:**

- Test: All four scripts with end-to-end workflow

### Step 1: End-to-end git workflow test

Run:

```bash
# Create test repository
mkdir -p /tmp/e2e-test
cd /tmp/e2e-test
git init
echo "# Test Project" > README.md
git add README.md
git commit -m "Initial commit"
git checkout -b e2e-branch

# Push to VM
cd -
cd yolo-vm
./vm-git-push e2e-branch

# Make changes on VM
ssh debian@$(terraform output -raw vm_ip) << 'EOFSSH'
cd ~/workspace
echo "Changes from VM" >> README.md
git add README.md
git commit -m "VM changes"
EOFSSH

# Fetch back
./vm-git-fetch e2e-branch

# Verify
cd /tmp/e2e-test
git checkout e2e-branch
git log --oneline
grep "Changes from VM" README.md
```

Expected: Shows "VM changes" commit and file contains "Changes from VM"

### Step 2: End-to-end directory workflow test

Run:

```bash
# Create test directory
mkdir -p /tmp/e2e-dir
echo "Host file" > /tmp/e2e-dir/host.txt

# Push to VM
cd yolo-vm
./vm-dir-push /tmp/e2e-dir

# Make changes on VM
ssh debian@$(terraform output -raw vm_ip) "echo 'VM file' > ~/workspace/vm.txt"

# Pull back
./vm-dir-pull /tmp/e2e-dir

# Verify
ls /tmp/e2e-dir/
cat /tmp/e2e-dir/vm.txt
```

Expected: Directory contains both host.txt and vm.txt, vm.txt says "VM file"

### Step 3: Test error conditions

Run:

```bash
# Test non-existent directory
./vm-dir-push /nonexistent 2>&1 | grep "does not exist"

# Test from non-git repo
cd /tmp
./vm-git-push test-branch 2>&1 | grep "git repository"

# Test non-existent branch
cd /tmp/e2e-test
./vm-git-push nonexistent-branch 2>&1 | grep "not found"
```

Expected: Each command shows appropriate error message

### Step 4: Clean up all test data

Run:

```bash
# Clean VM workspace
ssh debian@$(cd yolo-vm && terraform output -raw vm_ip) "rm -rf ~/workspace/*"

# Clean local test directories
rm -rf /tmp/e2e-test /tmp/e2e-dir
```

### Step 5: Run all pre-commit checks

Run:

```bash
pre-commit run --all-files
```

Expected: All checks PASS

### Step 6: Commit verification checkpoint

```bash
git add -A
git commit -m "test: verify end-to-end workspace sync workflows

Completed manual testing of all four sync scripts with both git and
directory workflows. All error conditions handled correctly.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

## Completion Checklist

- [ ] Task 1: Common infrastructure functions implemented
- [ ] Task 2: vm-dir-push implemented and tested
- [ ] Task 3: vm-dir-pull implemented and tested
- [ ] Task 4: vm-git-push implemented and tested
- [ ] Task 5: vm-git-fetch implemented and tested
- [ ] Task 6: Documentation updated in README
- [ ] Task 7: End-to-end verification complete
- [ ] All pre-commit checks passing
- [ ] All scripts have execute permissions
- [ ] All commits follow conventional commit format

## Notes for Implementation

**DRY principles:**

- Common functions in vm-common.sh prevent duplication
- All scripts source the common library
- Consistent error handling patterns

**YAGNI principles:**

- No fancy features like dry-run mode or progress bars yet
- No workspace listing or management (can add later)
- Simple direct implementation of core functionality

**Testing approach:**

- Manual testing with real VM interaction
- Test both happy path and error conditions
- Clean up test data after each test

**Commit frequency:**

- One commit per task (7 total)
- Each commit is independently functional
- Follows conventional commit format
