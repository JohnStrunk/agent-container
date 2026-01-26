#!/bin/bash
# Common tool installation script for both container and VM environments
# This script installs tools that are not available via package managers
# or require custom installation procedures.

set -e -o pipefail

echo "Installing Claude Code using official installer..."
curl -fsSL https://claude.ai/install.sh | bash

# Copy Claude Code to system location for container use
# The installer creates a symlink in ~/.local/bin, but we need the actual binary
# in a system path so it's available to dynamically created users at runtime

# Determine the home directory (cloud-init runcmd may not set $HOME)
if [ -n "$HOME" ] && [ -d "$HOME" ]; then
    claude_home="$HOME"
else
    claude_home="/root"
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
fi

# Verify installation succeeded
if ! command -v claude &> /dev/null; then
    echo "ERROR: Claude Code installation failed - claude command not found"
    exit 1
fi

echo "Claude Code installed successfully:"
claude --version
