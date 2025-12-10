#! /bin/bash
set -e -o pipefail

EUID="${EUID:-1000}"
EGID="${EGID:-1000}"
USERNAME="${USER:-user}"
GROUPNAME="${USERNAME}"

if [[ $# -lt 1 ]]; then
    # Set default command to bash if no arguments are provided
    set -- bash
fi

HOMEDIR="${HOME:-/home/$USERNAME}"
# Ensure parent directories exist
mkdir -p "$(dirname "$HOMEDIR")"
groupadd -g "$EGID" "$GROUPNAME" || true
useradd -o -u "$EUID" -g "$EGID" -m -d "$HOMEDIR" "$USERNAME"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR"

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
