# Claude Code Assistant Configuration - VM Approach (Lima)

**[← Back to root CLAUDE.md](../CLAUDE.md)**

## Project Overview

This is the **VM approach** - a Lima-based deployment of a Debian 13
virtual machine with AI coding agents. Lima provides cross-platform VM
management (Linux, macOS, Windows via WSL2) with automatic SSH
configuration and network setup.

**Architecture:** Single persistent VM (`agent-vm`) hosts multiple
workspace directories, each containing a full git clone. File sharing
via forward SSHFS (host mounts VM directories) provides strong
isolation while allowing host editing.

## Project Structure

```text
vm/
├── agent-vm.yaml              # Lima VM template (declarative config)
├── lima-provision.sh          # Provisioning script (runs at first start)
├── agent-vm                   # CLI wrapper (all functionality inline)
├── common-packages/           # Symlink to ../common/packages/ (required by Lima)
├── common-scripts/            # Symlink to ../common/scripts/ (required by Lima)
├── common-homedir/            # Symlink to ../common/homedir/ (required by Lima)
├── README.md                  # VM documentation
├── CLAUDE.md                  # This file
└── TROUBLESHOOTING.md         # Debugging guide

../common/
├── homedir/                   # Shared configs (deployed to VM)
│   ├── .claude.json
│   ├── .gitconfig
│   ├── .gitignore
│   ├── .claude/
│   │   ├── settings.json
│   │   ├── statusline-command.sh
│   │   └── skills/
│   ├── .config/
│   │   └── opencode/
│   │       └── opencode.jsonc
│   └── .local/
│       └── bin/
│           └── start-claude
├── packages/                  # Package lists (used in provisioning)
│   ├── apt-packages.txt
│   ├── npm-packages.txt
│   ├── python-packages.txt
│   ├── versions.txt
│   └── envvars.txt            # Environment variables to pass through
└── scripts/
    └── install-tools.sh       # Tool installation (Go, hadolint, etc.)
```

## Key Technologies & Tools

- **VM Management**: Lima (limactl)
- **VM Backend**: QEMU (cross-platform)
- **VM OS**: Debian 13 (Trixie)
- **File Sharing**: SSHFS (forward mount, host to VM)
- **AI Agents**: Claude Code, Gemini CLI, OpenCode AI, GitHub Copilot
- **Development Tools**: Git, Node.js, Python, Go, Docker, Podman,
  Lima (nested)

### Package Management

Package lists are shared between container and VM approaches via
`common/packages/`:

- `apt-packages.txt` - Debian packages (base utilities)
- `npm-packages.txt` - Node.js packages (AI agents, tools)
- `python-packages.txt` - Python packages (pre-commit, poetry, etc.)
- `versions.txt` - Version pins (Go, hadolint, etc.)
- `envvars.txt` - Environment variables to pass through

VM-specific packages (docker.io, podman, qemu, etc.) are defined
separately in `lima-provision.sh` since they're not needed in
containers.

### Provisioning Architecture

The provisioning script (`lima-provision.sh`) reads configuration from
`common/` directory:

1. **Symlinks** - The `vm/` directory contains symlinks (`common-packages`,
   `common-scripts`, `common-homedir`) pointing to `../common/` directories.
   These are required because Lima's `file:` property doesn't support `../`
   in paths.
2. **Package lists** - Lima copies files from `common/packages/*.txt`
   using `mode: data` in the template (referenced via symlinks)
3. **Version pins** - Sourced from `common/packages/versions.txt`
4. **Homedir configs** - Dynamically generated as `homedir.tar.gz` from
   `../common/homedir/` during VM creation by the `agent-vm` script,
   then deployed and extracted in VM
5. **Tool installation** - Uses `common/scripts/install-tools.sh`

This ensures container and VM approaches stay synchronized.

## Development Workflow

### Using agent-vm

The `agent-vm` script manages all VM and workspace operations:

```bash
# VM lifecycle
./agent-vm start                        # Create/start VM
./agent-vm start --memory 16 --vcpu 8   # Create VM with custom resources
./agent-vm destroy                      # Delete VM and all workspaces
./agent-vm status                       # Show VM state and workspaces

# Workspace operations (auto-starts VM if needed)
./agent-vm connect feature-name         # Create/connect to workspace
./agent-vm connect                      # Connect directly to VM (no workspace)
./agent-vm push feature-name            # Push branch to VM
./agent-vm fetch feature-name           # Fetch changes from VM
./agent-vm clean feature-name           # Delete specific workspace
./agent-vm clean-all                    # Delete all workspaces

# Running commands
./agent-vm connect feature-name -- claude   # Run claude in workspace
```

