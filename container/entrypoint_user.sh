#! /bin/bash
set -e -o pipefail

# Add ~/.local/bin to PATH for any user-installed tools
# shellcheck disable=SC2016
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc

# Expand ~ to $HOME in environment variables (e.g. KUBECONFIG=~/.kube/config)
for var in $(compgen -e); do
    val="${!var}"
    if [[ "$val" == "~"* ]]; then
        export "$var"="$HOME${val#\~}"
    fi
done

pre-commit gc > /dev/null 2>&1 || true
(pre-commit install-hooks > /dev/null 2>&1 || true) &

# Install Claude plugins from spec file
PLUGINS_SPEC="/etc/claude-plugins.txt"
if [[ -f "$PLUGINS_SPEC" ]]; then
    echo "Installing Claude plugins..."
    while IFS= read -r line || [[ -n "$line" ]]; do
        # Skip comments and blank lines
        [[ -z "$line" || "$line" =~ ^# ]] && continue

        if [[ "$line" =~ ^marketplace[[:space:]]+(.*) ]]; then
            echo "  Adding marketplace: ${BASH_REMATCH[1]}"
            claude plugin marketplace add "${BASH_REMATCH[1]}" || true
        else
            echo "  Installing plugin: $line"
            claude plugin install "$line" || true
        fi
    done < "$PLUGINS_SPEC"
fi

exec "$@"
