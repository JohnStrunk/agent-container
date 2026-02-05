# VM Approach - Lima-based Agent VM

Lima-based development environment for working with AI coding agents using
isolated virtual machines.

**[← Back to main documentation](../README.md)**

**Key Feature: Strong Isolation** - The VM uses forward SSHFS for file
sharing, where the host mounts VM directories. The VM cannot access host
files, credentials, or configs, providing strong security boundaries.

## Overview

This project provides a Lima-based VM environment that enables developers
to work with AI coding agents on isolated Git branches using workspace
directories. The VM comes pre-configured with:

- **Claude Code** - Anthropic's AI coding assistant
- **Gemini CLI** - Google's Gemini CLI
- **OpenCode AI** - Open-source AI coding assistant
- **GitHub Copilot** - GitHub's AI coding assistant
- **Development tools** - Git, Node.js, Python, Docker, Podman, and more
- **Code quality tools** - pre-commit, hadolint, pipenv, poetry
- **Nested VM support** - Lima pre-installed for nested virtualization

**Isolation Model:**

- ✅ Forward SSHFS (host mounts VM, not reverse)
- ✅ VM cannot access host filesystem
- ✅ VM cannot access host credentials or configs
- ✅ Single VM, multiple workspace directories
- ✅ Each workspace is independent git clone
- ✅ Cross-platform support (Linux, macOS, Windows via WSL2)

## Features

- **Strong Isolation**: VM cannot access host filesystem or credentials
- **Forward SSHFS**: Host mounts VM directories (secure direction)
- **AI Agent Support**: Pre-installed Claude Code, Gemini CLI, and
  GitHub Copilot CLI
- **Cross-Platform**: Linux, macOS, and Windows (via WSL2)
- **Single-VM Architecture**: Multiple workspaces in one VM
- **Git Workspace Support**: Each branch gets independent git clone
- **Automatic SSH Setup**: Lima manages SSH keys and configuration
- **Nested Virtualization**: Lima pre-installed for testing VM workflows

## Prerequisites

- **Lima** - VM management tool (cross-platform)
- **SSHFS** - For mounting VM directories on host
- **Git** - Version control
- **Bash** - For running the agent-vm script

**Platform support:**

- **Linux** - Native support via package managers
- **macOS** - Native support via Homebrew
- **Windows** - Via WSL2 (run agent-vm within WSL)

### Install Lima

**Linux (Debian/Ubuntu):**

```bash
# Add Lima repository
sudo apt-get update
sudo apt-get install -y curl
curl -fsSL https://lima-vm.io/lima.gpg | sudo apt-key add -
echo "deb https://lima-vm.io/deb/ $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/lima.list

# Install Lima
sudo apt-get update
sudo apt-get install -y lima

# Verify installation
limactl --version
```

**macOS:**

```bash
# Install via Homebrew
brew install lima

# Verify installation
limactl --version
```

**Windows (WSL2):**

Install within WSL2 environment using Linux instructions above.

### Install SSHFS

**Linux (Debian/Ubuntu):**

```bash
sudo apt-get install -y sshfs
```

**macOS:**

```bash
brew install sshfs
```

**Windows (WSL2):**

Install within WSL2 using Linux instructions above.

## Quick Start

1. **Navigate to the vm directory:**

   ```bash
   cd agent-container-lima/vm
   ```

2. **Create/connect to a workspace:**

   ```bash
   ./agent-vm connect my-feature-branch
   ```

This will:

