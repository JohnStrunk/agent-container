#! /bin/bash
set -e -o pipefail

# Use different variable names to avoid conflict with readonly bash builtins
TARGET_UID="${EUID:-1000}"
TARGET_GID="${EGID:-1000}"
USERNAME="${USER:-user}"
GROUPNAME="${USERNAME}"

if [[ $# -lt 1 ]]; then
    # Set default command to bash if no arguments are provided
    set -- bash
fi

HOMEDIR="${HOME:-/home/$USERNAME}"
# Ensure parent directories exist
mkdir -p "$(dirname "$HOMEDIR")"
groupadd -g "$TARGET_GID" "$GROUPNAME" || true
useradd -o -u "$TARGET_UID" -g "$TARGET_GID" -d "$HOMEDIR" "$USERNAME"
mkdir -p "$HOMEDIR"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR"

# Manually copy /etc/skel/ contents to home directory
# -n flag prevents overwriting existing files (handles pre-existing mounts)
if [[ -d /etc/skel ]]; then
    gosu "$USERNAME" cp -rn /etc/skel/. "$HOMEDIR/"
fi

# Ensure critical user directories exist and have correct ownership
gosu "$USERNAME" mkdir -p "$HOMEDIR/.cache"
gosu "$USERNAME" mkdir -p "$HOMEDIR/.config"
gosu "$USERNAME" mkdir -p "$HOMEDIR/.local"
# Ensure these critical directories have correct ownership too
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR/.cache"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR/.config"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR/.local"

# Inject GCP credentials if provided
if [[ -n "$GCP_CREDENTIALS_B64" ]]; then
    mkdir -p /etc/google
    echo "$GCP_CREDENTIALS_B64" | base64 -d > /etc/google/application_default_credentials.json
    chmod 600 /etc/google/application_default_credentials.json
    chown "$USERNAME":"$GROUPNAME" /etc/google/application_default_credentials.json
    export GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json
fi

exec gosu "$USERNAME" /entrypoint_user.sh "$@"
