# Automatic Pre-commit Hook Installation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically install pre-commit hooks when creating new workspaces in agent-vm

**Architecture:** Add a new function `install_precommit_hooks` that checks for `.pre-commit-config.yaml` and runs `pre-commit install` via SSH. Call this function immediately after successful workspace creation.

**Tech Stack:** Bash, SSH, pre-commit

---

## Task 1: Add install_precommit_hooks Function

**Files:**
- Modify: `vm/agent-vm` (add function after line 375, before `usage` function)

**Step 1: Add the install_precommit_hooks function**

Add this function after the `warn_resource_overrides_ignored` function (around line 375):

```bash
function install_precommit_hooks {
  local vm_ip="$1"
  local workspace_name="$2"
  local ssh_key="$SCRIPT_DIR/vm-ssh-key"

  # Check if .pre-commit-config.yaml exists in workspace
  if ssh -i "$ssh_key" -o StrictHostKeyChecking=no "user@$vm_ip" \
     "test -f ~/workspace/$workspace_name/.pre-commit-config.yaml" 2>/dev/null < /dev/null; then

    # Install pre-commit hooks
    if ssh -i "$ssh_key" -o StrictHostKeyChecking=no "user@$vm_ip" \
       "cd ~/workspace/$workspace_name && pre-commit install" 2>/dev/null < /dev/null; then
      echo "✓ Pre-commit hooks installed"
    else
      echo ""
      echo "⚠️  WARNING: Could not install pre-commit hooks"
      echo "You can install them manually: cd ~/workspace/$workspace_name && pre-commit install"
      echo ""
    fi
  fi
}
```

**Step 2: Verify syntax**

Run: `bash -n vm/agent-vm`
Expected: No output (syntax is valid)

**Step 3: Commit the function**

```bash
git add vm/agent-vm
git commit -m "feat: add install_precommit_hooks function

Add function to automatically detect and install pre-commit hooks
when creating new workspaces. Checks for .pre-commit-config.yaml
and runs pre-commit install with graceful error handling.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Integrate Function into Workspace Creation Flow

**Files:**
- Modify: `vm/agent-vm:753-761` (workspace creation section)

**Step 1: Add function call after push_branch_to_vm**

Locate the section around line 753 that looks like:

```bash
# If workspace doesn't exist or --push flag provided, push branch
if [[ "$WORKSPACE_EXISTS" == "false" ]]; then
  echo "Creating new workspace: $WORKSPACE_NAME"
  push_branch_to_vm "$VM_IP" "$BRANCH_NAME" "$WORKSPACE_NAME"
else
  echo "Using existing workspace: $WORKSPACE_NAME"
fi
```

Modify it to:

```bash
# If workspace doesn't exist or --push flag provided, push branch
if [[ "$WORKSPACE_EXISTS" == "false" ]]; then
  echo "Creating new workspace: $WORKSPACE_NAME"
  push_branch_to_vm "$VM_IP" "$BRANCH_NAME" "$WORKSPACE_NAME"
  install_precommit_hooks "$VM_IP" "$WORKSPACE_NAME"
else
  echo "Using existing workspace: $WORKSPACE_NAME"
fi
```

**Step 2: Verify syntax**

Run: `bash -n vm/agent-vm`
Expected: No output (syntax is valid)

**Step 3: Commit the integration**

```bash
git add vm/agent-vm
git commit -m "feat: auto-install pre-commit hooks on workspace creation

Call install_precommit_hooks after creating new workspaces.
Only runs on workspace creation, not on reconnection.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Test with Repository That Has Pre-commit Config

**Files:**
- Test: `vm/agent-vm` (manual testing with current repository)

**Step 1: Verify current repository has .pre-commit-config.yaml**

Run: `test -f .pre-commit-config.yaml && echo "Present" || echo "Missing"`
Expected: `Present`

**Step 2: Create test workspace**

Run: `cd vm && ./agent-vm -b test-precommit-install`
Expected output should include:
```
Creating new workspace: agent-container-precommit-test-precommit-install
✓ Branch 'test-precommit-install' pushed to VM workspace
✓ Pre-commit hooks installed
```

**Step 3: Verify hooks are installed in VM**

Run: `cd vm && ./agent-vm -b test-precommit-install -- "ls -la .git/hooks/pre-commit"`
Expected: File exists with executable permissions

