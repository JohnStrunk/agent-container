#!/bin/bash
# Lima provisioning script for agent-vm
# Runs as root during first VM start to install packages and configure environment
#
# This script is embedded by Lima using the "file:" property and runs in the VM.
# Template variables {{.User}} will be expanded by Lima.

set -e -o pipefail

# Logging functions
info() { echo "[INFO] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# Verify we're running as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must run as root"
fi

# Get Lima user dynamically
# Lima creates a user matching the host user
# Find the user with a real home directory (not /nonexistent or /run/*)
LIMA_USER=$(getent passwd | awk -F: '$6 ~ /^\/home\// && $7 !~ /nologin|false/ { print $1; exit }')

if [ -z "$LIMA_USER" ]; then
    error "Could not detect Lima user (no non-system user found)"
fi

info "Provisioning VM for user: $LIMA_USER"

# ==============================================================================
# Verify file availability (files copied via mode:data in agent-vm.yaml)
# ==============================================================================
info "Verifying files copied via Lima mode:data..."

# List files we expect to find in /tmp
expected_files=(
    "/tmp/apt-packages.txt"
    "/tmp/npm-packages.txt"
    "/tmp/python-packages.txt"
    "/tmp/versions.txt"
    "/tmp/envvars.txt"
    "/tmp/install-tools.sh"
    "/tmp/homedir/.claude.json"
    "/tmp/homedir/.gitconfig"
    "/tmp/homedir/.claude/settings.json"
    "/tmp/homedir/.local/bin/start-claude"
)

missing_count=0
for file in "${expected_files[@]}"; do
    if [ -e "$file" ]; then
        info "  ✓ Found: $file"
    else
        echo "[ERROR]   ✗ Missing: $file" >&2
        missing_count=$((missing_count + 1))
    fi
done

if [ $missing_count -gt 0 ]; then
    error "Missing $missing_count expected file(s). Lima mode:data copy failed."
fi

info "All expected files verified in /tmp/"

# ==============================================================================
# Package lists (sourced from common/packages/*.txt)
# ==============================================================================
info "Reading package lists from common directory..."

# Verify package list files exist
for file in apt-packages.txt npm-packages.txt python-packages.txt versions.txt; do
    if [ ! -f "/tmp/$file" ]; then
        error "Package list not found: /tmp/$file"
    fi
done

# Source version numbers
# shellcheck source=/dev/null
source /tmp/versions.txt

# Read APT packages (filter comments and blank lines)
mapfile -t APT_PACKAGES < <(grep -v '^#' /tmp/apt-packages.txt | grep -v '^$')

# VM-specific packages (not in common, only needed in VM)
VM_PACKAGES=(
    docker.io
    podman
    qemu-system-x86
    qemu-utils
    qemu-guest-agent
    wget
    htop
)

# Read NPM packages (filter comments and blank lines)
mapfile -t NPM_PACKAGES < <(grep -v '^#' /tmp/npm-packages.txt | grep -v '^$')

# Read Python packages (filter comments and blank lines)
mapfile -t PYTHON_PACKAGES < <(grep -v '^#' /tmp/python-packages.txt | grep -v '^$')

# ==============================================================================
# 1. Install system packages
# ==============================================================================
info "Installing APT packages..."
apt-get update
apt-get install -y "${APT_PACKAGES[@]}" "${VM_PACKAGES[@]}"

# ==============================================================================
# 2. Install Lima for nested VM support
# ==============================================================================
info "Installing Lima for nested VM support..."

if ! command -v curl > /dev/null 2>&1; then
    error "curl not found - required for Lima installation"
fi

LIMA_VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')
if [ -z "$LIMA_VERSION" ]; then
    error "Failed to fetch Lima version from GitHub"
fi

info "Installing Lima version: $LIMA_VERSION"
curl -fsSL "https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/lima-${LIMA_VERSION}-Linux-x86_64.tar.gz" | tar -C /usr/local -xzf -

# Verify Lima installation (check binary exists, don't run it as root)
if [ ! -x /usr/local/bin/limactl ]; then
    error "Lima installation failed - limactl binary not found or not executable"
fi

info "Lima installed successfully"

# ==============================================================================
# 3. Install Node.js packages
# ==============================================================================
info "Installing Node.js packages..."
for pkg in "${NPM_PACKAGES[@]}"; do
    npm install -g "$pkg"
done

# ==============================================================================
# 4. Install Python packages
# ==============================================================================
info "Installing Python packages..."
for pkg in "${PYTHON_PACKAGES[@]}"; do
    pip install --break-system-packages "$pkg"
done

# ==============================================================================
# 5. Install additional tools (Go, hadolint, Claude Code)
# ==============================================================================
info "Installing additional tools..."

# Install Go (version from common/packages/versions.txt)
info "Installing Go $GOLANG_VERSION..."
if [ -z "$GOLANG_VERSION" ]; then
    error "GOLANG_VERSION not set (should be sourced from versions.txt)"
fi
curl -fsSL "https://go.dev/dl/go${GOLANG_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xzf -

# Configure Go PATH and user local bin
mkdir -p /etc/profile.d
cat > /etc/profile.d/go-path.sh <<'EOF'
export PATH="/usr/local/go/bin:$PATH"
EOF
chmod 644 /etc/profile.d/go-path.sh

# Add ~/.local/bin to PATH for all users (for Claude Code and other user tools)
cat > /etc/profile.d/user-local-bin.sh <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
EOF
chmod 644 /etc/profile.d/user-local-bin.sh

# Install hadolint
HADOLINT_VERSION="2.12.0"
info "Installing hadolint $HADOLINT_VERSION..."
curl -fsSL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-x86_64" -o /usr/local/bin/hadolint
chmod +x /usr/local/bin/hadolint

# Note: Claude Code installation moved to user-level provision in agent-vm.yaml
# to ensure it installs to the user's ~/.local/bin

# ==============================================================================
# 6. Copy homedir configuration files
# ==============================================================================
info "Setting up user home directory configuration..."

USER_HOME=$(getent passwd "$LIMA_USER" | cut -d: -f6)
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    error "User home directory not found for: $LIMA_USER"
fi

# Create .claude directory structure
mkdir -p "$USER_HOME/.claude"
mkdir -p "$USER_HOME/.local/bin"

# Create .claude.json
cat > "$USER_HOME/.claude.json" <<'EOF'
{
  "defaultSession": "default",
  "defaultModel": "claude-sonnet-4-5-20250929"
}
EOF

# Create .claude/settings.json
cat > "$USER_HOME/.claude/settings.json" <<'EOF'
{
  "betaTools": ["read", "edit", "write", "task", "bash", "glob", "grep", "webFetch", "webSearch"]
}
EOF

# Create .gitconfig
cat > "$USER_HOME/.gitconfig" <<'EOF'
[init]
    defaultBranch = main
[core]
    editor = vim
[user]
    name = Agent User
    email = agent@localhost
[pull]
    rebase = false
EOF

# Create start-claude helper script
cat > "$USER_HOME/.local/bin/start-claude" <<'EOF'
#!/bin/bash
exec claude "$@"
EOF
chmod +x "$USER_HOME/.local/bin/start-claude"

# Set ownership
USER_UID=$(id -u "$LIMA_USER")
USER_GID=$(id -g "$LIMA_USER")
chown -R "$USER_UID:$USER_GID" "$USER_HOME"

info "Home directory configuration complete"

# ==============================================================================
# 7. Inject GCP credentials if provided
# ==============================================================================
info "Checking for GCP credentials..."

# Source GCP environment if it was injected via cloud-init
if [ -f /tmp/gcp-env.sh ]; then
    # shellcheck source=/dev/null
    source /tmp/gcp-env.sh
fi

if [ -n "$GCP_CREDENTIALS_JSON" ]; then
    info "Injecting GCP credentials..."
    mkdir -p /etc/google
    echo "$GCP_CREDENTIALS_JSON" > /etc/google/application_default_credentials.json
    chmod 644 /etc/google/application_default_credentials.json

    cat > /etc/profile.d/ai-agent-env.sh <<EOF
export GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json
export ANTHROPIC_VERTEX_PROJECT_ID="${VERTEX_PROJECT_ID}"
export CLOUD_ML_REGION="${VERTEX_REGION}"
export CLAUDE_CODE_USE_VERTEX="true"
EOF
    chmod 644 /etc/profile.d/ai-agent-env.sh
    info "GCP credentials configured"
else
    info "No GCP credentials provided"
fi

# ==============================================================================
# 8. Configure user permissions
# ==============================================================================
info "Configuring user permissions..."

usermod -aG docker "$LIMA_USER"

if getent group podman > /dev/null; then
    usermod -aG podman "$LIMA_USER"
fi

if getent group kvm > /dev/null; then
    usermod -aG kvm "$LIMA_USER"
fi

usermod --add-subuids 200000-265535 --add-subgids 200000-265535 "$LIMA_USER"

# ==============================================================================
# 9. Create environment marker
# ==============================================================================
echo "agent-vm" > /etc/agent-environment
chmod 644 /etc/agent-environment

# ==============================================================================
# Provisioning complete
# ==============================================================================
info "Provisioning complete! VM is ready for use."
info "User: $LIMA_USER"
info "Claude Code: installed (run as user to check version)"
info "Go: $(/usr/local/go/bin/go version 2>&1 | awk '{print $3}' || echo 'installed')"
info "Lima: installed (run as user to check version)"

exit 0
