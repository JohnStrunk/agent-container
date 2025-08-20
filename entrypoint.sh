#! /bin/bash
set -e -o pipefail

if [[ -z "$EUID" || -z "$EGID" ]]; then
    exec "$@"
fi

USERNAME="user"

if [[ $# -lt 1 ]]; then
    # Set default command to bash if no arguments are provided
    set -- bash
fi

groupadd -g "$EGID" "$USERNAME" || true
useradd -u "$EUID" -g "$EGID" -m "$USERNAME"

# Give the user access to the Docker socket if it exists
if [[ -S /var/run/docker.sock ]]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    groupadd -g "$DOCKER_GID" docker || true
    usermod -aG docker "$USERNAME"
fi
chown "$USERNAME":"$USERNAME" "/.pre-commit"

gosu "$USERNAME" mkdir -p "/home/$USERNAME/.config"
gosu "$USERNAME" mkdir -p "/home/$USERNAME/.cache"

ln -s /.gemini "/home/$USERNAME/.gemini"
ln -s /.claude "/home/$USERNAME/.claude"
ln -s /.claude.json "/home/$USERNAME/.claude.json"
ln -s /.gcloud "/home/$USERNAME/.config/gcloud"
ln -s /.pre-commit "/home/$USERNAME/.cache/pre-commit"
gosu "$USERNAME" pre-commit gc > /dev/null 2>&1 || true
(gosu "$USERNAME" pre-commit install-hooks > /dev/null 2>&1 || true) &

exec gosu "$USERNAME" "$@"
