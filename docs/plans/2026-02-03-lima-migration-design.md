# Lima Migration Design

**Date:** 2026-02-03
**Status:** Proposed
**Author:** Claude Sonnet 4.5

## Overview

Migrate the VM approach from Terraform + libvirt to Lima (https://lima-vm.io/) to enable cross-platform support (Linux, macOS, Windows via WSL2) while maintaining strong isolation and the current single-VM, multi-workspace architecture.

## Goals

1. **Cross-platform support** - Linux and macOS mandatory, Windows via WSL2
2. **Simplification** - Reduce infrastructure code complexity
3. **Better developer experience** - Leverage Lima's automatic SSH and network setup
4. **Preserve isolation** - Maintain forward SSHFS (VM cannot access host)
5. **Common config compatibility** - Keep `common/` directory shared with container approach

## Architecture

### Core Principles

- **Single persistent VM** named `agent-vm` running Debian 13
- **Multiple workspace directories** within the VM (`~/workspace/<repo>-<branch>/`)
- **Forward SSHFS** for file sharing (host mounts VM directories)
- **Declarative configuration** via `vm/agent-vm.yaml` Lima template
- **Cross-platform** support for Linux, macOS, and Windows (WSL2)
- **Common config sharing** with container approach via `common/` directory

### Key Components

1. **Lima template** (`vm/agent-vm.yaml`) - Declarative VM configuration
2. **Provision script** (`vm/lima-provision.sh`) - Installs packages and tools
3. **CLI wrapper** (`vm/agent-vm`) - Manages workspaces, SSHFS mounts, git sync
4. **Common configs** (`common/homedir/`, `common/packages/`) - Shared between container/VM

### What Lima Provides

- VM lifecycle management (`limactl start/stop/delete`)
- Automatic SSH configuration and key management
- Network setup with dynamic IP allocation
- Cloud-init integration for provisioning
- Cross-platform VM backend abstraction (QEMU)

### What We Customize

- File sharing direction (forward SSHFS instead of Lima's default reverse)
- Workspace management and git synchronization
- Credential injection via provision scripts
- CLI interface for workspace operations

## File Structure

### New Structure

```text
vm/
├── agent-vm.yaml              # Lima template (replaces main.tf)
├── lima-provision.sh          # Provisioning script (replaces cloud-init.yaml.tftpl)
├── agent-vm                   # CLI wrapper (refactored, keeps name)
├── vm-common.sh               # Shared functions (minimal changes)
├── README.md                  # Updated documentation
├── CLAUDE.md                  # Updated documentation
└── TROUBLESHOOTING.md         # Updated documentation

../common/                     # Unchanged structure
├── homedir/                   # Config files (.claude.json, .gitconfig, etc.)
├── packages/                  # Package lists (apt, npm, python)
│   ├── apt-packages.txt
│   ├── npm-packages.txt
│   ├── python-packages.txt
│   ├── versions.txt
│   └── envvars.txt           # Passed through at connection time
└── scripts/
    └── install-tools.sh       # Tool installation (Go, hadolint, etc.)
```

### Files Removed

- `main.tf`, `variables.tf`, `outputs.tf` - Replaced by `agent-vm.yaml`
- `cloud-init.yaml.tftpl` - Replaced by `lima-provision.sh`
- `libvirt-nat-fix.sh` - Not needed (Lima handles networking)
- `vm-ssh-key`, `vm-ssh-key.pub` - Lima manages keys automatically

## CLI Interface

### New Command Structure

```bash
# VM lifecycle
./agent-vm start [--memory M --vcpu N]    # Explicitly start/create VM
./agent-vm destroy                         # Delete VM entirely (stops if running)
./agent-vm status                          # Show VM state and workspaces

# Workspace operations (VM auto-starts if needed)
./agent-vm connect [branch]                # Create/connect/shell (VM if no arg)
./agent-vm push <branch>                   # Push branch to workspace
./agent-vm fetch <branch>                  # Fetch branch from workspace
./agent-vm clean <branch>                  # Delete specific workspace
./agent-vm clean-all                       # Delete all workspaces
```

### Command Behaviors

**`start [--memory M --vcpu N]`**
- Creates Lima VM if it doesn't exist
- Starts VM if stopped
- Optional flags override default resources (only at creation time)
- Runs `lima-provision.sh` via Lima's provision mechanism
- Waits for VM to be ready (SSH accessible)

**`destroy`**
- Unmounts all SSHFS mounts
- Stops VM if running (via `limactl stop`)
- Deletes VM and all workspaces (via `limactl delete agent-vm`)
- Removes mount directory `~/.agent-vm-mounts/workspace/`
- Succeeds whether VM is running or stopped

**`status`**
- Shows VM state (running/stopped/non-existent)
- If running: Lists all workspaces with current branches
- Shows SSHFS mount status for each workspace
- Shows resource allocation (CPU/memory from Lima config)

**`connect [branch]`**
- If no branch: Opens shell directly to VM
- If branch specified:
  - Starts VM if not running
  - Creates workspace directory `~/workspace/<repo>-<branch>/` if needed
  - Initializes git repo in workspace if needed
  - Pushes branch from host to workspace
  - Mounts workspace via SSHFS to `~/.agent-vm-mounts/workspace/`
  - Sets environment variables from `envvars.txt`
  - Opens SSH session into workspace directory

**`push <branch>`**
- Pushes local branch to VM workspace
- Creates workspace if doesn't exist
- Updates VM copy with host version

**`fetch <branch>`**
- Fetches commits from VM workspace to host repo
- Warns if VM has uncommitted changes
- Uses `git pull` if branch is checked out, `git fetch` otherwise

**`clean <branch>`**
- Unmounts SSHFS
- Deletes workspace directory in VM via SSH
- Removes local mount directory

**`clean-all`**
- Unmounts all SSHFS mounts
- Deletes all workspace directories in VM
- Keeps VM running
- Removes all local mount directories

## Lima Template

### `agent-vm.yaml` Structure

```yaml
# Lima VM template for agent-vm
# Provides isolated development environment for AI coding agents

# VM backend - QEMU works on both Linux and macOS
vmType: "qemu"

# OS images
images:
  - location: "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
    arch: "x86_64"

# Default resources (overridable via start command)
cpus: 4
memory: "8GiB"
disk: "100GiB"

# Disable Lima's default mounts (we use forward SSHFS instead)
mounts: []

# SSH configuration
ssh:
  localPort: 0  # Auto-assign port
  loadDotSSHPubKeys: false  # Use Lima-generated keys only
  forwardAgent: false       # Security: no agent forwarding

# Port forwarding (none needed by default)
portForwards: []

# Provisioning scripts
provision:
  # System-level provisioning
  - mode: system
    script: |
      #!/bin/bash
      set -e -o pipefail

      # Run the main provisioning script
      {{.Dir}}/lima-provision.sh

  # User-level setup (runs as default Lima user)
  - mode: user
    script: |
      #!/bin/bash
      set -e -o pipefail

      # Create workspace directory
      mkdir -p ~/workspace

      # Set default directory in bashrc
      echo "cd ~/workspace" >> ~/.bashrc

# Firmware (default UEFI)
firmware:
  legacyBIOS: false

# Video display (headless)
video:
  display: "none"

# Network (default user-mode networking)
networks:
  - lima: shared
```

### Key Decisions

1. **No digest** - Always uses latest Debian 13 image
2. **vmType: qemu** - Cross-platform compatibility
3. **mounts: []** - Explicitly disabled (using forward SSHFS)
4. **`{{.Dir}}/lima-provision.sh`** - References script from template directory
5. **localPort: 0** - Lima auto-assigns SSH port, avoiding conflicts

### Resource Override Handling

When `--memory` or `--vcpu` flags are used with `start`, the `agent-vm` script will:
1. Read the template file
2. Generate a temporary template with replaced values
3. Pass temporary template to `limactl start`
4. Clean up temporary file

## Provisioning Script

### `lima-provision.sh` Responsibilities

The provisioning script runs once as root during first VM start and handles:

1. Install system packages from `common/packages/apt-packages.txt`
2. Install Node.js packages from `common/packages/npm-packages.txt`
3. Install Python packages from `common/packages/python-packages.txt`
4. Run `common/scripts/install-tools.sh` for Go, hadolint, etc.
5. Configure Go PATH in `/etc/profile.d/`
6. Copy homedir files to default user's home
7. Inject GCP credentials if provided
8. Configure user permissions (sudo, groups)
9. Install Lima for nested VM support
10. Create environment marker `/etc/agent-environment`

### VM-Specific Packages

```bash
# VM-specific packages for nested virtualization and containers
apt-get install -y \
  docker.io \
  podman \
  qemu-system-x86 \
  qemu-utils \
  qemu-guest-agent \
  wget \
  htop \
  curl

# Install Lima for nested VM support
LIMA_VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
curl -fsSL "https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/lima-${LIMA_VERSION}-Linux-x86_64.tar.gz" | tar -C /usr/local -xzf -

# Verify Lima installation
limactl --version

# Configure user permissions
LIMA_USER="{{.User}}"
usermod -aG docker "$LIMA_USER"
getent group podman && usermod -aG podman "$LIMA_USER" || true
usermod -aG kvm "$LIMA_USER" || true

# Configure subuid/subgid for rootless Podman
usermod --add-subuids 200000-265535 --add-subgids 200000-265535 "$LIMA_USER"
```

### Key Changes from Cloud-Init

- Uses `{{.Dir}}` to reference files relative to template directory
- Uses `{{.User}}` for Lima's default user (matches host username)
- Credentials passed via environment variables (set by `agent-vm` script)
- Simpler bash script instead of YAML templating
- Direct file operations instead of cloud-init's write_files
- Installs Lima instead of libvirt/Terraform

## File Sharing

### SSHFS Mounting Strategy

Forward SSHFS (host mounts VM directories) preserves security isolation.

### Mount Structure

```
Host filesystem:
~/.agent-vm-mounts/
└── workspace/                   # Single SSHFS mount point
    ├── <repo>-<branch1>/        # Visible via mount
    ├── <repo>-<branch2>/        # Visible via mount
    └── ...

VM filesystem:
/home/user/workspace/            # This entire dir is mounted
├── <repo>-<branch1>/
├── <repo>-<branch2>/
└── ...
```

### SSHFS Implementation

```bash
# Get SSH config from Lima
SSH_CONFIG="$HOME/.lima/agent-vm/ssh.config"
VM_HOST="lima-agent-vm"

# Create mount point (single directory for all workspaces)
MOUNT_DIR="$HOME/.agent-vm-mounts/workspace"
mkdir -p "$MOUNT_DIR"

# Check if already mounted
if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
  return 0  # Already mounted
fi

# Mount entire workspace directory
sshfs -F "$SSH_CONFIG" \
  -o StrictHostKeyChecking=no \
  -o UserKnownHostsFile=/dev/null \
  -o reconnect \
  -o ServerAliveInterval=15 \
  -o ServerAliveCountMax=3 \
  -o follow_symlinks \
  "$VM_HOST:/home/user/workspace" \
  "$MOUNT_DIR"
```

### SSHFS Options

- `-F "$SSH_CONFIG"` - Use Lima's SSH configuration (handles auth, port, keys)
- `follow_symlinks` - Follow symlinks in the VM filesystem
- `reconnect` - Auto-reconnect if connection drops
- `ServerAliveInterval=15` - Keep connection alive with 15s pings
- `ServerAliveCountMax=3` - Retry 3 times before giving up

### Unmounting

```bash
# Unmount (single mount point)
MOUNT_DIR="$HOME/.agent-vm-mounts/workspace"
if mountpoint -q "$MOUNT_DIR" 2>/dev/null; then
  fusermount -u "$MOUNT_DIR" 2>/dev/null || umount "$MOUNT_DIR" 2>/dev/null
  sleep 1  # Give time for unmount to complete
fi
```

### Security Benefits

- VM cannot initiate connections to host filesystem
- Only mounted directories are visible to host
- VM has no visibility into host filesystem structure
- If VM is compromised, attack surface limited to SSH server

## Git Workflow

### Workspace Repository Structure

Each workspace in the VM is a full git clone (not a worktree), allowing complete independence between workspaces.

### Initial Workspace Creation

```bash
# Change to repository root
cd "$(git rev-parse --show-toplevel)" || exit 1

# On host: Ensure branch exists locally, create if not
if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "Creating branch '$BRANCH' from current HEAD..."
  git branch "$BRANCH"
fi

# Set up SSH for git operations
export GIT_SSH_COMMAND="ssh -F $SSH_CONFIG -o StrictHostKeyChecking=no"

# In VM: Initialize workspace git repo if needed
ssh -F "$SSH_CONFIG" -o StrictHostKeyChecking=no "$VM_HOST" bash -s "$WORKSPACE_NAME" <<'EOF'
  workspace_name="$1"
  if [ ! -d ~/workspace/$workspace_name/.git ]; then
    mkdir -p ~/workspace/$workspace_name
    cd ~/workspace/$workspace_name
    git init
    git config user.name "$(git config user.name || echo 'Agent User')"
    git config user.email "$(git config user.email || echo 'agent@localhost')"
  fi
EOF

# Push branch to VM workspace (not force push)
if git push "ssh://$VM_HOST/home/user/workspace/$WORKSPACE_NAME" "$BRANCH:$BRANCH" 2>&1; then
  # Check out the branch in VM
  ssh -F "$SSH_CONFIG" -o StrictHostKeyChecking=no "$VM_HOST" \
    "cd ~/workspace/$WORKSPACE_NAME && git checkout $BRANCH" 2>/dev/null
  echo "✓ Branch '$BRANCH' pushed to VM workspace"
else
  echo "Error: Could not push branch '$BRANCH' to workspace '$WORKSPACE_NAME'" >&2
  unset GIT_SSH_COMMAND
  exit 1
fi

unset GIT_SSH_COMMAND
```

### Push Operation

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1

# Ensure branch exists
if ! git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "Creating branch '$BRANCH' from current HEAD..."
  git branch "$BRANCH"
fi

export GIT_SSH_COMMAND="ssh -F $SSH_CONFIG -o StrictHostKeyChecking=no"

# Initialize workspace if needed (same as connect)
ssh -F "$SSH_CONFIG" -o StrictHostKeyChecking=no "$VM_HOST" bash -s "$WORKSPACE_NAME" <<'EOF'
  workspace_name="$1"
  if [ ! -d ~/workspace/$workspace_name/.git ]; then
    mkdir -p ~/workspace/$workspace_name
    cd ~/workspace/$workspace_name
    git init
    git config user.name "$(git config user.name || echo 'Agent User')"
    git config user.email "$(git config user.email || echo 'agent@localhost')"
  fi
EOF

# Push branch (not force push - same as connect)
if git push "ssh://$VM_HOST/home/user/workspace/$WORKSPACE_NAME" "$BRANCH:$BRANCH" 2>&1; then
  ssh -F "$SSH_CONFIG" -o StrictHostKeyChecking=no "$VM_HOST" \
    "cd ~/workspace/$WORKSPACE_NAME && git checkout $BRANCH" 2>/dev/null
  echo "✓ Branch '$BRANCH' pushed to VM workspace"
else
  echo "Error: Could not push branch '$BRANCH' to workspace '$WORKSPACE_NAME'" >&2
  unset GIT_SSH_COMMAND
  exit 1
fi

unset GIT_SSH_COMMAND
```

### Fetch Operation

```bash
cd "$(git rev-parse --show-toplevel)" || exit 1

# Check if workspace exists in VM
if ! ssh -F "$SSH_CONFIG" -o StrictHostKeyChecking=no "$VM_HOST" \
     "test -d ~/workspace/$WORKSPACE_NAME" 2>/dev/null; then
  echo "Error: Workspace '$WORKSPACE_NAME' does not exist in VM" >&2
  exit 1
fi

# Check for uncommitted changes in VM (warn but continue)
if ssh -F "$SSH_CONFIG" -o StrictHostKeyChecking=no "$VM_HOST" \
   "cd ~/workspace/$WORKSPACE_NAME && ! git diff --quiet || ! git diff --cached --quiet" 2>/dev/null; then
  echo ""
  echo "⚠️  WARNING: VM workspace has uncommitted changes"
  echo "These will NOT be included in the fetch"
  echo "Fetching anyway..."
  echo ""
fi

# Set up SSH for git
export GIT_SSH_COMMAND="ssh -F $SSH_CONFIG -o StrictHostKeyChecking=no"

# Check if branch is currently checked out on host
current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Fetch branch from VM
if [ "$current_branch" = "$BRANCH" ]; then
  # Branch is checked out - use pull to update working tree
  echo "Branch '$BRANCH' is currently checked out - using git pull..."
  if git pull "ssh://$VM_HOST/home/user/workspace/$WORKSPACE_NAME" "$BRANCH" 2>&1; then
    echo ""
    echo "✓ Branch '$BRANCH' updated and working tree synchronized"
    echo ""
    echo "To view changes:"
    echo "  git log"
    echo ""
  else
    echo "Error: Could not pull branch '$BRANCH' from workspace '$WORKSPACE_NAME'" >&2
    unset GIT_SSH_COMMAND
    exit 1
  fi
else
  # Branch is not checked out - use fetch to update ref only
  if git fetch "ssh://$VM_HOST/home/user/workspace/$WORKSPACE_NAME" "$BRANCH:$BRANCH" 2>&1; then
    echo ""
    echo "✓ Branch '$BRANCH' updated in main repo"
    echo ""
    echo "To view changes:"
    echo "  git checkout $BRANCH"
    echo "  git log"
    echo ""
  else
    echo "Error: Could not fetch branch '$BRANCH' from workspace '$WORKSPACE_NAME'" >&2
    unset GIT_SSH_COMMAND
    exit 1
  fi
fi

unset GIT_SSH_COMMAND
```

### Key Design Points

1. **Full clones, not worktrees** - Each workspace is independent
2. **Git over SSH** - Uses Lima's SSH config for authentication
3. **Normal push (not force)** - Preserves git safety, fails on conflicts
4. **Working tree sync** - `git checkout` updates files after push
5. **Uncommitted change warnings** - User informed before fetch
6. **Branch creation on-the-fly** - Creates branch if it doesn't exist locally

## Environment Variables

### Environment Variables at Connection Time

Environment variables from `common/packages/envvars.txt` are passed through to the SSH session when connecting to a workspace.

### Reading envvars.txt

```bash
# Build environment variable exports from common/packages/envvars.txt
ENV_EXPORTS=""
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
ENVVARS_FILE="$SCRIPT_DIR/../common/packages/envvars.txt"

if [[ -f "$ENVVARS_FILE" ]]; then
  while IFS= read -r var || [[ -n "$var" ]]; do
    # Skip empty lines and comments
    [[ -z "$var" || "$var" =~ ^# ]] && continue

    # Only export if variable is set in host environment
    if [[ -n "${!var:-}" ]]; then
      # Escape special characters for shell (single quotes)
      escaped_value=$(printf '%s' "${!var}" | sed "s/'/'\\\\''/g")
      ENV_EXPORTS+="export $var='$escaped_value'; "
    fi
  done < "$ENVVARS_FILE"
fi
```

### SSH Connection with Environment Variables

**Interactive session:**

```bash
ssh -F "$SSH_CONFIG" -o StrictHostKeyChecking=no "$VM_HOST" \
  -t "${ENV_EXPORTS}cd ~/workspace/$WORKSPACE_NAME 2>/dev/null || cd ~; exec bash -l"
```

**Command execution:**

```bash
ssh -F "$SSH_CONFIG" -o StrictHostKeyChecking=no "$VM_HOST" \
  "${ENV_EXPORTS}cd ~/workspace/$WORKSPACE_NAME 2>/dev/null || cd ~; ${COMMAND[*]}"
```

### Key Behaviors

1. **Only exports if set** - Variables must exist in host environment
2. **Escapes single quotes** - Handles values with special characters safely
3. **Falls back to home** - If workspace doesn't exist, goes to `~`
4. **Interactive shell** - Uses `exec bash -l` to load profile.d files
5. **Command mode** - Supports executing commands without interactive shell

### GCP Credential Environment Variables

If GCP credentials were injected during provisioning, `/etc/profile.d/ai-agent-env.sh` sets:
- `GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json`
- `ANTHROPIC_VERTEX_PROJECT_ID` (if provided during provisioning)
- `CLOUD_ML_REGION` (default: us-central1)
- `CLAUDE_CODE_USE_VERTEX=true`

### Combined Behavior

1. Connection-time exports run first (from ENV_EXPORTS)
2. `bash -l` loads `/etc/profile.d/ai-agent-env.sh` (login shell)
3. Result: Both connection-time and system-wide vars are available

## Credential Injection

### GCP Credential Handling

Credentials are injected during VM provisioning (not at connection time).

### Credential Detection on Host

```bash
# Detect GCP credentials
GCP_CREDS_PATH=""
if [[ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ]]; then
  GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
elif [[ -f "$HOME/.config/gcloud/application_default_credentials.json" ]]; then
  GCP_CREDS_PATH="$HOME/.config/gcloud/application_default_credentials.json"
fi

# Read credentials if found
GCP_CREDS_JSON=""
if [[ -n "$GCP_CREDS_PATH" && -f "$GCP_CREDS_PATH" ]]; then
  GCP_CREDS_JSON=$(cat "$GCP_CREDS_PATH")
  echo "Found GCP credentials at: $GCP_CREDS_PATH"
fi
```

### Passing to Lima Provisioning

```bash
# Export for provision script
export GCP_CREDENTIALS_JSON="$GCP_CREDS_JSON"
export VERTEX_PROJECT_ID="${ANTHROPIC_VERTEX_PROJECT_ID:-}"
export VERTEX_REGION="${CLOUD_ML_REGION:-us-central1}"

# Start VM (provision script will see these env vars)
limactl start "$TEMPLATE_PATH"
```

### Provision Script Usage

```bash
# Inject GCP credentials if provided
if [ -n "$GCP_CREDENTIALS_JSON" ]; then
  echo "Injecting GCP credentials..."
  mkdir -p /etc/google
  echo "$GCP_CREDENTIALS_JSON" > /etc/google/application_default_credentials.json
  chmod 644 /etc/google/application_default_credentials.json

  # Set environment variables in /etc/profile.d/
  cat > /etc/profile.d/ai-agent-env.sh <<EOF
export GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json
export ANTHROPIC_VERTEX_PROJECT_ID="${VERTEX_PROJECT_ID:-}"
export CLOUD_ML_REGION="${VERTEX_REGION:-us-central1}"
export CLAUDE_CODE_USE_VERTEX="true"
EOF
  chmod 644 /etc/profile.d/ai-agent-env.sh
fi
```

### Security Considerations

- Credentials never stored in git repository
- Passed via environment variables (not written to disk on host)
- Written to `/etc/google/` in VM (world-readable, VM isolation provides security)
- Environment variables set system-wide via `/etc/profile.d/`

## Cross-Platform Compatibility

### Platform Support

- **Linux** - Native support via package managers
- **macOS** - Native support via Homebrew
- **Windows** - Via WSL2 (runs Lima inside WSL)

### Platform Differences

| Aspect | Linux | macOS | Notes |
|--------|-------|-------|-------|
| Lima installation | Package manager (apt/yum) | Homebrew | Both straightforward |
| VM backend | QEMU (default) | QEMU (default) | VZ backend macOS-only, not used |
| SSHFS | apt install sshfs | brew install sshfs | FUSE implementations differ |
| Unmount command | `fusermount -u` or `umount` | `umount` only | Script tries both |
| VM performance | Native KVM acceleration | QEMU emulation (slower) | Expected difference |
| Nested virtualization | Requires KVM | Limited/no support | Lima in Lima unlikely on macOS |

### Platform-Agnostic Template

The `agent-vm.yaml` template uses portable Lima features:
- `vmType: "qemu"` - Works on both platforms
- No platform-specific mounts or settings
- Standard networking via Lima's shared network
- Cloud-init supported on both platforms

### Script Platform Detection

```bash
# In agent-vm script
PLATFORM="$(uname -s)"
case "$PLATFORM" in
  Linux*)
    UNMOUNT_CMD="fusermount -u"
    ;;
  Darwin*)
    UNMOUNT_CMD="umount"
    ;;
  *)
    echo "Unsupported platform: $PLATFORM"
    exit 1
    ;;
esac
```

### SSHFS Compatibility

```bash
# Unmount function that works on both platforms
function unmount_vm_workspace {
  local mount_point="$HOME/.agent-vm-mounts/workspace"

  if mountpoint -q "$mount_point" 2>/dev/null; then
    echo "Unmounting: $mount_point"
    # Try fusermount first (Linux), fall back to umount (macOS/Linux)
    fusermount -u "$mount_point" 2>/dev/null || umount "$mount_point" 2>/dev/null
    sleep 1
  fi
}
```

### Windows (WSL2) Support

- Users run `agent-vm` within WSL2 environment
- Lima runs inside WSL2 (Linux behavior)
- SSHFS mounts accessible within WSL2 filesystem
- Native Windows access via `\\wsl$\` network path

## Migration Path

### Breaking Change

The Lima migration is a **breaking change** requiring users to destroy existing Terraform VMs and recreate with Lima.

### Git Repository Changes

**Files removed:**
- `vm/main.tf`
- `vm/variables.tf`
- `vm/outputs.tf`
- `vm/cloud-init.yaml.tftpl`
- `vm/libvirt-nat-fix.sh`

**Files added:**
- `vm/agent-vm.yaml` (Lima template)
- `vm/lima-provision.sh` (provisioning script)

**Files modified:**
- `vm/agent-vm` (refactored for Lima)
- `vm/vm-common.sh` (updated for Lima)
- `vm/README.md` (rewritten)
- `vm/CLAUDE.md` (rewritten)
- `vm/TROUBLESHOOTING.md` (updated)
- `test-integration.sh` (VM tests updated for Lima)

**Files unchanged:**
- `common/` directory (shared with container)
- Root `README.md`, `CLAUDE.md` (updated references only)

### State Management Location

```
Before (Terraform):
vm/terraform.tfstate
vm/.terraform/
vm/vm-ssh-key

After (Lima):
~/.lima/agent-vm/
```

### Breaking Changes

1. **SSH keys** - New Lima-managed keys (old keys discarded)
2. **CLI interface** - New command structure (`connect` instead of `-b`)
3. **VM IP** - Dynamic instead of static (transparent via Lima SSH config)
4. **Resource specification** - Must use `--memory`/`--vcpu` with `start`, not `connect`

### Non-Breaking Aspects

1. **Common configs** - `common/` directory unchanged
2. **Workspace structure** - Same (`~/workspace/<repo>-<branch>/`)
3. **Git workflow** - Identical (push/fetch operations)
4. **SSHFS mount** - Same location and behavior (`~/.agent-vm-mounts/workspace/`)
5. **Integration tests** - Same test scenarios, different implementation

## Implementation Considerations

### Lima Installation Requirements

Users must install Lima before using the VM approach:

```bash
# Linux (Debian/Ubuntu)
sudo apt-get install lima

# macOS
brew install lima

# Verify installation
limactl --version
```

### Resource Override Implementation

The `agent-vm` script handles resource overrides by generating a temporary template:

```bash
if [[ -n "$MEMORY" || -n "$VCPU" ]]; then
  # Read base template
  TEMP_TEMPLATE=$(mktemp)
  cp "$SCRIPT_DIR/agent-vm.yaml" "$TEMP_TEMPLATE"

  # Replace resource values if specified
  [[ -n "$MEMORY" ]] && sed -i "s/^memory:.*/memory: \"${MEMORY}GiB\"/" "$TEMP_TEMPLATE"
  [[ -n "$VCPU" ]] && sed -i "s/^cpus:.*/cpus: $VCPU/" "$TEMP_TEMPLATE"

  TEMPLATE_PATH="$TEMP_TEMPLATE"
else
  TEMPLATE_PATH="$SCRIPT_DIR/agent-vm.yaml"
fi
```

### Integration Test Updates

The `test-integration.sh` script VM tests will be updated to:
1. Check for Lima installation
2. Use `limactl` commands instead of Terraform
3. Verify Lima VM creation and provisioning
4. Test workspace operations with Lima-based VM
5. Clean up Lima VMs after tests

## Summary

The Lima migration simplifies the VM approach while maintaining:
- Strong security isolation (forward SSHFS)
- Single-VM, multi-workspace architecture
- Git workflow compatibility
- Cross-platform support (Linux, macOS, Windows)
- Common config sharing with container approach

Key improvements:
- Reduced infrastructure code (no Terraform state management)
- Simpler networking (Lima handles automatically)
- Better cross-platform support (native macOS)
- Automatic SSH configuration management
- Declarative VM configuration (YAML template)
