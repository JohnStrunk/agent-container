# Copy Home Files Design

Replace the static `common/homedir/` configuration directory with a
mechanism that copies files from the user's real home directory into
the container or VM environment. A spec file lists which paths to
copy using glob patterns and exclusions.

## Goals

- Users bring their own configuration into the environment
- No repo-managed default dotfiles
- Container: one-time copy at startup
- VM: copy on first connect, re-sync on demand via
  `agent-vm refresh-home`
- Maintain container isolation (agent cannot see host filesystem)

## Non-Goals

- Syncing changes back from the environment to the host
- Watching for file changes and auto-syncing
- Per-user override files (single spec file in the repo)

## Spec File

### Location

`common/homedir-files-to-copy.txt`

### Format

```text
# Files/directories to copy from user's $HOME into the environment.
# Paths are relative to $HOME. Directories are copied recursively.
# Standard glob patterns are supported. Lines starting with ! exclude.
# Missing paths are silently skipped.

.claude
.claude.json
.config/opencode
.gemini
```

### Rules

- Lines starting with `#` are comments
- Blank lines are ignored
- Each line is a path relative to `$HOME`
- Glob patterns (e.g., `.config/*/settings.json`) are supported
- Lines starting with `!` exclude matching paths from the copy set
- If a resolved path is a directory, it is copied recursively
- Paths that do not exist in the user's home are silently skipped

## Shared Library

### File

`common/scripts/copy-home-lib.sh`

### Language

POSIX sh (`#!/bin/sh`). No bashisms. `local` is allowed.

### Interface

The library is sourced (`. copy-home-lib.sh`) and exposes functions
that:

1. Read the spec file, skipping comments and blank lines
2. Expand glob patterns relative to a source home directory
3. Process exclusions (`!` lines filter out matches)
4. Build rsync include/exclude filter arguments
5. Run rsync to copy matched files to a destination, preserving
   directory structure and permissions

Both the container host-side script and the VM host-side script
source this library. The library rsyncs matched files into a
local destination directory. For the container path, the caller
rsyncs into a temporary staging directory and then tars it. For
the VM path, the caller rsyncs directly into the VM over SSH.

### Rsync Translation

The library translates the simple spec format into rsync filter
rules. For each entry:

- A path like `.claude` that resolves to a directory generates
  includes for the directory and its contents (`+ .claude/`,
  `+ .claude/**`), plus includes for any intermediate parent
  directories
- A path like `.claude.json` that resolves to a file generates a
  single include (`+ .claude.json`)
- Exclusion lines (`!pattern`) generate corresponding exclude rules
- A final `- *` exclude catches everything not explicitly included

Intermediate parent directories are automatically included so rsync
can traverse into them. For example, `.config/opencode` generates
includes for `.config/` and `.config/opencode/` and
`.config/opencode/**`.

## Container Integration

### Changes to `container/agent-container`

Before launching the container:

1. Source `common/scripts/copy-home-lib.sh`
2. Read `common/homedir-files-to-copy.txt`
3. Build a tarball of matching files from the host user's `$HOME`
   into a temporary directory
4. Bind-mount the temporary directory read-only into the container
   at `/tmp/host-home`
5. After the container exits, clean up the temporary directory

### Changes to `container/Dockerfile`

- Remove the `COPY ../common/homedir/ /etc/skel/` directive
  (line 77)
- Remove the permission-setting `RUN` block (lines 80-83)
- No new files need to be added to the image

### Changes to `container/entrypoint.sh`

- Remove the `/etc/skel` copy blocks (lines 42-44 in the root
  path, lines 82-84 in the non-root path)
- Replace with: if `/tmp/host-home/homedir.tar.gz` exists, extract
  it to the user's home directory, then remove the tarball

## VM Integration

### Changes to `vm/agent-vm`

**Remove from `start_vm`:**

- Tarball generation from `common/homedir` (lines 217-236)
- Tarball cleanup (line 248)

**Add to `start_vm` (after SSH is ready):**

- Source `common/scripts/copy-home-lib.sh`
- Rsync matching files from host `$HOME` into the VM user's home
  over SSH, using the existing `$SSH_CONFIG`

**New subcommand: `refresh-home`**

```text
./agent-vm refresh-home
```

Ensures the VM is running, then rsyncs the spec'd files from the
host `$HOME` into the VM user's home. Always overwrites existing
files.

**Update `usage` function** to document `refresh-home`.

### Changes to `vm/agent-vm.yaml`

- Remove the `mode: data` block that ships `homedir.tar.gz` into
  the VM (lines 54-56)