### Single-VM Architecture

One persistent VM hosts multiple workspace directories:

- VM name: `agent-vm` (managed by Lima)
- Workspaces: `~/workspace/<repo>-<branch>/`
- Each workspace is a full git clone (not worktrees)
- All workspaces share the same VM
- Lima state stored in `~/.lima/agent-vm/`

### Filesystem Sharing

Host files are mounted via SSHFS (forward direction):

- Host mount: `~/.agent-vm-mounts/workspace/`
- VM directory: `~/workspace/`
- All workspaces visible through one mount point
- Real-time synchronization via SSHFS

Edit files on host with your IDE, run builds/tests in VM.

### Multi-Workspace Support

Multiple branches work in the same VM:

- Workspaces: `~/workspace/<repo>-<branch>/`
- Each workspace is isolated (separate git clone)
- Open multiple terminals to different workspaces
- VM resources shared across all workspaces

### Task Management

Use task management tools (TaskCreate, TaskUpdate, TaskList) for
complex tasks to track progress.

### Pre-commit Quality Checks

Pre-commit hooks are automatically installed when creating a new
workspace (if `.pre-commit-config.yaml` is present in the repository).

Run pre-commit after making changes:

```bash
pre-commit run --files <filename>
```

### Testing VM Changes

After modifying Lima template or provisioning script:

1. **Validate Lima template**:

   ```bash
   cd /home/user/workspace/agent-container-lima/vm
   # Lima validates template on start
   limactl validate agent-vm.yaml
   ```

2. **Test with new VM**:

   ```bash
   # Destroy existing VM
   ./agent-vm destroy

   # Create new VM with changes
   ./agent-vm start

   # Verify provisioning
   ./agent-vm connect
   # Check installed packages, configs, etc.
   exit

   # Test workspace operations
   ./agent-vm connect test-branch
   ```

3. **Run integration tests**:

   ```bash
   cd ..
   ./test-integration.sh --vm
   ```

## File Modification Guidelines

### Lima Template (agent-vm.yaml)

- Follow YAML syntax and indentation
- Validate with `limactl validate agent-vm.yaml`
- Test changes by destroying and recreating VM
- Comment complex configurations
- Keep template cross-platform compatible

### Provisioning Script (lima-provision.sh)

- Use `#!/bin/bash` shebang
- Include `set -e -o pipefail`
- Pass shellcheck (via pre-commit)
- Use double quotes for variables
- Reference files via `{{.Dir}}` for template directory
- Reference user via `{{.User}}` for Lima user
- Use `info()` and `error()` functions for consistent output

### Shell Scripts (agent-vm)

- Use `#!/bin/bash` shebang
- Include `set -e -o pipefail`
- Pass shellcheck (via pre-commit)
- Use double quotes for variables: `"$VARIABLE"`
- Use local variables in functions: `local var_name="$1"`
- Handle both Linux and macOS (platform detection included)

## Common Tasks

### Adding Packages

1. **Plan**: Create todo for editing package list
2. Edit `../common/packages/apt-packages.txt` (or npm/python)
3. **Test**: Destroy and recreate VM to verify provisioning
4. Verify packages are installed:

   ```bash
   ./agent-vm connect
   dpkg -l | grep <package>
   ```

5. Commit changes

### Modifying VM Configuration

1. **Plan**: Create todos for configuration changes
2. Edit `agent-vm.yaml`
3. Run `limactl validate agent-vm.yaml`
4. **Test**: Destroy and recreate VM:

   ```bash
   ./agent-vm destroy
   ./agent-vm start
   ./agent-vm status
   ```

5. Verify configuration changes
6. Commit changes

### Updating Provisioning Script

1. **Plan**: Create todos for provisioning changes
2. Edit `lima-provision.sh`
3. Run shellcheck via pre-commit:

   ```bash
   pre-commit run shellcheck --files lima-provision.sh
   ```

4. **Test**: Destroy and recreate VM:

   ```bash
   ./agent-vm destroy
   ./agent-vm start
   # SSH in and verify changes
   ./agent-vm connect
   ```

5. Commit changes

## Testing Strategy

1. **Lima template validation**: `limactl validate agent-vm.yaml`
2. **Shellcheck validation**: Run pre-commit on all modified scripts
3. **Incremental testing**: Test small changes before large refactors
4. **VM recreation testing**: Destroy and recreate to test provisioning
5. **Workspace operations**: Test create, push, fetch, clean workflows
6. **Pre-commit checks**: Run on all modified files

### Integration Tests

