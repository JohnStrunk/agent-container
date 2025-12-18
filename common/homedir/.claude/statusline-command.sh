#!/bin/bash
# https://code.claude.com/docs/en/statusline
# Claude Code status line: cost | context usage | git status

set -e -o pipefail

# Read JSON input from stdin
input=$(cat)

# Extract context usage and other info
context_size=$(echo "$input" | jq -r '.context_window.context_window_size')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')

cost=$(echo "$input" | jq -r '.cost.total_cost_usd')

# Calculate total current usage by summing all token fields
current_usage=$(echo "$input" | jq '
  .context_window.current_usage |
  (.input_tokens // 0) +
  (.output_tokens // 0) +
  (.cache_creation_input_tokens // 0) +
  (.cache_read_input_tokens // 0)
')

# Calculate context window percentage from current_usage
if [ -n "$current_usage" ] && [ "$current_usage" != "null" ]; then
    ctx_percent=$((current_usage * 100 / context_size))
else
    ctx_percent="N/A"
fi

# Get git status
git_info="git: none"
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" branch --show-current 2>/dev/null || echo "detached")

    # Parse git status -s output and count file states
    # Skip optional locks for safety in concurrent environments
    status_output=$(git -C "$cwd" --no-optional-locks status -s 2>/dev/null || echo "")

    # Count different file states
    count_a=$(echo "$status_output" | grep -c "^A " || true)
    count_m=$(echo "$status_output" | grep -c "^.M" || true)
    count_untracked=$(echo "$status_output" | grep -c "^??" || true)

    # Build status string with non-zero counts
    status_parts=""
    [ "$count_a" -gt 0 ] && status_parts="${status_parts} A:$count_a"
    [ "$count_m" -gt 0 ] && status_parts="${status_parts} M:$count_m"
    [ "$count_untracked" -gt 0 ] && status_parts="${status_parts} ??:$count_untracked"

    if [ -n "$status_parts" ]; then
        git_info="git: $branch -${status_parts}"
    else
        git_info="git: $branch - clean"
    fi
fi

# Output status line
# Ensure leading zero for costs < $1.00
cost_formatted=$(printf "%.2f" "$cost")
printf "cost: \$%s | ctx: %s%% of %s | %s" "$cost_formatted" "$ctx_percent" "$context_size" "$git_info"
