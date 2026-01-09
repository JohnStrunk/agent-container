# Automatic Pre-commit Hook Installation for agent-vm

**Date:** 2026-01-09
**Status:** Approved

## Overview

Automatically configure pre-commit hooks when creating new workspaces in agent-vm. This ensures linting and code quality checks run on every commit, maintaining code quality standards without manual setup.

## Problem Statement

When creating a new workspace with `agent-vm`, repositories that have `.pre-commit-config.yaml` require manual hook installation (`pre-commit install`). This extra step is easy to forget and delays the development workflow.

## Solution

Automatically detect `.pre-commit-config.yaml` and run `pre-commit install` during workspace creation.

## Design Decisions

### When to Install

**Install on workspace creation only** (not on reconnection):
- Runs after `push_branch_to_vm` successfully creates the workspace
- Ensures repository files are present and git is initialized
- Avoids redundant operations on reconnection
- Happens once per workspace lifecycle

### Detection Logic

Check for `.pre-commit-config.yaml` in the workspace root:
- If present → run `pre-commit install`
- If absent → no action (silent skip)

### Error Handling

**Tolerant approach** (warn but continue):
- Success → Display `✓ Pre-commit hooks installed`
- Failure → Display warning, allow workspace creation to succeed
- No impact on repositories without pre-commit configuration

### User Feedback

Show clear success message when hooks are installed, matching the style of other agent-vm operations (checkmark prefix).

## Technical Implementation

### New Function

```bash
function install_precommit_hooks {
  local vm_ip="$1"
  local workspace_name="$2"
  local ssh_key="$SCRIPT_DIR/vm-ssh-key"

  # Check if .pre-commit-config.yaml exists
  if ssh -i "$ssh_key" -o StrictHostKeyChecking=no "user@$vm_ip" \
     "test -f ~/workspace/$workspace_name/.pre-commit-config.yaml" 2>/dev/null; then

    # Install pre-commit hooks
    if ssh -i "$ssh_key" -o StrictHostKeyChecking=no "user@$vm_ip" \
       "cd ~/workspace/$workspace_name && pre-commit install" 2>/dev/null; then
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

### Integration Point

Call the function in the workspace creation flow (around line 755 in `agent-vm`):

```bash
if [[ "$WORKSPACE_EXISTS" == "false" ]]; then
  echo "Creating new workspace: $WORKSPACE_NAME"
  push_branch_to_vm "$VM_IP" "$BRANCH_NAME" "$WORKSPACE_NAME"
  install_precommit_hooks "$VM_IP" "$WORKSPACE_NAME"  # <-- NEW
else
  echo "Using existing workspace: $WORKSPACE_NAME"
fi
```

## Behavior Matrix

| Scenario | Action | Message |
|----------|--------|---------|
| New workspace, `.pre-commit-config.yaml` exists, install succeeds | Install hooks | `✓ Pre-commit hooks installed` |
| New workspace, `.pre-commit-config.yaml` exists, install fails | Skip, warn | `⚠️  WARNING: Could not install...` |
| New workspace, no `.pre-commit-config.yaml` | Skip silently | None |
| Existing workspace (reconnection) | Function not called | None |

## Edge Cases

1. **pre-commit not installed on VM**: Installation fails, warning displayed
2. **Invalid .pre-commit-config.yaml**: Installation fails, warning displayed
3. **Git not initialized**: Cannot happen - `push_branch_to_vm` initializes git first
4. **SSH connection issues**: Handled by existing agent-vm SSH error handling
5. **Workspace directory doesn't exist**: Cannot happen - function only called after successful push

## Files Modified

- `vm/agent-vm`: Add `install_precommit_hooks` function and call it during workspace creation

## Files NOT Modified

- `vm/cloud-init.yaml.tftpl`: No changes (pre-commit already installed)
- `common/packages/python-packages.txt`: No changes (pre-commit already listed)
- Terraform configuration: No changes needed

## Testing Strategy

1. **Manual testing**:
   - Create workspace with `.pre-commit-config.yaml` → verify hooks installed
   - Create workspace without config file → verify silent skip
   - Reconnect to existing workspace → verify function not called
   - Create workspace with invalid config → verify warning displayed

2. **Integration tests**:
   - Update `test-integration.sh` to verify pre-commit hooks are installed after workspace creation (optional enhancement)

## Success Criteria

- Pre-commit hooks automatically installed for repositories with `.pre-commit-config.yaml`
- No impact on repositories without pre-commit configuration
- Workspace creation succeeds even if hook installation fails
- Clear feedback to users about hook installation status