Run end-to-end tests to validate VM environment:

```bash
# From repository root
./test-integration.sh --vm
```

This tests:

- Lima provisions VM successfully
- Provisioning script completes without errors
- Workspace operations (create, push, fetch, clean)
- SSHFS mounting and unmounting
- VM lifecycle (start, stop, status, destroy)

**When to run:**

- Before committing Lima template changes (`agent-vm.yaml`)
- Before committing provisioning script changes (`lima-provision.sh`)
- Before committing changes to `agent-vm` CLI script
- Before committing changes to `common/homedir/` configs
- After updating package lists in `common/packages/`

## Security Considerations

- SSH keys auto-generated per-VM by Lima (stored in `~/.lima/agent-vm/`)
- GCP credentials auto-detected and injected via provisioning:
  - Checks `GOOGLE_APPLICATION_CREDENTIALS` env var first
  - Falls back to `~/.config/gcloud/application_default_credentials.json`
  - Written to `/etc/google/application_default_credentials.json` in VM
  - Environment variables configured in `/etc/profile.d/ai-agent-env.sh`
  - Never stored in repo
- Forward SSHFS (VM cannot access host filesystem)
- No agent forwarding (SSH security)
- Root access via Lima SSH key only (no password)

## Environment Identification

The VM includes an environment marker file at `/etc/agent-environment`
containing `agent-vm`. This identifies the execution context and allows
integration tests to run from the VM environment.

## Cross-Platform Compatibility

### Platform Support

- **Linux** - Native support (package managers: apt, yum)
- **macOS** - Native support (Homebrew)
- **Windows** - Via WSL2 (runs Lima inside WSL)

### Platform Differences

| Aspect                 | Linux                  | macOS              |
|------------------------|------------------------|--------------------|
| Lima installation      | Package manager        | Homebrew           |
| VM backend             | QEMU (default)         | QEMU (default)     |
| SSHFS                  | apt install sshfs      | brew install sshfs |
| Unmount command        | fusermount -u / umount | umount only        |
| VM performance         | Native KVM accel       | QEMU emulation     |
| Nested virtualization  | Requires KVM           | Limited/no support |

### Platform Detection

The `agent-vm` script detects platform automatically:

```bash
PLATFORM="$(uname -s)"
case "$PLATFORM" in
  Linux*)
    UNMOUNT_CMD="fusermount -u"
    ;;
  Darwin*)
    UNMOUNT_CMD="umount"
    ;;
esac
```

### Cross-Platform Template

The `agent-vm.yaml` template uses portable Lima features:

- `vmType: "qemu"` - Works on both Linux and macOS
- No platform-specific mounts or settings
- Standard networking via Lima's shared network
- Cloud-init supported on both platforms

## Lima-Specific Considerations

### Template Variables

Lima templates support Go template syntax:

- `{{.Dir}}` - Directory containing the template (for file references)
- `{{.User}}` - Lima's default user (matches host username)

These are expanded by Lima at VM creation time.

### SSH Configuration

Lima automatically generates SSH config at
`~/.lima/agent-vm/ssh.config`. The `agent-vm` script uses this for all
SSH and git operations:

```bash
SSH_CONFIG="$HOME/.lima/agent-vm/ssh.config"
VM_HOST="lima-agent-vm"

ssh -F "$SSH_CONFIG" "$VM_HOST" "command"
```

### Resource Overrides

Resource specifications (`--memory`, `--vcpu`) only work at VM creation
time. To change resources:

1. Destroy existing VM: `./agent-vm destroy`
2. Create new VM with resources: `./agent-vm start --memory 16 --vcpu 8`

The script generates a temporary template with replaced values when
resource overrides are specified.

### Lima State Location

All Lima state is stored in `~/.lima/agent-vm/`:

- SSH keys and configuration
- VM disk images
- Lima metadata

This is separate from the repository and not committed to git.

## Git Workflow

### Workspace Repository Structure

Each workspace in the VM is a **full git clone** (not a worktree),
allowing complete independence between workspaces.

### Initial Workspace Creation

When you run `./agent-vm connect feature-name`:

1. Script checks if workspace exists in VM
2. If not, creates workspace directory
3. Initializes git repository in workspace
4. Pushes branch from host to workspace (normal push, not force)
5. Checks out branch in workspace
6. Installs pre-commit hooks if `.pre-commit-config.yaml` exists

### Push Operation

`./agent-vm push feature-name` pushes local branch to VM workspace:

- Creates workspace and git repo if doesn't exist
- Pushes branch via `git push` over SSH
- Uses normal push (not force push) - fails on conflicts
- Checks out branch in workspace after push

