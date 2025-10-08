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

# Give the user access to the Docker socket if it exists
if [[ -S /var/run/docker.sock ]]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    groupadd -g "$DOCKER_GID" docker || true
    usermod -aG docker "$USERNAME"
fi

# Ensure parent directories of mounted paths have correct permissions
# Process CONTAINER_MOUNT_PATHS if provided by start-work script
if [[ -n "$CONTAINER_MOUNT_PATHS" ]]; then
    IFS=':' read -ra MOUNT_PATHS <<< "$CONTAINER_MOUNT_PATHS"
    for mount_path in "${MOUNT_PATHS[@]}"; do
        if [[ -n "$mount_path" && -e "$mount_path" ]]; then
            # Fix ownership of the entire directory chain up to the mount point
            current_dir="$(dirname "$mount_path")"
            while [[ "$current_dir" != "/" && "$current_dir" != "." ]]; do
                # Create directory if it doesn't exist
                if [[ ! -d "$current_dir" ]]; then
                    gosu "$USERNAME" mkdir -p "$current_dir"
                fi
                # Fix ownership, but skip system directories that should remain root-owned
                if [[ "$current_dir" != "/home" && "$current_dir" != "/opt" && "$current_dir" != "/usr" && "$current_dir" != "/var" ]]; then
                    chown "$USERNAME":"$GROUPNAME" "$current_dir"
                fi
                current_dir="$(dirname "$current_dir")"
            done
        fi
    done
fi

# Ensure critical user directories exist and have correct ownership
gosu "$USERNAME" mkdir -p "$HOMEDIR/.cache"
gosu "$USERNAME" mkdir -p "$HOMEDIR/.config"
gosu "$USERNAME" mkdir -p "$HOMEDIR/.local"
# Ensure these critical directories have correct ownership too
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR/.cache"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR/.config"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR/.local"

# Set up pre-commit cache fallback if the real one wasn't mounted
if [[ -d "/.pre-commit-fallback" ]]; then
    chown "$USERNAME":"$GROUPNAME" "/.pre-commit-fallback"
    # Only create symlink if the real pre-commit cache doesn't exist
    if [[ ! -e "$HOMEDIR/.cache/pre-commit" ]]; then
        gosu "$USERNAME" ln -s /.pre-commit-fallback "$HOMEDIR/.cache/pre-commit"
    fi
fi

exec gosu "$USERNAME" /entrypoint_user.sh "$@"