- Remove the `mode: system` script that extracts the tarball
  (lines 59-77)

### Changes to `vm/lima-provision.sh`

- Remove the homedir deployment section that copies from
  `/tmp/homedir` to the user's home (lines 189-221)
- Remove the `/tmp/homedir` entries from the `expected_files`
  array (lines 43-46) since those files are no longer shipped
  via Lima `mode: data`

### Symlink Removal

- Delete `vm/common-homedir` symlink (no longer needed)

## Removal of `common/homedir`

Delete the entire `common/homedir/` directory and all its contents:

- `.claude.json`
- `.claude/settings.json`
- `.claude/statusline-command.sh`
- `.claude/skills/README.md`
- `.gitconfig`
- `.gitignore`
- `.config/opencode/opencode.jsonc`
- `.local/bin/start-claude`
- `.gitkeep`

## Documentation Updates

### `CLAUDE.md` (root)

- Replace the `common/homedir/` section under "Common Resources"
  with documentation of `common/homedir-files-to-copy.txt`
- Explain the format, how to customize, and the copy behavior
- Update the `common/` file listing

### `container/CLAUDE.md`

- Replace references to built-in configs from `common/homedir/`
  with the new behavior: files copied from user's home at container
  startup based on the spec file
- Update the "Configuration files" section under Isolation Model
- Update the "Volume Mounts" section to mention the temporary
  tarball mount

### `vm/CLAUDE.md`

- Replace references to the homedir tarball with the new behavior:
  files rsynced from user's home on first connect
- Add `refresh-home` to the `agent-vm` command reference
- Update the provisioning architecture section
- Remove references to `common-homedir` symlink

## Testing

### Unit Tests

New file: `common/scripts/test-copy-home-lib.sh`

POSIX sh (`#!/bin/sh`), `local` allowed.

Tests run against a temporary directory with a known file structure
(fake `$HOME`), requiring only sh and rsync. No container or VM
needed.

Test cases:

1. **Spec file parsing** - comments and blank lines are skipped,
   entries are read correctly
2. **Glob expansion** - patterns like `.config/o*` expand to
   matching paths
3. **Exclusion handling** - `!` prefixed lines remove paths from
   the copy set
4. **Missing paths** - entries that do not exist in the source are
   silently skipped
5. **Directory recursion** - a directory entry copies all contents
   recursively, preserving structure
6. **Rsync filter generation** - the generated rsync
   include/exclude arguments are correct

### Integration Test Updates (`test-integration.sh`)

**Container test (`test_container`):**

- Remove validation that assumed `common/homedir` files existed in
  the container
- Add a test that verifies the copy-home mechanism works: create a
  known test file in a staging area, confirm it appears in the
  container's home after startup

**VM test (`test_vm_approach`):**

- Remove the homedir tarball generation block (lines 417-441)
- Add a test that verifies files from the host home appear in the
  VM after `start`
- Add a test for `refresh-home`: modify a file on the host, run
  `agent-vm refresh-home`, verify the update appears in the VM
- Add a test that `refresh-home` overwrites existing files

## POSIX Compliance

All new shell scripts and libraries use `#!/bin/sh` and avoid
bashisms:

- No `[[ ]]` (use `[ ]`)
- No arrays
- No `source` (use `.`)
- No `function` keyword (use `name() { ... }`)
- No process substitution (`<()`)
- No `${var,,}` case manipulation
- `local` is allowed

Existing scripts (`agent-container`, `agent-vm`, `entrypoint.sh`)
remain bash and are not changed to POSIX sh.

## Summary of Changes

| Area | Change |
| ---- | ------ |
| New: `common/homedir-files-to-copy.txt` | Spec file |
| New: `common/scripts/copy-home-lib.sh` | Shared POSIX sh library |
| New: `common/scripts/test-copy-home-lib.sh` | Unit tests |
| Delete: `common/homedir/` | Entire directory |
| Delete: `vm/common-homedir` | Symlink |
| Modify: `container/agent-container` | Build tarball on host |
| Modify: `container/Dockerfile` | Remove `/etc/skel` copy |
| Modify: `container/entrypoint.sh` | Extract tarball |
| Modify: `vm/agent-vm` | Rsync on connect, `refresh-home` |
| Modify: `vm/agent-vm.yaml` | Remove tarball blocks |
| Modify: `vm/lima-provision.sh` | Remove homedir deployment |
| Modify: `test-integration.sh` | Update tests |
| Modify: `CLAUDE.md` | Update docs |
| Modify: `container/CLAUDE.md` | Update docs |
| Modify: `vm/CLAUDE.md` | Update docs |
