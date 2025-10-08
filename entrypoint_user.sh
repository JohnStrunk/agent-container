#! /bin/bash
set -e -o pipefail

# Install python tools now that we have the right user
# shellcheck disable=SC2016
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
echo -n "Installing Python tools:"
for tool in $(echo "$PYTHON_TOOLS" | tr ',' ' '); do
    echo -n " $tool"
    uv tool install -q "$tool"
done
echo " ...done"

pre-commit gc > /dev/null 2>&1 || true
(pre-commit install-hooks > /dev/null 2>&1 || true) &

exec "$@"
