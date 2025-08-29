#! /bin/bash
set -e -o pipefail

EUID="${EUID:-1000}"
EGID="${EGID:-1000}"
USERNAME="user"
GROUPNAME="user"

if [[ $# -lt 1 ]]; then
    # Set default command to bash if no arguments are provided
    set -- bash
fi

HOMEDIR="/home/$USERNAME"
groupadd -g "$EGID" "$GROUPNAME" || true
useradd -o -u "$EUID" -g "$EGID" -m "$USERNAME"

# Give the user access to the Docker socket if it exists
if [[ -S /var/run/docker.sock ]]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    groupadd -g "$DOCKER_GID" docker || true
    usermod -aG docker "$USERNAME"
fi
chown "$USERNAME":"$GROUPNAME" "/.pre-commit"

gosu "$USERNAME" mkdir -p "$HOMEDIR/.config"
gosu "$USERNAME" mkdir -p "$HOMEDIR/.cache"

ln -s /.gemini "$HOMEDIR/.gemini"
ln -s /.claude "$HOMEDIR/.claude"
ln -s /.claude.json "$HOMEDIR/.claude.json"
ln -s /.gcloud "$HOMEDIR/.config/gcloud"
ln -s /.pre-commit "$HOMEDIR/.cache/pre-commit"

exec gosu "$USERNAME" /entrypoint_user.sh "$@"
