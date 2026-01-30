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
CURRENT_UID="$(id -u)"
CURRENT_GID="$(id -g)"

# Check if we're running as root (Docker) or as target user (Podman with --userns=keep-id)
if [[ "$CURRENT_UID" == "0" ]]; then
    # Running as root (Docker) - need to create user and use gosu
    echo "Running as root - creating user $USERNAME (UID=$TARGET_UID, GID=$TARGET_GID)"

    # Ensure parent directories exist
    mkdir -p "$(dirname "$HOMEDIR")"

    # Create group and user if they don't exist
    if ! getent group "$TARGET_GID" >/dev/null; then
        groupadd -g "$TARGET_GID" "$GROUPNAME"
    fi

    if ! id -u "$USERNAME" >/dev/null 2>&1; then
        useradd -o -u "$TARGET_UID" -g "$TARGET_GID" -d "$HOMEDIR" "$USERNAME"
    fi

    # Ensure home directory exists and has correct ownership
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

    # Execute as target user using gosu
    exec gosu "$USERNAME" /entrypoint_user.sh "$@"
else
    # Running as non-root (Podman with --userns=keep-id) - already target user
    echo "Running as user $USERNAME (UID=$CURRENT_UID, GID=$CURRENT_GID)"

    # When running as non-root, HOME may not be writable (especially with Podman userns)
    # Test if we can write to a file in the parent directory of HOME
    HOMEDIR_PARENT="$(dirname "$HOMEDIR")"
    if [[ ! -d "$HOMEDIR_PARENT" ]] || [[ ! -w "$HOMEDIR_PARENT" ]]; then
        echo "Cannot write to $HOMEDIR_PARENT, using /tmp/home-$USERNAME as HOME"
        HOMEDIR="/tmp/home-$USERNAME"
        export HOME="$HOMEDIR"
    fi

    # Create home directory
    mkdir -p "$HOMEDIR"

    # Copy /etc/skel/ contents to home directory
    # -n flag prevents overwriting existing files
    if [[ -d /etc/skel ]]; then
        cp -rn /etc/skel/. "$HOMEDIR/" 2>/dev/null || true
    fi

    # Ensure critical user directories exist
    mkdir -p "$HOMEDIR/.cache"
    mkdir -p "$HOMEDIR/.config"
    mkdir -p "$HOMEDIR/.local"

    # Inject GCP credentials if provided
    # When running as non-root, use user's config directory instead of /etc
    if [[ -n "$GCP_CREDENTIALS_B64" ]]; then
        CREDS_DIR="$HOMEDIR/.config/gcloud"
        CREDS_FILE="$CREDS_DIR/application_default_credentials.json"

        mkdir -p "$CREDS_DIR"
        echo "$GCP_CREDENTIALS_B64" | base64 -d > "$CREDS_FILE"
        chmod 600 "$CREDS_FILE"
        export GOOGLE_APPLICATION_CREDENTIALS="$CREDS_FILE"
    fi

    # Execute directly (already running as target user)
    exec /entrypoint_user.sh "$@"
fi