- Start the VM (if not running) or create it (if it doesn't exist)
- Create a workspace directory for your branch
- Initialize a git repository in the workspace
- Push your branch to the workspace
- Mount the workspace via SSHFS to `~/.agent-vm-mounts/workspace/`
- Drop you into an SSH session in the workspace directory

## Usage

### VM Lifecycle

```bash
# Start VM (creates if doesn't exist)
./agent-vm start

# Start with custom resources (creation-time only)
./agent-vm start --memory 16 --vcpu 8

# Show VM status and workspaces
./agent-vm status

# Destroy VM completely (stops if running, deletes all workspaces)
./agent-vm destroy
```

### Workspace Operations

```bash
# Create/connect to workspace (auto-starts VM if needed)
./agent-vm connect my-feature-branch

# Connect to VM without workspace (just shell)
./agent-vm connect

# Push local branch to VM workspace
./agent-vm push my-feature-branch

# Fetch commits from VM workspace to host
./agent-vm fetch my-feature-branch

# Delete specific workspace
./agent-vm clean my-feature-branch

# Delete all workspaces (keeps VM running)
./agent-vm clean-all
```

### Inside the VM

Once connected to a workspace, you can use:

```bash
# Start Claude Code (recommended - includes MCP servers and plugins)
start-claude

# Or use claude directly
claude

# Start Gemini CLI
gemini

# Start GitHub Copilot CLI
copilot
```

## How It Works

**Single-VM Architecture:**

- One persistent VM named `agent-vm` running Debian 13
- Multiple workspace directories within VM (`~/workspace/<repo>-<branch>/`)
- Each workspace is a full git clone (not a worktree)
- Workspaces isolated from each other
- SSHFS mounts entire workspace directory to host

**Workflow:**

1. `./agent-vm connect feature-auth` - Starts VM and creates workspace
2. Edit files at `~/.agent-vm-mounts/workspace/<repo>-feature-auth/`
   on host using your IDE
3. Build/test in VM SSH session
4. Commit changes in VM
5. `./agent-vm fetch feature-auth` - Fetch changes back to host repo

**Resource Efficiency:**

- Multiple workspaces share one VM (reduced memory/CPU usage)
- Workspaces are lightweight directories, not full VMs
- Single SSHFS mount for all workspaces

### Filesystem Sharing

Files are shared between host and VM via forward SSHFS (host mounts VM):

- Host mount: `~/.agent-vm-mounts/workspace/`
- VM directory: `~/workspace/`
- All workspaces visible in single mount point

**Security benefits:**

- VM cannot access host filesystem
- VM cannot read host credentials or configs
- If VM is compromised, attack surface limited to SSH server
- Only mounted directories are visible to host

Changes on host appear immediately in VM and vice versa.

## Configuration

### VM Resource Options

Customize VM resources at creation time:

```bash
# Default: 4 vCPU, 8 GB RAM, 100 GB disk
./agent-vm start

# High-resource configuration
./agent-vm start --memory 16 --vcpu 8

# Custom configuration
./agent-vm start --memory 12 --vcpu 6
```

**Note:** Resource settings only apply at VM creation time. To change
resources, destroy and recreate the VM.

### Built-in Configurations

The VM uses built-in configurations from `../common/homedir/`:

- `.claude.json` - Claude Code settings (model, preferences)
- `.gitconfig` - Git configuration (name, email, aliases)
- `.local/bin/start-claude` - Helper script for starting Claude Code

These are deployed to the VM during provisioning and are shared with the
container approach.

To customize permanently:

1. Edit files in `../common/homedir/`
2. Destroy and recreate the VM to apply changes

### Environment Variables

**Authentication:**

Set these environment variables on your host before starting the VM to
enable AI service authentication:

**Claude Code:**

- `ANTHROPIC_API_KEY` - Anthropic API key (for direct API access)
- `ANTHROPIC_MODEL` - Model to use (default: claude-3-5-sonnet-20241022)
- `ANTHROPIC_SMALL_FAST_MODEL` - Fast model for simple tasks
- `ANTHROPIC_VERTEX_PROJECT_ID` - Google Cloud project for Vertex AI
- `CLOUD_ML_REGION` - Cloud region for Vertex AI (default: us-central1)
- `CLAUDE_CODE_USE_VERTEX` - Use Vertex AI instead of direct API

**Gemini CLI:**

- `GEMINI_API_KEY` - API key for Gemini

**GCP Credential Injection:**

For Vertex AI authentication, credentials are detected and injected during
VM provisioning:

```bash
# Auto-detected from default location
./agent-vm start  # Uses ~/.config/gcloud/application_default_credentials.json

# Override with custom path
export GOOGLE_APPLICATION_CREDENTIALS=~/my-service-account.json
export ANTHROPIC_VERTEX_PROJECT_ID="your-gcp-project-id"
./agent-vm start
```

The credential file is:

- Detected from `GOOGLE_APPLICATION_CREDENTIALS` env var or default location
- Injected during VM provisioning
- Written to `/etc/google/application_default_credentials.json` in VM
- Environment variables set system-wide via `/etc/profile.d/ai-agent-env.sh`
- Available to all workspaces and SSH sessions

**Connection-time environment variables:**

Environment variables listed in `common/packages/envvars.txt` are passed
through to SSH sessions when connecting to workspaces. Only variables that
are set in your host environment are passed through.

## Nested Virtualization

The VM includes Lima pre-installed, enabling you to run VMs inside the VM
for testing VM workflows or further isolation.

### Running Nested VMs

```bash
# Inside the VM, create a nested VM using Lima
limactl start default

# Or use the agent-vm script inside the VM
cd /path/to/agent-container-lima/vm
./agent-vm start
```

Lima automatically handles network configuration to avoid conflicts with
the outer VM.

### Features Available for Nested VMs

The VM is configured with:

- **Lima pre-installed** - Latest version from GitHub releases
- **QEMU and KVM** - Full virtualization support
- **Docker and Podman** - Container runtimes for testing container approach
- **Sufficient resources** - 4 vCPUs, 8GB RAM, 100GB disk

## Git Workflow

### Workspace Structure

Each workspace in the VM is a full git clone (not a worktree), providing
complete independence between workspaces.

Workspace naming: `<repo>-<branch>`

Example: For repository `agent-container-lima` and branch `feature-auth`,
the workspace is `agent-container-lima-feature-auth`.

### Push Operation

```bash
./agent-vm push feature-auth
```

This:

1. Creates workspace directory in VM if needed
2. Initializes git repository if needed
3. Creates branch on host if it doesn't exist
4. Pushes branch from host to VM workspace
5. Checks out the branch in VM

**Safety:** Uses normal `git push` (not force push), fails on conflicts.

### Fetch Operation

```bash
./agent-vm fetch feature-auth
```

This:

1. Checks for uncommitted changes in VM (warns if found)
2. Fetches commits from VM workspace to host repository
3. If branch is checked out on host: uses `git pull` to update working tree
4. If branch is not checked out: uses `git fetch` to update ref only

**Safety:** Warns about uncommitted changes but continues (only committed
work is fetched).

### Branch Creation

If a branch doesn't exist locally, the `connect` and `push` commands
automatically create it from current HEAD:

```bash
# Creates branch 'new-feature' from HEAD and pushes to VM
./agent-vm connect new-feature
```

## Homedir Configuration Management

### Tarball Approach

The VM uses a tarball (`homedir.tar.gz`) to deploy configuration files from
`../common/homedir/` because Lima's `mode: data` doesn't fully support
directories with hidden files (dotfiles).

**Why use a tarball:**

- Lima's `mode: data` can copy individual files but struggles with nested
  directory structures
- Hidden files (`.claude.json`, `.gitconfig`, etc.) need special handling
- Tarball preserves file permissions and directory structure
- Single atomic operation for entire config tree

**Automatic generation:**

The `homedir.tar.gz` tarball is automatically generated from `../common/homedir/`
during VM creation by the `agent-vm` script. You don't need to manually
regenerate it - just modify files in `../common/homedir/` and the next VM
creation will pick up the changes.

**What gets deployed:**

- `.claude.json` - Claude Code settings
- `.gitconfig` - Git configuration
- `.gitignore` - Git ignore patterns
- `.claude/settings.json` - Claude settings
- `.claude/statusline-command.sh` - Status line script
- `.claude/skills/` - Claude skills directory
- `.config/opencode/opencode.jsonc` - OpenCode AI configuration
- `.local/bin/start-claude` - Helper script

**Extraction verification:**

The provisioning script verifies extraction succeeded by checking for
`.claude.json` as a sentinel file. If this file is missing after extraction,
provisioning fails with a clear error message.

## File Structure

```text
vm/
├── README.md              # This file
├── CLAUDE.md              # Claude Code assistant instructions
├── TROUBLESHOOTING.md     # Troubleshooting guide
├── agent-vm.yaml          # Lima VM template
├── lima-provision.sh      # VM provisioning script
├── agent-vm               # CLI wrapper script
├── common-packages/       # Symlink to ../common/packages/ (required by Lima)
├── common-scripts/        # Symlink to ../common/scripts/ (required by Lima)
└── common-homedir/        # Symlink to ../common/homedir/ (required by Lima)

../common/
├── homedir/               # Shared configs (deployed to VM)
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
├── packages/              # Package lists (used in provisioning)
│   ├── apt-packages.txt
│   ├── npm-packages.txt
│   ├── python-packages.txt
│   ├── versions.txt
│   └── envvars.txt
└── scripts/
    └── install-tools.sh   # Tool installation script

~/.lima/agent-vm/          # Lima state (created at runtime)
~/.agent-vm-mounts/        # SSHFS mount points (created at runtime)
```

## Isolation & Security

This VM uses forward SSHFS for strong security isolation:

**What the agent CAN access:**

- ✅ Workspace directories in VM (read-write)
- ✅ Built-in configs from `../common/homedir/` (deployed during provisioning)
- ✅ Injected credentials (from provisioning)
- ✅ Other workspaces in the VM (accessible via filesystem)

**What the agent CANNOT access:**

- ❌ Host filesystem outside mounted workspace
- ❌ Host configs (`~/.claude`, `~/.config/gcloud`, etc.)
- ❌ Host credentials or secrets (except those injected)
- ❌ Other users' files or host processes

**Security properties:**

- VM cannot initiate connections to host filesystem
- VM cannot corrupt your host configs
- VM cannot access host Docker socket or escalate privileges
- If VM is compromised, attack surface limited to SSH server
- Credentials are system-wide in VM but isolated from host

**SSHFS direction:**

Forward SSHFS (host mounts VM directories) is more secure than reverse
SSHFS (VM mounts host directories) because:

- VM cannot access host filesystem even if compromised
- Host controls what gets mounted and when
- VM has no visibility into host filesystem structure

## Comparison with Container Approach

| Aspect | Container | VM |
| --- | --- | --- |
| **Isolation** | Container (namespace) | Full VM (KVM/QEMU) |
| **Startup** | Fast (~1-5s) | Slower (~10-30s) |
| **Resources** | Lightweight | Heavier (VM overhead) |
| **File Sharing** | Bind mounts | Forward SSHFS |
| **Nested VMs** | Limited | Full (Lima installed) |
| **Platform** | Docker/Podman | Lima required |
| **Security** | Strong | Stronger (full VM) |
| **Use Case** | Quick iteration | Heavy workloads |

**When to use container approach:**

- Fast iteration cycles
- CI/CD pipelines
- Lighter workloads
- Docker/Podman already installed

**When to use VM approach:**

- Need full VM isolation
- Testing VM workflows (nested VMs)
- Heavy workloads (builds, tests)
- Platform without Docker/Podman
- macOS development

## Migration from Terraform Version

### Breaking Changes

The Lima migration is a **breaking change**. You must destroy your existing
Terraform-based VMs and recreate with Lima.

**What changed:**

1. **CLI interface** - New command structure (see Usage section)
2. **SSH keys** - Lima manages keys automatically (old keys discarded)
3. **VM IP addressing** - Dynamic instead of static (transparent via Lima)
4. **State location** - Moved from `vm/terraform.tfstate` to `~/.lima/agent-vm/`
5. **Resource specification** - Use `./agent-vm start --memory N --vcpu M`
   instead of command-line flags during connect

**What stayed the same:**

1. **Workspace structure** - Same (`~/workspace/<repo>-<branch>/`)
2. **Git workflow** - Identical (push/fetch operations)
3. **SSHFS mount location** - Same (`~/.agent-vm-mounts/workspace/`)
4. **Common configs** - Same (`common/` directory)
5. **Architecture** - Still single-VM, multi-workspace

### Migration Steps

1. **Fetch any uncommitted work from existing VM:**

   ```bash
   # Old Terraform-based command
   ./agent-vm -b my-branch --fetch
   ```

2. **Destroy Terraform-based VM:**

   ```bash
   # Old Terraform-based command
   ./agent-vm --destroy
   ```

3. **Install Lima and SSHFS** (see Prerequisites section above)

4. **Create new Lima-based VM:**

   ```bash
   # New Lima-based command
   ./agent-vm start
   ```

5. **Connect to your workspace:**

   ```bash
   # New Lima-based command
   ./agent-vm connect my-branch
   ```

**Note:** Your git repository and branches are unaffected by the migration.
Only the VM infrastructure changes.

## Troubleshooting

### VM Won't Start

```bash
# Check Lima installation
limactl --version

# Check VM status
./agent-vm status

# Try starting explicitly
./agent-vm start
```

### Cannot Connect to Workspace

1. Verify VM is running: `./agent-vm status`
2. Check workspace exists: `./agent-vm status` (lists workspaces)
3. Try creating workspace: `./agent-vm connect branch-name`

### SSHFS Mount Issues

```bash
# Check mount status
mountpoint -q ~/.agent-vm-mounts/workspace && echo "Mounted" || echo "Not mounted"

# Unmount manually if stuck
fusermount -u ~/.agent-vm-mounts/workspace   # Linux
umount ~/.agent-vm-mounts/workspace          # macOS

# Reconnect to workspace
./agent-vm connect branch-name
```

### Push/Fetch Fails

**Push failures:**

- Ensure branch exists locally or let `agent-vm` create it
- Check for merge conflicts in VM workspace
- Verify VM is running: `./agent-vm status`

**Fetch failures:**

- Commit or stash changes in VM before fetching
- Check network connectivity to VM
- Verify workspace exists: `./agent-vm status`

### VM Performance Issues

**Slow performance:**

1. Check resource allocation: `./agent-vm status`
2. Destroy and recreate with more resources:

   ```bash
   ./agent-vm destroy
   ./agent-vm start --memory 16 --vcpu 8
   ```

3. Check host system resources (CPU, memory available)

### macOS-Specific Issues

**SSHFS mount failures:**

- Ensure macFUSE is installed: `brew install macfuse`
- Check macFUSE kernel extension is loaded
- Restart macOS if kernel extension was just installed

**VM performance:**

- macOS uses QEMU emulation (slower than Linux KVM)
- Consider increasing VM resources
- Use container approach for lighter workloads

## Architecture

- **VM Management**: Lima (<https://lima-vm.io/>)
- **VM Backend**: QEMU (cross-platform)
- **Base Image**: Debian 13 (Trixie) cloud image
- **Provisioning**: Lima provision scripts + cloud-init
- **Networking**: Lima managed (automatic)
- **Storage**: QCOW2 disk image managed by Lima
- **File Sharing**: Forward SSHFS (host mounts VM)
- **SSH**: Lima managed (automatic key generation and config)

## Security Notes

This configuration is designed for **development/testing environments**:

- VM isolation provides strong security boundaries
- Forward SSHFS prevents VM from accessing host
- SSH key-based authentication only (no passwords)
- Credentials injected at provisioning time (not runtime)
- Lima manages SSH configuration automatically

For production use, consider:

- Implementing additional firewall rules
- Regular security updates via reprovisioning
- Credential rotation strategies
- Audit logging for VM access

## References

- [Lima Documentation](https://lima-vm.io/)
- [Debian Cloud Images](https://cloud.debian.org/images/cloud/)
- [SSHFS Documentation](https://github.com/libfuse/sshfs)
- [QEMU Documentation](https://www.qemu.org/documentation/)
