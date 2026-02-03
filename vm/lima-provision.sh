#!/bin/bash
# Lima provisioning script for agent-vm
# Runs as root during first VM start to install packages and configure environment
#
# Template variables available:
#   {{.Dir}} - Directory containing this script (for file references)
#   {{.User}} - Lima's default user (matches host username)
#
# Environment variables for credentials (set by agent-vm script):
#   GCP_CREDENTIALS_JSON - GCP service account credentials
#   VERTEX_PROJECT_ID - Vertex AI project ID
#   VERTEX_REGION - Vertex AI region

set -e -o pipefail

# Color output for better readability
info() { echo "[INFO] $*"; }
error() { echo "[ERROR] $*" >&2; exit 1; }

# Verify we're running as root
if [ "$(id -u)" -ne 0 ]; then
    error "This script must run as root"
fi

# Verify template variables are available
LIMA_USER="{{.User}}"
SCRIPT_DIR="{{.Dir}}"

if [ -z "$LIMA_USER" ] || [ "$LIMA_USER" = "{{.User}}" ]; then
    error "Lima user not set - template variable {{.User}} not expanded"
fi

if [ -z "$SCRIPT_DIR" ] || [ "$SCRIPT_DIR" = "{{.Dir}}" ]; then
    error "Script directory not set - template variable {{.Dir}} not expanded"
fi

info "Provisioning VM for user: $LIMA_USER"
info "Script directory: $SCRIPT_DIR"

# ==============================================================================
# 1. Install system packages from common/packages/apt-packages.txt
# ==============================================================================
info "Installing system packages from apt-packages.txt..."

APT_PACKAGES_FILE="$SCRIPT_DIR/../common/packages/apt-packages.txt"
if [ ! -f "$APT_PACKAGES_FILE" ]; then
    error "apt-packages.txt not found at: $APT_PACKAGES_FILE"
fi

# Update package lists
apt-get update

# Read packages from file, filter out comments and empty lines
PACKAGES=$(grep -v '^#' "$APT_PACKAGES_FILE" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
if [ -n "$PACKAGES" ]; then
    info "Installing: $PACKAGES"
    # shellcheck disable=SC2086
    apt-get install -y $PACKAGES
else
    error "No packages found in apt-packages.txt"
fi

# ==============================================================================
# 2. Install VM-specific packages
# ==============================================================================
info "Installing VM-specific packages..."

apt-get install -y \
    docker.io \
    podman \
    qemu-system-x86 \
    qemu-utils \
    qemu-guest-agent \
    wget \
    htop

info "VM-specific packages installed"

# ==============================================================================
# 3. Install Lima for nested VM support
# ==============================================================================
info "Installing Lima for nested VM support..."

# Get latest Lima version from GitHub
LIMA_VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/lima/releases/latest | grep '"tag_name"' | sed -E 's/.*"v([^"]+)".*/\1/')

if [ -z "$LIMA_VERSION" ]; then
    error "Failed to fetch Lima version from GitHub"
fi

info "Installing Lima version: $LIMA_VERSION"

# Download and extract Lima
curl -fsSL "https://github.com/lima-vm/lima/releases/download/v${LIMA_VERSION}/lima-${LIMA_VERSION}-Linux-x86_64.tar.gz" | tar -C /usr/local -xzf -

# Verify Lima installation
if ! /usr/local/bin/limactl --version; then
    error "Lima installation failed"
fi

info "Lima installed successfully"

# ==============================================================================
# 4. Install Node.js packages from common/packages/npm-packages.txt
# ==============================================================================
info "Installing Node.js packages..."

NPM_PACKAGES_FILE="$SCRIPT_DIR/../common/packages/npm-packages.txt"
if [ ! -f "$NPM_PACKAGES_FILE" ]; then
    error "npm-packages.txt not found at: $NPM_PACKAGES_FILE"
fi