**Step 4: Clean up test workspace**

Run: `cd vm && ./agent-vm -b test-precommit-install --clean`
Expected: Workspace removed successfully

---

## Task 4: Test with Repository Without Pre-commit Config

**Files:**
- Test: Create temporary test without `.pre-commit-config.yaml`

**Step 1: Create test branch without pre-commit config**

```bash
git checkout -b test-no-precommit
git rm .pre-commit-config.yaml
git commit -m "test: remove pre-commit config for testing"
```

**Step 2: Create test workspace**

Run: `cd vm && ./agent-vm -b test-no-precommit`
Expected output should NOT include pre-commit installation message (silent skip)

**Step 3: Verify hooks are NOT installed**

Run: `cd vm && ./agent-vm -b test-no-precommit -- "test -f .git/hooks/pre-commit && echo 'exists' || echo 'not exists'"`
Expected: `not exists`

**Step 4: Clean up test**

```bash
cd vm && ./agent-vm -b test-no-precommit --clean
git checkout precommit
git branch -D test-no-precommit
```

---

## Task 5: Test Reconnection Behavior

**Files:**
- Test: `vm/agent-vm` (verify function not called on reconnection)

**Step 1: Create workspace**

Run: `cd vm && ./agent-vm -b test-reconnect`
Expected: `✓ Pre-commit hooks installed` appears

**Step 2: Disconnect and reconnect**

Run: `cd vm && ./agent-vm -b test-reconnect`
Expected: Should show "Using existing workspace" and NO pre-commit installation message

**Step 3: Clean up**

Run: `cd vm && ./agent-vm -b test-reconnect --clean`

---

## Task 6: Update Documentation

**Files:**
- Modify: `vm/CLAUDE.md` (add note about automatic pre-commit hook installation)

**Step 1: Add section about pre-commit auto-installation**

Find the "Pre-commit Quality Checks" section (around line 99) and update it to:

```markdown
### Pre-commit Quality Checks

Pre-commit hooks are automatically installed when creating a new workspace
(if `.pre-commit-config.yaml` is present in the repository).

Run pre-commit after making changes:

```bash
pre-commit run --files <filename>
```
```

**Step 2: Commit documentation update**

```bash
git add vm/CLAUDE.md
git commit -m "docs: document automatic pre-commit hook installation

Update CLAUDE.md to mention that pre-commit hooks are automatically
installed during workspace creation.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Run Pre-commit on Modified Files

**Files:**
- All modified files

**Step 1: Run pre-commit checks**

Run: `pre-commit run --files vm/agent-vm vm/CLAUDE.md`
Expected: All checks pass

**Step 2: Fix any issues if needed**

If checks fail, fix the issues and commit:

```bash
git add vm/agent-vm vm/CLAUDE.md
git commit -m "fix: address pre-commit issues"
```

---

## Task 8: Final Verification

**Files:**
- Test: Complete end-to-end workflow

**Step 1: Create fresh workspace with current branch**

Run: `cd vm && ./agent-vm -b final-test`
Expected:
- Workspace created successfully
- Pre-commit hooks installed message appears

**Step 2: Make a test commit in the VM to verify hooks work**

Run:
```bash
cd vm && ./agent-vm -b final-test -- "bash -c 'echo test > test.txt && git add test.txt && git commit -m \"test commit\"'"
```
Expected: Pre-commit hooks run on the commit

**Step 3: Clean up**

Run: `cd vm && ./agent-vm -b final-test --clean`

**Step 4: Final commit of plan**

```bash
git add docs/plans/2026-01-09-precommit-auto-install.md
git commit -m "docs: mark implementation plan as complete

All tasks completed and tested successfully.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Success Criteria

- ✓ Function added to agent-vm script
- ✓ Function called during workspace creation only
- ✓ Pre-commit hooks installed for repos with config file
- ✓ Silent skip for repos without config file
- ✓ No installation on reconnection
- ✓ Documentation updated
- ✓ All pre-commit checks pass
- ✓ End-to-end testing complete

---

## Notes

- Function uses same SSH pattern as other agent-vm operations
- Error handling is graceful (warnings, no failures)
- No changes needed to cloud-init or Terraform
- Pre-commit is already installed on VM via python-packages.txt
