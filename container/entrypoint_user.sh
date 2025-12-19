#! /bin/bash
set -e -o pipefail

# Add ~/.local/bin to PATH for any user-installed tools
# shellcheck disable=SC2016
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

pre-commit gc > /dev/null 2>&1 || true
(pre-commit install-hooks > /dev/null 2>&1 || true) &

exec "$@"
