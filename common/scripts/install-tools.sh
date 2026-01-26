#!/bin/bash
# Common tool installation script for both container and VM environments
# This script installs tools that are not available via package managers
# or require custom installation procedures.

set -e -o pipefail

echo "Installing Claude Code using official installer..."
curl -fsSL https://claude.ai/install.sh | bash

# Verify installation succeeded
if ! command -v claude &> /dev/null; then
    echo "ERROR: Claude Code installation failed - claude command not found"
    exit 1
fi

echo "Claude Code installed successfully:"
claude --version