### Fetch Operation

`./agent-vm fetch feature-name` fetches commits from VM to host:

- Warns if VM workspace has uncommitted changes
- Uses `git pull` if branch is currently checked out (updates working tree)
- Uses `git fetch` if branch is not checked out (updates ref only)
- Uncommitted changes in VM are NOT included

### Key Design Points

1. **Full clones, not worktrees** - Each workspace is independent
2. **Git over SSH** - Uses Lima's SSH config for authentication
3. **Normal push (not force)** - Preserves git safety, fails on conflicts
4. **Working tree sync** - `git checkout` updates files after push
5. **Uncommitted change warnings** - User informed before fetch
6. **Branch creation on-the-fly** - Creates branch if doesn't exist locally

## Environment Variables

### Connection-Time Environment Variables

Environment variables from `common/packages/envvars.txt` are passed
through to the SSH session when connecting to a workspace.

The `agent-vm` script reads this file and exports variables if they are
set in the host environment:

```bash
# Only exports if variable is set in host environment
# Escapes special characters for shell safety
ENV_EXPORTS="export VAR1='value1'; export VAR2='value2'; "
```

### System-Wide Environment Variables

If GCP credentials were injected during provisioning,
`/etc/profile.d/ai-agent-env.sh` sets:

- `GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json`
- `ANTHROPIC_VERTEX_PROJECT_ID` (if provided during provisioning)
- `CLOUD_ML_REGION` (default: us-central1)
- `CLAUDE_CODE_USE_VERTEX=true`

These are loaded by login shells via `exec bash -l`.

### Combined Behavior

1. Connection-time exports run first (from `ENV_EXPORTS`)
2. `bash -l` loads `/etc/profile.d/ai-agent-env.sh` (login shell)
3. Result: Both connection-time and system-wide vars are available

## Credential Injection

### GCP Credential Handling

Credentials are injected during VM provisioning (not at connection time).

### Detection on Host

The `agent-vm` script detects credentials when running `start`:

```bash
# Check environment variable first
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  gcp_creds_path="$GOOGLE_APPLICATION_CREDENTIALS"
# Fall back to default location
elif [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
  gcp_creds_path="$HOME/.config/gcloud/application_default_credentials.json"
fi

# Read and export for provisioning
if [[ -n "$gcp_creds_path" && -f "$gcp_creds_path" ]]; then
  export GCP_CREDENTIALS_JSON=$(cat "$gcp_creds_path")
  export VERTEX_PROJECT_ID="${ANTHROPIC_VERTEX_PROJECT_ID:-}"
  export VERTEX_REGION="${CLOUD_ML_REGION:-us-central1}"
fi
```

### Provisioning Script Usage

The provisioning script (`lima-provision.sh`) checks for credentials:

```bash
if [ -n "$GCP_CREDENTIALS_JSON" ]; then
  # Write credentials to /etc/google/
  mkdir -p /etc/google
  echo "$GCP_CREDENTIALS_JSON" > /etc/google/application_default_credentials.json
  chmod 644 /etc/google/application_default_credentials.json

  # Configure environment variables
  cat > /etc/profile.d/ai-agent-env.sh <<EOF
export GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json
export ANTHROPIC_VERTEX_PROJECT_ID="${VERTEX_PROJECT_ID}"
export CLOUD_ML_REGION="${VERTEX_REGION}"
export CLAUDE_CODE_USE_VERTEX="true"
EOF
fi
```

### Credential Security

- Credentials never stored in git repository
- Passed via environment variables during provisioning
- Written to `/etc/google/` in VM (world-readable, VM isolation provides security)
- Environment variables set system-wide via `/etc/profile.d/`
- VM must be destroyed and recreated to update credentials

## Common Pitfalls

### Lima Not Installed

**Problem:** `limactl: command not found`

**Solution:** Install Lima first:

```bash
# Linux (Debian/Ubuntu)
sudo apt-get install lima

# macOS
brew install lima

# Verify
limactl --version
```

### SSHFS Not Installed

**Problem:** Warning about SSHFS not available

**Solution:** Install SSHFS:

```bash
# Linux (Debian/Ubuntu)
sudo apt-get install sshfs

# macOS
brew install macfuse && brew install sshfs
```

### Resource Changes Not Applied

**Problem:** Using `--memory` or `--vcpu` with existing VM doesn't change resources

**Reason:** Resource specifications only work at VM creation time

**Solution:** Destroy and recreate VM:

```bash
./agent-vm destroy
./agent-vm start --memory 16 --vcpu 8
```

### Uncommitted Changes Lost

