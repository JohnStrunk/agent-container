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

# Wait for the installer to finish creating the symlink and downloading the binary
# The installer may create the symlink before the binary is fully downloaded
max_wait=30
waited=0
while [ $waited -lt $max_wait ]; do
    if [ -L "$HOME/.local/bin/claude" ]; then
        # Symlink exists, now check if target exists
        if claude_target=$(readlink -f "$HOME/.local/bin/claude") && [ -f "$claude_target" ]; then
            # Both symlink and target exist
            break
        fi
    elif [ -f "$HOME/.local/bin/claude" ]; then
        # Regular file exists
        break
    fi
    sleep 1
    waited=$((waited + 1))
done

if [ ! -L "$HOME/.local/bin/claude" ] && [ ! -f "$HOME/.local/bin/claude" ]; then
    echo "ERROR: Claude installer did not create ~/.local/bin/claude after ${max_wait}s"
    exit 1
fi

if [ -L "$HOME/.local/bin/claude" ]; then
    # Follow the symlink and copy the actual binary
    claude_target=$(readlink -f "$HOME/.local/bin/claude")
    if [ -z "$claude_target" ] || [ ! -f "$claude_target" ]; then
        echo "ERROR: Failed to resolve Claude symlink to valid binary"
        exit 1
    fi
    cp "$claude_target" /usr/local/bin/claude
    chmod 755 /usr/local/bin/claude
    echo "Copied Claude Code binary to /usr/local/bin for system-wide access"
elif [ -f "$HOME/.local/bin/claude" ]; then
    # If it's a regular file, just copy it
    cp "$HOME/.local/bin/claude" /usr/local/bin/claude
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
