#!/bin/bash
set -e -o pipefail

# This entrypoint handles container mode (not VM mode)
# It creates a user matching the host UID/GID for file permission compatibility

# Default values
TARGET_UID="${EUID:-1000}"
TARGET_GID="${EGID:-1000}"
TARGET_USER="${USER:-user}"
TARGET_HOME="${HOME:-/home/$TARGET_USER}"

# Create group if it doesn't exist
if ! getent group "$TARGET_GID" > /dev/null 2>&1; then
    groupadd -g "$TARGET_GID" "$TARGET_USER"
fi

# Create user if it doesn't exist
if ! id "$TARGET_USER" > /dev/null 2>&1; then
    useradd -u "$TARGET_UID" -g "$TARGET_GID" -d "$TARGET_HOME" -s /bin/bash -m "$TARGET_USER"
fi

# Copy skeleton files to user home if not already present
if [ ! -f "$TARGET_HOME/.claude.json" ]; then
    cp -r /etc/skel/. "$TARGET_HOME/"
    chown -R "$TARGET_UID:$TARGET_GID" "$TARGET_HOME"
fi

# Handle GCP credentials injection (base64 encoded)
if [ -n "$GCP_CREDENTIALS_B64" ]; then
    mkdir -p "$TARGET_HOME/.config/gcloud"
    echo "$GCP_CREDENTIALS_B64" | base64 -d > "$TARGET_HOME/.config/gcloud/application_default_credentials.json"
    chown -R "$TARGET_UID:$TARGET_GID" "$TARGET_HOME/.config"
    chmod 600 "$TARGET_HOME/.config/gcloud/application_default_credentials.json"
fi

# Switch to user and execute command
if [ $# -eq 0 ]; then
    exec gosu "$TARGET_USER" /bin/bash
else
    exec gosu "$TARGET_USER" "$@"
fi