**Problem:** Made changes in VM but forgot to commit before `fetch`

**Solution:** The `fetch` command warns about uncommitted changes but
doesn't include them. Always commit in VM before fetching:

```bash
# In VM
git add .
git commit -m "Description"
exit

# On host
./agent-vm fetch feature-name
```

### Push Fails with Conflict

**Problem:** `git push` fails with rejected non-fast-forward error

**Reason:** VM workspace has commits not in host branch

**Solution:** Fetch first, then push:

```bash
./agent-vm fetch feature-name
git merge  # or git rebase
./agent-vm push feature-name
```

### Provisioning Fails

**Problem:** VM starts but provisioning script fails

**Debugging:**

1. Check provisioning logs:

   ```bash
   limactl shell agent-vm
   journalctl -u lima-init  # System-level provisioning
   ```

2. Check for missing files:

   ```bash
   ls -la /home/user/.claude.json
   ls -la /etc/google/application_default_credentials.json
   ```

3. Verify package installation:

   ```bash
   dpkg -l | grep <package>
   npm list -g
   pip list
   ```

### SSHFS Mount Stale

**Problem:** Files not updating in host mount

**Solution:** Unmount and remount:

```bash
fusermount -u ~/.agent-vm-mounts/workspace  # Linux
umount ~/.agent-vm-mounts/workspace         # macOS

./agent-vm connect feature-name  # Remounts automatically
```

## Debugging Tips

### Check VM Status

```bash
# Lima VM status
limactl list

# Detailed VM info
limactl list --format json | jq

# VM status via script
./agent-vm status
```

### SSH into VM Directly

```bash
# Using Lima
limactl shell agent-vm

# Using SSH config
ssh -F ~/.lima/agent-vm/ssh.config lima-agent-vm
```

### Check Provisioning

```bash
# View provisioning logs
limactl shell agent-vm
journalctl -u lima-init | less

# Check environment marker
cat /etc/agent-environment

# Check installed packages
dpkg -l | grep <package>
npm list -g
pip list

# Check homedir files
ls -la ~/.claude.json
ls -la ~/.gitconfig
ls -la ~/.claude/settings.json
```

### Verify SSHFS Mount

```bash
# Check mount status
mountpoint ~/.agent-vm-mounts/workspace

# List mount options
mount | grep agent-vm-mounts

# Test read/write
ls ~/.agent-vm-mounts/workspace/
touch ~/.agent-vm-mounts/workspace/test-file
```

### Check Git Operations

```bash
# Verify SSH config exists
cat ~/.lima/agent-vm/ssh.config

# Test git over SSH
export GIT_SSH_COMMAND="ssh -F ~/.lima/agent-vm/ssh.config"
git ls-remote ssh://lima-agent-vm/home/user/workspace/<repo>-<branch>
unset GIT_SSH_COMMAND
```

### Verify Credentials

```bash
# In VM
echo $GOOGLE_APPLICATION_CREDENTIALS
cat /etc/google/application_default_credentials.json
cat /etc/profile.d/ai-agent-env.sh

# Test Claude Code with Vertex
claude --version
echo $CLAUDE_CODE_USE_VERTEX
```

### Clean Start

If everything is broken, start fresh:

```bash
# Destroy VM completely
./agent-vm destroy

# Clean up Lima state
rm -rf ~/.lima/agent-vm

# Create new VM
./agent-vm start

# Verify provisioning
./agent-vm status
./agent-vm connect
```

## Maintenance Notes

- Pre-commit hooks ensure code quality
- Lima manages VM lifecycle (create/start/stop/delete)
- Provisioning runs once at VM creation
- SSH keys generated automatically by Lima
- VM state stored in `~/.lima/agent-vm/` (not in repo)

## Architecture Evolution

**2026-02-03:** Migrated from Terraform + libvirt to Lima

The VM approach was migrated from Terraform/libvirt to Lima for
cross-platform support and simplified infrastructure. The
single-VM, multi-workspace architecture was preserved. Key changes:

- Removed: `main.tf`, `variables.tf`, `outputs.tf`, `cloud-init.yaml.tftpl`, `libvirt-nat-fix.sh`
- Added: `agent-vm.yaml`, `lima-provision.sh`
- Refactored: `agent-vm` CLI (all functions inline, Lima commands)
- Unchanged: `common/` directory structure, workspace workflow, SSHFS mounting

**Previous architecture (2026-01-08):** Single-VM with multiple workspaces

The multi-VM architecture (one VM per branch via Terraform workspaces)
was replaced with a simpler single-VM design. This is preserved in the
Lima migration.
