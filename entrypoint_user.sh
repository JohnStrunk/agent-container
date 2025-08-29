#! /bin/bash
set -e -o pipefail

# Install python tools now that we have the right user
# shellcheck disable=SC2016
echo 'export PATH="/home/user/.local/bin:$PATH"' >> ~/.bashrc
for tool in $(echo "$PYTHON_TOOLS" | tr ',' ' '); do
    uv tool install -q "$tool"
done

pre-commit gc > /dev/null 2>&1 || true
(pre-commit install-hooks > /dev/null 2>&1 || true) &

exec "$@"
