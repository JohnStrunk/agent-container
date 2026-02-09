#!/bin/bash
# Common tool installation script for both container and VM environments
# This script installs tools that are not available via package managers
# or require custom installation procedures.

set -e -o pipefail

echo "Installing kubectl from Kubernetes apt repository..."
# Create keyrings directory if it doesn't exist
mkdir -p /etc/apt/keyrings
chmod 755 /etc/apt/keyrings

# Download and install the Kubernetes GPG key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.35/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# Add the Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.35/deb/ /' | tee /etc/apt/sources.list.d/kubernetes.list
chmod 644 /etc/apt/sources.list.d/kubernetes.list

# Update package index and install kubectl
apt-get update
apt-get install -y kubectl

# Verify kubectl installation
if ! command -v kubectl &> /dev/null; then
    echo "ERROR: kubectl installation failed - kubectl command not found"
    exit 1
fi

echo "kubectl installed successfully:"
kubectl version --client

echo "Installing Claude Code using official installer..."
curl -fsSL https://claude.ai/install.sh | bash

# Copy Claude Code to system location for multi-user access
# The installer places the binary in ~/.local/bin, but we need it in a system path
# so it's available to all users, including dynamically created container users.
# Container environments may create users at runtime that don't have access to the
# build-time user's home directory, so /usr/local/bin ensures universal availability.

# Determine the home directory (cloud-init runcmd may not set $HOME)
if [ -n "$HOME" ] && [ -d "$HOME" ]; then
    claude_home="$HOME"
else
    # Fallback: try to get home from passwd database, then try /root
    claude_home=$(getent passwd "$(whoami)" 2>/dev/null | cut -d: -f6)
    if [ -z "$claude_home" ] || [ ! -d "$claude_home" ]; then
        claude_home="/root"
    fi
fi

# Check that the installer created the claude binary
if [ ! -L "$claude_home/.local/bin/claude" ] && [ ! -f "$claude_home/.local/bin/claude" ]; then
    echo "ERROR: Claude installer did not create $claude_home/.local/bin/claude"
    exit 1
fi

if [ -L "$claude_home/.local/bin/claude" ]; then
    # Follow the symlink and copy the actual binary
    claude_target=$(readlink -f "$claude_home/.local/bin/claude")
    if [ -z "$claude_target" ] || [ ! -f "$claude_target" ]; then
        echo "ERROR: Failed to resolve Claude symlink to valid binary"
        exit 1
    fi
    cp "$claude_target" /usr/local/bin/claude
    chmod 755 /usr/local/bin/claude
    echo "Copied Claude Code binary to /usr/local/bin for system-wide access"
elif [ -f "$claude_home/.local/bin/claude" ]; then
    # If it's a regular file, just copy it
    cp "$claude_home/.local/bin/claude" /usr/local/bin/claude
    chmod 755 /usr/local/bin/claude
    echo "Copied Claude Code to /usr/local/bin for system-wide access"
else
    # This should never happen due to the check above, but be explicit
    echo "ERROR: Unexpected state - claude binary exists but is neither symlink nor file"
    exit 1
fi

# Verify installation succeeded
if ! command -v claude &> /dev/null; then
    echo "ERROR: Claude Code installation failed - claude command not found"
    exit 1
fi

echo "Claude Code installed successfully:"
claude --version
