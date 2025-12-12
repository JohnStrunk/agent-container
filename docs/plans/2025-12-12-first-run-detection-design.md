# First Run Detection Fix for start-claude Scripts

**Date:** 2025-12-12

**Status:** Approved

## Problem Statement

The `start-claude` script in both container and VM environments currently
detects first run by checking if the `~/.claude` directory exists. However,
configuration files (`settings.json`, `statusline-command.sh`) are now
pre-populated into the `.claude` directory and copied to the home directory
during startup. This means the directory always exists, breaking first-run
detection. As a result, MCP servers and marketplace plugins never get
configured.

## Current Behavior

**Container:** `files/homedir/.local/bin/start-claude`

**VM:** `yolo-vm/files/homedir/start-claude`

Both scripts use:

```bash
if [ ! -d "${HOME}/.claude" ]; then  # 1st run
    initial_setup
else
    claude plugin marketplace update
fi
```

Since `~/.claude` is pre-populated from built-in configs, the condition is
always false, and `initial_setup()` never runs.

## Solution Design

### Marker File Approach

Replace directory existence check with a marker file that gets created only
after successful completion of initial setup.

**Marker file:** `~/.claude/.setup-complete`

**Properties:**

- Empty file (no content needed)
- Created after `initial_setup()` completes successfully
- Ephemeral lifecycle (same as container/VM home directory)
- Lost on container/VM restart, triggering fresh setup

### Implementation

**Change for both scripts:**

```bash
if [ ! -f "${HOME}/.claude/.setup-complete" ]; then  # 1st run
    mkdir -p "${HOME}/.claude"
    initial_setup
    touch "${HOME}/.claude/.setup-complete"
else
    claude plugin marketplace update
fi
```

**What changes:**

1. Check marker file instead of directory: `[ ! -f ... ]`
2. Defensive directory creation: `mkdir -p "${HOME}/.claude"`
3. Create marker after setup: `touch "${HOME}/.claude/.setup-complete"`

### Lifecycle Alignment

The marker file has the same lifecycle as the MCP server and marketplace
configurations it controls:

- **Container environment:** Home directory is ephemeral, not mounted from
  host. Marker and configs both reset on container restart.
- **VM environment:** Similar ephemeral behavior for fresh VM instances.
- **Pre-existing configs:** `settings.json` and `statusline-command.sh` remain
  in place, unaffected by marker file logic.

## Files Modified

1. `files/homedir/.local/bin/start-claude` (container)
2. `yolo-vm/files/homedir/start-claude` (VM)

Both get identical changes to the first-run detection logic.

## Testing Strategy

After implementation:

1. **Fresh start test:** Create new container/VM, verify initial setup runs
2. **Subsequent runs:** Call `start-claude` again in same session, verify
   setup skipped
3. **Restart test:** Recreate container/VM, verify setup runs again
4. **Config preservation:** Verify built-in configs remain accessible

## Alternatives Considered

**Check for MCP config directly:** Could check for specific MCP server configs
instead of using a marker file. Rejected because it couples the detection
logic to implementation details of Claude Code's config storage.

**Timestamp-based marker:** Could store timestamp in marker file for
debugging. Rejected because simple presence check is sufficient and we don't
need debugging metadata.

**External state directory:** Could use `~/.local/state/` per XDG conventions.
Rejected to keep all Claude-related state together in `~/.claude`.

## Benefits

- **Reliable detection:** Marker file explicitly tracks setup completion
- **Simple implementation:** Minimal code change, easy to understand
- **Lifecycle match:** Marker has same lifecycle as configs it controls
- **No side effects:** Pre-existing config files work as before
