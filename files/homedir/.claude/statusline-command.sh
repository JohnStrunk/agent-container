#!/bin/bash
# Claude Code status line: cost | context usage | git status

set -e -o pipefail

# Read JSON input from stdin
input=$(cat)

# Extract token counts and context window size
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens')
context_size=$(echo "$input" | jq -r '.context_window.context_window_size')
cwd=$(echo "$input" | jq -r '.workspace.current_dir')

# Calculate cost (Claude 3.5 Sonnet pricing: $3/M input, $15/M output)
cost=$(echo "scale=2; ($total_input * 3 + $total_output * 15) / 1000000" | bc)

# Calculate context window percentage
total_tokens=$((total_input + total_output))
ctx_percent=$(echo "scale=0; $total_tokens * 100 / $context_size" | bc)

# Get git status
git_info="git - none"
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
        git_info="git - $branch -${status_parts}"
    else
        git_info="git - $branch - clean"
    fi
fi

# Output status line
# Ensure leading zero for costs < $1.00
cost_formatted=$(printf "%.2f" "$cost")
printf "cost: \$%s | ctx: %s%% of %s | %s" "$cost_formatted" "$ctx_percent" "$context_size" "$git_info"