NPM_PACKAGES=$(grep -v '^#' "$NPM_PACKAGES_FILE" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
if [ -n "$NPM_PACKAGES" ]; then
    info "Installing npm packages: $NPM_PACKAGES"
    # shellcheck disable=SC2086
    npm install -g $NPM_PACKAGES
else
    info "No npm packages to install"
fi

# ==============================================================================
# 5. Install Python packages from common/packages/python-packages.txt
# ==============================================================================
info "Installing Python packages..."

PYTHON_PACKAGES_FILE="$SCRIPT_DIR/../common/packages/python-packages.txt"
if [ ! -f "$PYTHON_PACKAGES_FILE" ]; then
    error "python-packages.txt not found at: $PYTHON_PACKAGES_FILE"
fi

PYTHON_PACKAGES=$(grep -v '^#' "$PYTHON_PACKAGES_FILE" | grep -v '^[[:space:]]*$' | tr '\n' ' ')
if [ -n "$PYTHON_PACKAGES" ]; then
    info "Installing Python packages: $PYTHON_PACKAGES"
    # shellcheck disable=SC2086
    pip install --break-system-packages $PYTHON_PACKAGES
else
    info "No Python packages to install"
fi

# ==============================================================================
# 6. Run common/scripts/install-tools.sh for Go, hadolint, etc.
# ==============================================================================
info "Running install-tools.sh for additional tooling..."

INSTALL_TOOLS_SCRIPT="$SCRIPT_DIR/../common/scripts/install-tools.sh"
if [ ! -f "$INSTALL_TOOLS_SCRIPT" ]; then
    error "install-tools.sh not found at: $INSTALL_TOOLS_SCRIPT"
fi

if [ ! -x "$INSTALL_TOOLS_SCRIPT" ]; then
    chmod +x "$INSTALL_TOOLS_SCRIPT"
fi

"$INSTALL_TOOLS_SCRIPT"

info "install-tools.sh completed"

# ==============================================================================
# 7. Configure Go PATH in /etc/profile.d/
# ==============================================================================
info "Configuring Go PATH..."

mkdir -p /etc/profile.d
cat > /etc/profile.d/go-path.sh <<'EOF'
export PATH="/usr/local/go/bin:$PATH"
EOF
chmod 644 /etc/profile.d/go-path.sh

info "Go PATH configured"

# ==============================================================================
# 8. Copy homedir files to Lima user's home
# ==============================================================================
info "Copying homedir files to user's home directory..."

HOMEDIR_SOURCE="$SCRIPT_DIR/../common/homedir"
if [ ! -d "$HOMEDIR_SOURCE" ]; then
    error "homedir not found at: $HOMEDIR_SOURCE"
fi

USER_HOME=$(getent passwd "$LIMA_USER" | cut -d: -f6)
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    error "User home directory not found for: $LIMA_USER"
fi

# Copy files preserving structure
cp -r "$HOMEDIR_SOURCE"/. "$USER_HOME"/

# Get user's UID and GID
USER_UID=$(id -u "$LIMA_USER")
USER_GID=$(id -g "$LIMA_USER")

# Set ownership
chown -R "$USER_UID:$USER_GID" "$USER_HOME"

# Make start-claude executable if it exists
if [ -f "$USER_HOME/.local/bin/start-claude" ]; then
    chmod +x "$USER_HOME/.local/bin/start-claude"
fi

info "Homedir files copied and ownership set"

# ==============================================================================
# 9. Inject GCP credentials if provided
# ==============================================================================
info "Checking for GCP credentials..."

if [ -n "$GCP_CREDENTIALS_JSON" ]; then
    info "Injecting GCP credentials..."

    mkdir -p /etc/google
    echo "$GCP_CREDENTIALS_JSON" > /etc/google/application_default_credentials.json
    chmod 644 /etc/google/application_default_credentials.json

    # Configure GCP environment variables
    cat > /etc/profile.d/ai-agent-env.sh <<EOF
export GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json
export ANTHROPIC_VERTEX_PROJECT_ID="${VERTEX_PROJECT_ID}"
export CLOUD_ML_REGION="${VERTEX_REGION}"
export CLAUDE_CODE_USE_VERTEX="true"
EOF
    chmod 644 /etc/profile.d/ai-agent-env.sh

    info "GCP credentials configured"
else
    info "No GCP credentials provided (GCP_CREDENTIALS_JSON not set)"
fi

# ==============================================================================
# 10. Configure user permissions
# ==============================================================================
info "Configuring user permissions..."

# Add user to docker group
usermod -aG docker "$LIMA_USER"

# Add user to podman group (if it exists)
if getent group podman > /dev/null; then
    usermod -aG podman "$LIMA_USER"
fi

# Add user to kvm group (for nested virtualization)
if getent group kvm > /dev/null; then
    usermod -aG kvm "$LIMA_USER"
fi

# Configure subuid/subgid for rootless Podman
# Use 200000+ range to avoid conflicts with user UIDs (typically <200000)
usermod --add-subuids 200000-265535 --add-subgids 200000-265535 "$LIMA_USER"

info "User permissions configured"

# ==============================================================================
# 11. Create environment marker
# ==============================================================================
info "Creating environment marker..."

echo "agent-vm" > /etc/agent-environment
chmod 644 /etc/agent-environment

info "Environment marker created"

# ==============================================================================
# Provisioning complete
# ==============================================================================
info "Provisioning complete! VM is ready for use."
info "User: $LIMA_USER"
info "Claude Code: $(claude --version 2>&1 | head -1 || echo 'installed')"
info "Go: $(go version 2>&1 | awk '{print $3}' || echo 'installed')"
info "Lima: $(limactl --version 2>&1 | head -1 || echo 'installed')"

exit 0
