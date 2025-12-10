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

exec gosu "$USERNAME" /entrypoint_user.sh "$@"
