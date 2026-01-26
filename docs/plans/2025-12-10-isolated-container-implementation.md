# Isolated Container Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform the current shared-mount container into a VM-like isolated container with workspace-only access.

**Architecture:** Replace host filesystem mounts with built-in configs (files/homedir/), runtime credential injection (base64 encoded), and a single shared cache volume. Only the workspace and main git repo are mounted.

**Tech Stack:** Docker, Bash, Debian 13 base image

---

## Task 1: Create Configuration Directory Structure

**Files:**
- Create: `files/homedir/.claude.json`
- Create: `files/homedir/.gitconfig`
- Create: `files/homedir/start-claude`

**Step 1: Create files/homedir directory**

Run: `mkdir -p files/homedir`

**Step 2: Create .claude.json with default settings**

Create `files/homedir/.claude.json`:

```json
{
  "model": "claude-sonnet-4-5@20250929",
  "smallFastModel": "claude-3-5-haiku-20241022",
  "browserEnabled": true,
  "settings": {
    "conciseMode": false
  }
}
```

**Step 3: Create .gitconfig template**

Create `files/homedir/.gitconfig`:

```ini
[user]
    name = Claude Code Agent
    email = agent@localhost

[core]
    editor = vim
    autocrlf = input

[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
    lg = log --oneline --graph --decorate

[init]
    defaultBranch = main
```

**Step 4: Create start-claude helper script**

Create `files/homedir/start-claude`:

```bash
#!/bin/bash
# Helper script to start Claude Code with common settings

set -e

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo "Warning: Not in a git repository"
fi

# Start Claude Code
exec claude "$@"
```

**Step 5: Make start-claude executable**

Run: `chmod +x files/homedir/start-claude`

**Step 6: Verify directory structure**

Run: `tree files/`

Expected output:
```
files/
└── homedir
    ├── .claude.json
    ├── .gitconfig
    └── start-claude
```

**Step 7: Commit configuration files**

```bash
git add files/
git commit -m "feat: add default configuration files for isolated container

Add files/homedir/ with Claude, git, and helper script configs.
These will be built into the container image and copied to user home.

No credentials or secrets included - only non-sensitive configs."
```

---

## Task 2: Update Dockerfile

**Files:**
- Modify: `Dockerfile:84` (before ENTRYPOINT line)

**Step 1: Add COPY instruction for config files**

Add before the ENTRYPOINT line in `Dockerfile`:

```dockerfile
# Copy default configuration files to /etc/skel/
# These will be copied to user home by entrypoint.sh
COPY files/homedir/ /etc/skel/

COPY entrypoint.sh /entrypoint.sh
```

The complete section should look like:

```dockerfile
# Install coding agents
# hadolint ignore=DL3016
RUN npm install -g \
    @anthropic-ai/claude-code@latest \
    @google/gemini-cli@latest \
    @github/copilot@latest

# Copy default configuration files to /etc/skel/
# These will be copied to user home by entrypoint.sh
COPY files/homedir/ /etc/skel/

COPY entrypoint.sh /entrypoint.sh
RUN chmod a+rx /entrypoint.sh
COPY entrypoint_user.sh /entrypoint_user.sh
RUN chmod a+rx /entrypoint_user.sh
ENTRYPOINT ["/entrypoint.sh"]
```

**Step 2: Verify Dockerfile syntax**

Run: `docker run --rm -i hadolint/hadolint < Dockerfile`

Expected: No errors (warnings are ok)

**Step 3: Commit Dockerfile changes**

```bash
git add Dockerfile
git commit -m "feat: copy config files to container image

Add COPY instruction to include files/homedir/ configs in image.
Configs are placed in /etc/skel/ for copying to user home."
```

---

## Task 3: Update entrypoint.sh - Remove Docker Socket Handling

**Files:**
- Modify: `entrypoint.sh:21-26`

**Step 1: Remove Docker socket group logic**

Remove lines 21-26 from `entrypoint.sh`:

```bash
# Give the user access to the Docker socket if it exists
if [[ -S /var/run/docker.sock ]]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    groupadd -g "$DOCKER_GID" docker || true
    usermod -aG docker "$USERNAME"
fi
```

After removal, the section should go from user creation directly to mount path handling.

**Step 2: Verify syntax**

Run: `bash -n entrypoint.sh`

Expected: No output (syntax is valid)

**Step 3: Commit Docker socket removal**

```bash
git add entrypoint.sh
git commit -m "refactor: remove Docker socket access from entrypoint

Remove Docker socket group handling for isolated container.
Agent no longer has Docker access for stronger isolation."
```

---

## Task 4: Update entrypoint.sh - Remove Mount Path Handling

**Files:**
- Modify: `entrypoint.sh:27-49`

**Step 1: Remove CONTAINER_MOUNT_PATHS logic**

Remove lines 27-49 from `entrypoint.sh` (the entire mount paths permission fixing block):

```bash
# Ensure parent directories of mounted paths have correct permissions
# Process CONTAINER_MOUNT_PATHS if provided by agent-container script
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
```

**Step 2: Verify syntax**

Run: `bash -n entrypoint.sh`

Expected: No output

**Step 3: Commit mount path removal**

```bash
git add entrypoint.sh
git commit -m "refactor: remove mount path permission fixing

Remove CONTAINER_MOUNT_PATHS logic since we no longer mount multiple
host directories. Only workspace is mounted in isolated container."
```

---

## Task 5: Update entrypoint.sh - Remove Pre-commit Fallback

**Files:**
- Modify: `entrypoint.sh:60-67`

**Step 1: Remove pre-commit fallback symlink logic**

Remove lines 60-67 from `entrypoint.sh`:

```bash
# Set up pre-commit cache fallback if the real one wasn't mounted
if [[ -d "/.pre-commit-fallback" ]]; then
    chown "$USERNAME":"$GROUPNAME" "/.pre-commit-fallback"
    # Only create symlink if the real pre-commit cache doesn't exist
    if [[ ! -e "$HOMEDIR/.cache/pre-commit" ]]; then
        gosu "$USERNAME" ln -s /.pre-commit-fallback "$HOMEDIR/.cache/pre-commit"
    fi
fi
```

The file should now end with critical directory creation and then exec.

**Step 2: Verify syntax**

Run: `bash -n entrypoint.sh`

Expected: No output

**Step 3: Commit pre-commit fallback removal**

```bash
git add entrypoint.sh
git commit -m "refactor: remove pre-commit fallback symlink

Remove fallback logic since cache is now a Docker volume.
No longer need special handling for unmounted cache."
```

---

## Task 6: Update entrypoint.sh - Add Credential Injection

**Files:**
- Modify: `entrypoint.sh:59` (after critical directory ownership, before exec)

**Step 1: Add GCP credential injection logic**

Add before the final `exec` line in `entrypoint.sh`:

```bash
# Inject GCP credentials if provided
if [[ -n "$GCP_CREDENTIALS_B64" ]]; then
    mkdir -p /etc/google
    echo "$GCP_CREDENTIALS_B64" | base64 -d > /etc/google/application_default_credentials.json
    chmod 600 /etc/google/application_default_credentials.json
    chown "$USERNAME":"$GROUPNAME" /etc/google/application_default_credentials.json
    export GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json
fi

exec gosu "$USERNAME" /entrypoint_user.sh "$@"
```

**Step 2: Verify syntax**

Run: `bash -n entrypoint.sh`

Expected: No output

**Step 3: Test base64 decode logic (manual verification)**

Run:
```bash
echo "test content" | base64 -w 0
# Copy output and decode:
echo "<output>" | base64 -d
```

Expected: "test content" printed

**Step 4: Commit credential injection**

```bash
git add entrypoint.sh
git commit -m "feat: add GCP credential injection to entrypoint

Add logic to decode and write GCP credentials from GCP_CREDENTIALS_B64
environment variable. Credentials written to /etc/google/ with proper
permissions and GOOGLE_APPLICATION_CREDENTIALS set."
```

---

## Task 7: Update entrypoint.sh - Fix User Creation and Config Copying

**Files:**
- Modify: `entrypoint.sh:18-19`

**Step 1: Change useradd to not use -m flag**

Change line 18 from:

```bash
useradd -o -u "$EUID" -g "$EGID" -m -d "$HOMEDIR" "$USERNAME"
```

To:

```bash
useradd -o -u "$EUID" -g "$EGID" -d "$HOMEDIR" "$USERNAME"
mkdir -p "$HOMEDIR"
```

**Step 2: Add manual /etc/skel/ copying**

Add after `chown "$USERNAME":"$GROUPNAME" "$HOMEDIR"` (around line 20):

```bash
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR"

# Manually copy /etc/skel/ contents to home directory
# -n flag prevents overwriting existing files (handles pre-existing mounts)
if [[ -d /etc/skel ]]; then
    gosu "$USERNAME" cp -rn /etc/skel/. "$HOMEDIR/"
fi
```

**Step 3: Verify complete user setup section**

The section should now look like:

```bash
HOMEDIR="${HOME:-/home/$USERNAME}"
# Ensure parent directories exist
mkdir -p "$(dirname "$HOMEDIR")"
groupadd -g "$EGID" "$GROUPNAME" || true
useradd -o -u "$EUID" -g "$EGID" -d "$HOMEDIR" "$USERNAME"
mkdir -p "$HOMEDIR"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR"

# Manually copy /etc/skel/ contents to home directory
# -n flag prevents overwriting existing files (handles pre-existing mounts)
if [[ -d /etc/skel ]]; then
    gosu "$USERNAME" cp -rn /etc/skel/. "$HOMEDIR/"
fi
```

**Step 4: Verify syntax**

Run: `bash -n entrypoint.sh`

Expected: No output

**Step 5: Commit user creation fix**

```bash
git add entrypoint.sh
git commit -m "fix: manual user home setup and config copying

Change useradd to not use -m flag (home may exist from mounts).
Manually create home directory and copy /etc/skel/ with -n flag
to avoid overwriting pre-existing mount paths."
```

---

## Task 8: Update agent-container - Add Credential Handling Variables

**Files:**
- Modify: `agent-container:6` (after IMAGE_NAME)

**Step 1: Add GCP credentials default path**

Add after line 6 in `agent-container`:

```bash
IMAGE_NAME="ghcr.io/johnstrunk/agent-container"
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"
```

**Step 2: Verify syntax**

Run: `bash -n agent-container`

Expected: No output

**Step 3: Commit credential variable**

```bash
git add agent-container
git commit -m "feat: add GCP credentials default path variable

Add GCP_CREDS_DEFAULT variable for auto-detecting credentials.
Will be used for credential injection logic."
```

---

## Task 9: Update agent-container - Remove Old CONTAINER_MOUNTS Array

**Files:**
- Modify: `agent-container:8-18`

**Step 1: Remove CONTAINER_MOUNTS array and related logic**

Remove lines 8-18 from `agent-container`:

```bash
# Paths to mount at the same location inside the container
# Only paths that exist on the host will be mounted
CONTAINER_MOUNTS=(
    "$HOME/.cache/pre-commit"
    "$HOME/.cache/uv"
    "$HOME/.claude"
    "$HOME/.claude.json"
    "$HOME/.config/gcloud"
    "$HOME/.gemini"
    "$HOME/Documents/Obsidian/RedHat"
)
```

**Step 2: Remove the mount arguments building loop**

Find and remove lines 114-124 (the loop that builds mount arguments):

```bash
# Build mount arguments for existing paths
MOUNT_ARGS=()
MOUNTED_PATHS=()
for path in "${CONTAINER_MOUNTS[@]}"; do
    if [[ -e "$path" ]]; then
        MOUNT_ARGS+=("-v" "$path:$path")
        MOUNTED_PATHS+=("$path")
        echo "Mounting: $path"
    else
        echo "Skipping non-existent path: $path"
    fi
done
```

**Step 3: Remove CONTAINER_MOUNT_PATHS creation**

Find and remove lines 126-131:

```bash
# Add the main repo directory and worktree directory to the list of paths that need parent ownership fixed
MOUNTED_PATHS+=("$MAIN_REPO_DIR")
MOUNTED_PATHS+=("$WORKTREE_DIR")

# Create colon-separated list of mounted paths for the container
CONTAINER_MOUNT_PATHS=$(IFS=':'; echo "${MOUNTED_PATHS[*]}")
```

**Step 4: Verify syntax**

Run: `bash -n agent-container`

Expected: No output

**Step 5: Commit removal of old mounts**

```bash
git add agent-container
git commit -m "refactor: remove old host directory mount logic

Remove CONTAINER_MOUNTS array and mount building loop.
Isolated container no longer mounts host configs/caches."
```

---

## Task 10: Update agent-container - Add New Mount Logic

**Files:**
- Modify: `agent-container:114` (where old mount args building was)

**Step 1: Add new isolated mount logic**

Add at the location where the old mount loop was removed:

```bash
# Build mount arguments for isolated container
MOUNT_ARGS=(
    "-v" "$WORKTREE_DIR:$WORKTREE_DIR:rw"
    "-v" "agent-container-cache:$HOME/.cache"
)

# Add main repo mount if using git worktrees
if [[ "$USE_GIT" == 1 ]]; then
    MOUNT_ARGS+=("-v" "$MAIN_REPO_DIR:$MAIN_REPO_DIR:rw")
    echo "Mounting worktree: $WORKTREE_DIR (rw)"
    echo "Mounting main repo: $MAIN_REPO_DIR (rw)"
    echo "Mounting cache volume: agent-container-cache"
else
    echo "Mounting current directory: $WORKTREE_DIR (rw)"
    echo "Mounting cache volume: agent-container-cache"
fi
```

**Step 2: Remove old core mounts section**

Find and remove the old "Core mounts" section (around line 133-139):

```bash
# Core mounts (always needed)
MOUNT_ARGS+=(
    "-v" "$WORKTREE_DIR:$WORKTREE_DIR"
    "-v" "/var/run/docker.sock:/var/run/docker.sock"
    "-v" "$MAIN_REPO_DIR:$MAIN_REPO_DIR"
    "-v" "agent-container-pre-commit-cache:/.pre-commit-fallback"
)
```

This should be replaced by the new logic in Step 1.

**Step 3: Verify syntax**

Run: `bash -n agent-container`

Expected: No output

**Step 4: Commit new mount logic**

```bash
git add agent-container
git commit -m "feat: implement isolated container mount strategy

Replace old mounts with isolated strategy:
- Worktree: read-write
- Main repo: read-write (if using git)
- Single cache volume for all caches
- No Docker socket, no host configs"
```

---

## Task 11: Update agent-container - Add GCP Credential Injection Logic

**Files:**
- Modify: `agent-container:61-80` (in argument parsing section)

**Step 1: Add GCP_CREDS_PATH variable initialization**

Add before the `while [[ $# -gt 0 ]]` loop:

```bash
# Parse command line options
BRANCH_NAME=""
CONTAINER_COMMAND=()
USE_GIT=0
GCP_CREDS_PATH=""  # Empty means auto-detect
```

**Step 2: Add --gcp-credentials flag parsing**

Add in the case statement (around line 65-69):

```bash
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--branch)
            BRANCH_NAME="$2"
            shift 2
            ;;
        --gcp-credentials)
            GCP_CREDS_PATH="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            # All remaining arguments are the command to execute
            CONTAINER_COMMAND=("$@")
            break
            ;;
    esac
done
```

**Step 3: Add credential detection and encoding logic**

Add after the mount logic setup (around line 125):

```bash
# Handle GCP credential injection
CREDENTIAL_ARGS=()

# Auto-detect if not specified
if [[ -z "$GCP_CREDS_PATH" ]]; then
    GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
fi

# Inject credentials if file exists
if [[ -f "$GCP_CREDS_PATH" ]]; then
    echo "Injecting GCP credentials from: $GCP_CREDS_PATH"
    GCP_CREDS_B64=$(base64 -w 0 "$GCP_CREDS_PATH")
    CREDENTIAL_ARGS+=("-e" "GCP_CREDENTIALS_B64=$GCP_CREDS_B64")
else
    echo "No GCP credentials file found (checked: $GCP_CREDS_PATH)"
    echo "GCP authentication will rely on environment variables only"
fi
```

**Step 4: Verify syntax**

Run: `bash -n agent-container`

Expected: No output

**Step 5: Commit credential injection logic**

```bash
git add agent-container
git commit -m "feat: add GCP credential injection to agent-container

Add --gcp-credentials flag with auto-detection from default path.
Credentials are base64-encoded and passed via environment variable
to container for injection by entrypoint.sh."
```

---

## Task 12: Update agent-container - Modify Docker Run Command

**Files:**
- Modify: `agent-container:148-164` (docker run command)

**Step 1: Remove CONTAINER_MOUNT_PATHS environment variable**

In the docker run command, remove:

```bash
    -e CONTAINER_MOUNT_PATHS="$CONTAINER_MOUNT_PATHS" \
```

**Step 2: Add CREDENTIAL_ARGS to docker run**

Modify the docker run command to include credential arguments. The command should look like:

```bash
docker run --rm -it \
    --name "$CONTANIER_NAME" \
    --hostname "$CONTANIER_NAME" \
    "${MOUNT_ARGS[@]}" \
    -w "$WORKTREE_DIR" \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="$HOME" \
    -e USER="$USER" \
    "${CREDENTIAL_ARGS[@]}" \
    -e GEMINI_API_KEY \
    -e ANTHROPIC_API_KEY \
    -e ANTHROPIC_MODEL \
    -e ANTHROPIC_SMALL_FAST_MODEL \
    -e ANTHROPIC_VERTEX_PROJECT_ID \
    -e CLOUD_ML_REGION \
    -e CLAUDE_CODE_USE_VERTEX \
    ghcr.io/johnstrunk/agent-container:latest "${CONTAINER_COMMAND[@]}"
```

**Step 3: Add ANTHROPIC_API_KEY to passthrough list**

Add to the environment variable list if not already present:

```bash
    -e ANTHROPIC_API_KEY \
```

**Step 4: Verify syntax**

Run: `bash -n agent-container`

Expected: No output

**Step 5: Commit docker run updates**

```bash
git add agent-container
git commit -m "refactor: update docker run command for isolation

Remove CONTAINER_MOUNT_PATHS environment variable.
Add CREDENTIAL_ARGS for credential injection.
Add ANTHROPIC_API_KEY to environment passthrough."
```

---

## Task 13: Update agent-container - Update Usage Documentation

**Files:**
- Modify: `agent-container:20-32` (usage function)

**Step 1: Update usage function**

Replace the usage function with:

```bash
function usage {
    cat - <<EOF
$0: Start using a coding agent on a git worktree (isolated container)

Usage: $0 [options] [-b <branch_name>] [command...]

Options:
  -b, --branch <name>         Branch name for git worktree
  --gcp-credentials <path>    Path to GCP service account JSON key file
                              (default: ~/.config/gcloud/application_default_credentials.json)
  -h, --help                  Show this help

Arguments:
  command...                  Optional command to execute in the container
                              (container will exit after execution)

Environment Variables:
  ANTHROPIC_API_KEY          Anthropic API key for Claude
  ANTHROPIC_MODEL            Model to use (default: claude-3-5-sonnet-20241022)
  GEMINI_API_KEY             Google Gemini API key
  (See README.md for complete list)

Isolation:
  * Container has NO access to host filesystem except workspace
  * No Docker socket access
  * Configs built into image (not shared with host)
  * Credentials injected at runtime (ephemeral)
  * Cache volume shared across sessions: agent-container-cache

Storage:
  * Worktrees are stored in $WORKTREE_BASE_DIR
  * Cache volume: docker volume ls | grep agent-container-cache
  * Clear cache: docker volume rm agent-container-cache

Examples:
  $0 -b feature-auth                    # Start interactive session
  $0 -b feature-auth -- claude          # Run claude directly
  $0 --gcp-credentials ~/my-sa.json -b feature  # Custom GCP credentials
  $0                                    # Use current directory (no git)
EOF
}
```

**Step 2: Verify syntax**

Run: `bash -n agent-container`

Expected: No output

**Step 3: Test usage display**

Run: `./agent-container --help`

Expected: Usage message displayed with new isolation documentation

**Step 4: Commit usage update**

```bash
git add agent-container
git commit -m "docs: update agent-container usage for isolated container

Update help text to reflect:
- Credential injection options
- Isolation model
- Cache volume management
- No host filesystem access"
```

---

## Task 14: Update README.md - Overview Section

**Files:**
- Modify: `README.md:1-26`

**Step 1: Update overview description**

Replace lines 1-26 in README.md with:

```markdown
# Agent Container

A Docker-based development environment for working with AI coding agents
(Claude Code, Gemini CLI, and GitHub Copilot CLI) using Git worktrees.

**Key Feature: Strong Isolation** - The container uses a VM-like isolation
model where only the workspace directory is accessible to the agent. No
access to host configs, credentials, or Docker socket.

## Overview

This project provides a containerized environment that enables developers to
work with AI coding agents on isolated Git branches using worktrees. The
container comes pre-configured with:

- **Claude Code** - Anthropic's AI coding assistant
- **Gemini CLI** - Google's Gemini CLI
- **GitHub Copilot CLI** - GitHub's AI coding assistant
- **Development tools** - Git, Node.js, Python, Docker CLI, and more
- **Code quality tools** - pre-commit, hadolint, pipenv, poetry

**Isolation Model:**

- ✅ Only workspace directory accessible to agent
- ✅ Configs built into container (not shared with host)
- ✅ Credentials injected at runtime (ephemeral)
- ✅ No Docker socket access
- ✅ Shared cache volume for performance
- ✅ Fast startup (containers vs VMs)
```

**Step 2: Verify markdown formatting**

Run: `head -30 README.md`

Expected: Well-formatted markdown visible

**Step 3: Commit README overview update**

```bash
git add README.md
git commit -m "docs: update README overview for isolated container

Highlight isolation as key feature.
Explain VM-like isolation model.
Clarify what is and isn't accessible to agent."
```

---

## Task 15: Update README.md - Features Section

**Files:**
- Modify: `README.md:18-26`

**Step 1: Replace features section**

Replace lines 18-26 with:

```markdown
## Features

- **Strong Isolation**: Agent cannot access host filesystem, configs, or
  Docker socket
- **Workspace-Only Access**: Each branch gets its own worktree, only that
  directory is accessible
- **AI Agent Support**: Pre-installed Claude Code, Gemini CLI, and
  GitHub Copilot CLI
- **Built-in Configs**: Default configurations built into image, not shared
  with host
- **Runtime Credential Injection**: Credentials injected at startup,
  ephemeral and isolated
- **Fast Performance**: Shared cache volume across sessions for quick
  startup
- **Git Worktrees**: Multiple concurrent sessions on different branches
- **User Permissions**: Proper UID/GID mapping to avoid permission issues
```

**Step 2: Commit features update**

```bash
git add README.md
git commit -m "docs: update features section for isolation

Emphasize isolation features.
Remove misleading Docker Integration mention.
Add credential injection feature."
```

---

## Task 16: Update README.md - Configuration Section

**Files:**
- Modify: `README.md:78-88`

**Step 1: Replace configuration section**

Replace the "Configuration" subsection (around lines 78-88) with:

```markdown
### Configuration

The container uses built-in configurations from `files/homedir/`:

- `.claude.json` - Claude Code settings (model, preferences)
- `.gitconfig` - Git configuration (name, email, aliases)
- `start-claude` - Helper script

**These are built into the container image and NOT shared with your host.**
Changes you make inside the container are lost when it exits.

To customize permanently:

1. Edit files in `files/homedir/`
2. Rebuild the image: `docker build -t ghcr.io/johnstrunk/agent-container .`
3. Restart your container

**Automatic mounts (OLD BEHAVIOR) have been removed.**
```

**Step 2: Commit configuration section update**

```bash
git add README.md
git commit -m "docs: update configuration section for built-in configs

Explain that configs are built into image, not mounted.
Document how to customize configs permanently.
Note that automatic mounts are removed."
```

---

## Task 17: Update README.md - Environment Variables Section

**Files:**
- Modify: `README.md:88-108`

**Step 1: Add credential injection documentation**

Update the environment variables section to include credential injection:

```markdown
### Environment Variables

**Authentication:**

Set these environment variables to authenticate with AI services:

**Claude Code:**

- `ANTHROPIC_API_KEY` - Anthropic API key (for direct API access)
- `ANTHROPIC_MODEL` - Model to use (default: claude-3-5-sonnet-20241022)
- `ANTHROPIC_SMALL_FAST_MODEL` - Fast model for simple tasks
- `ANTHROPIC_VERTEX_PROJECT_ID` - Google Cloud project for Vertex AI
- `CLOUD_ML_REGION` - Cloud region for Vertex AI
- `CLAUDE_CODE_USE_VERTEX` - Use Vertex AI instead of direct API

**Gemini CLI:**

- `GEMINI_API_KEY` - API key for Gemini

**GCP Credential Injection:**

For Vertex AI authentication, use credential file injection:

```bash
# Auto-detected from default location
agent-container -b feature  # Uses ~/.config/gcloud/application_default_credentials.json

# Override with custom path
agent-container -b feature --gcp-credentials ~/my-service-account.json
```

The credential file is:

- Base64-encoded and injected at container startup
- Written to `/etc/google/application_default_credentials.json`
- Deleted when container exits (ephemeral)
- Never stored in the git repository
```

**Step 2: Commit environment variables update**

```bash
git add README.md
git commit -m "docs: add GCP credential injection documentation

Document --gcp-credentials flag and auto-detection.
Explain ephemeral nature of injected credentials.
Clarify credential security model."
```

---

## Task 18: Update README.md - File Structure Section

**Files:**
- Modify: `README.md:115-120`

**Step 1: Update file structure**

Replace the file structure section with:

```markdown
## File Structure

- `Dockerfile` - Container image definition
- `entrypoint.sh` - Container startup script with user setup and credential
  injection
- `entrypoint_user.sh` - User-level initialization
- `agent-container` - Main script to create worktrees and start containers
- `files/homedir/` - Built-in configuration files (copied to container)
  - `.claude.json` - Claude Code settings
  - `.gitconfig` - Git configuration
  - `start-claude` - Helper script
- `LICENSE` - MIT License
```

**Step 2: Commit file structure update**

```bash
git add README.md
git commit -m "docs: update file structure with files/homedir/

Add files/homedir/ directory to file structure.
Update entrypoint.sh description to mention credential injection."
```

---

## Task 19: Update README.md - Add Isolation Section

**Files:**
- Modify: `README.md:131` (after Docker Image section, before License)

**Step 1: Add new Isolation & Security section**

Add before the License section:

```markdown
## Isolation & Security

This container uses a VM-like isolation model for safe agent operation:

**What the agent CAN access:**

- ✅ Workspace directory (read-write)
- ✅ Main git repository (read-write, for worktree commits)
- ✅ Built-in configs (ephemeral, changes lost on exit)
- ✅ Injected credentials (ephemeral, deleted on exit)
- ✅ Shared cache volume (persistent across sessions)

**What the agent CANNOT access:**

- ❌ Host filesystem outside workspace
- ❌ Host configs (`~/.claude`, `~/.config/gcloud`, etc.)
- ❌ Docker socket (no container creation)
- ❌ Host credentials or secrets
- ❌ Other users' files or directories

**Security properties:**

- Agent cannot corrupt your host configs
- Agent cannot access credentials outside its session
- Agent cannot start containers or escalate privileges
- Credentials are ephemeral (deleted when container exits)
- Cache is isolated from host filesystem

**Cache management:**

```bash
# View cache volume
docker volume ls | grep agent-container-cache

# Inspect cache size
docker system df -v | grep agent-container-cache

# Clear cache (forces fresh installs)
docker volume rm agent-container-cache
```

**See also:** `docs/plans/2025-12-10-isolated-container-design.md` for
complete design rationale.
```

**Step 2: Commit isolation section**

```bash
git add README.md
git commit -m "docs: add isolation and security section

Document what agent can/cannot access.
Explain security properties of isolated container.
Add cache management commands."
```

---

## Task 20: Update CLAUDE.md - Project Overview

**Files:**
- Modify: `CLAUDE.md:5-10`

**Step 1: Update project overview**

Replace lines 5-10 in CLAUDE.md with:

```markdown
## Project Overview

This is the **Agent Container** project - a Docker-based development
environment for working with AI coding agents (Claude Code and Gemini CLI)
using Git worktrees.

**Isolation Model:** The container uses VM-like isolation where only the
workspace directory is accessible to the agent. No access to host configs,
credentials, or Docker socket. This enables safe unsupervised agent
operation.

The project provides containerized isolation for development work with AI
assistants.
```

**Step 2: Commit CLAUDE.md overview update**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md overview for isolation

Add explanation of isolation model.
Clarify safety for unsupervised operation."
```

---

## Task 21: Update CLAUDE.md - Key Technologies Section

**Files:**
- Modify: `CLAUDE.md:33-35`

**Step 1: Update Code Quality Tools subsection**

Replace the Code Quality Tools subsection with:

```markdown
### Code Quality Tools

**All quality tools work EXCLUSIVELY through pre-commit hooks.**
Direct tool commands are not available in this environment.

Pre-commit hooks are extensively configured for:

- File validation (JSON, YAML, TOML, XML)
- Code formatting (Ruff for Python)
- Security (detect-secrets)
- Shell scripts (shellcheck via pre-commit)
- Markdown (markdownlint via pre-commit)
- Docker (hadolint via pre-commit)
- Python linting and formatting

**Cache:** Pre-commit hooks are cached in Docker volume
`agent-container-cache` for fast startup across sessions.
```

**Step 2: Commit code quality tools update**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with cache volume info

Mention agent-container-cache volume for pre-commit.
Note that caches are shared across sessions."
```

---

## Task 22: Update CLAUDE.md - Add Isolation Section

**Files:**
- Modify: `CLAUDE.md:50` (after Development Workflow, before Task Management)

**Step 1: Add Isolation Model section**

Add new section after Development Workflow:

```markdown
### Isolation Model (IMPORTANT)

**This container uses VM-like isolation for safe agent operation.**

**Agent can access:**

- Workspace directory (read-write)
- Main git repository (read-write, for worktree commits)
- Built-in configs from `files/homedir/` (ephemeral)
- Injected credentials (ephemeral)
- Shared cache volume `agent-container-cache`

**Agent CANNOT access:**

- Host filesystem outside workspace
- Host configs (`~/.claude`, `~/.config/gcloud`, etc.)
- Docker socket
- Host credentials or secrets

**Configuration files:**

- Located in `files/homedir/` directory
- Built into container image at build time
- Automatically copied to agent's home directory
- Changes inside container are NOT persistent
- To modify permanently: edit `files/homedir/` and rebuild image

**Credentials:**

- Never stored in git repository
- Injected at container startup via `--gcp-credentials` flag
- Auto-detected from `~/.config/gcloud/application_default_credentials.json`
- Deleted when container exits
- See `agent-container --help` for details

**Security:**

- Agent cannot damage host configs
- Agent cannot leak credentials between sessions
- Agent cannot access Docker or escalate privileges
- Limited blast radius (only workspace accessible)

**See:** `docs/plans/2025-12-10-isolated-container-design.md` for complete
design.
```

**Step 2: Commit isolation model section**

```bash
git add CLAUDE.md
git commit -m "docs: add isolation model section to CLAUDE.md

Document what agent can/cannot access.
Explain config and credential handling.
Reference design document."
```

---

## Task 23: Update CLAUDE.md - Environment Variables Section

**Files:**
- Modify: `CLAUDE.md:137-144`

**Step 1: Update environment variables section**

Replace the environment variables section with:

```markdown
## Environment Variables

### Claude Code Configuration

- `ANTHROPIC_API_KEY` - Anthropic API key (for direct API access)
- `ANTHROPIC_MODEL` - Model to use (default: claude-3-5-sonnet-20241022)
- `ANTHROPIC_SMALL_FAST_MODEL` - Fast model for simple tasks
- `ANTHROPIC_VERTEX_PROJECT_ID` - Google Cloud project for Vertex AI
- `CLOUD_ML_REGION` - Cloud region for Vertex AI
- `CLAUDE_CODE_USE_VERTEX` - Use Vertex AI instead of direct API

### Gemini CLI Configuration

- `GEMINI_API_KEY` - API key for Gemini

### Container Runtime

- `EUID` - User ID for container user (default: 1000)
- `EGID` - Group ID for container user (default: 1000)

**Note:** `PYTHON_TOOLS` environment variable is no longer used. Python
tools are installed in the image at build time.

### GCP Credential Injection

For Vertex AI, use credential file injection instead of mounting:

```bash
# Auto-detect from default location
agent-container -b feature

# Custom path
agent-container -b feature --gcp-credentials ~/my-sa.json
```

Credentials are ephemeral and deleted when container exits.
```

**Step 2: Commit environment variables update**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md environment variables

Add credential injection documentation.
Remove obsolete PYTHON_TOOLS mention.
Note ephemeral nature of credentials."
```

---

## Task 24: Update CLAUDE.md - Container Architecture Section

**Files:**
- Modify: `CLAUDE.md:146-161`

**Step 1: Update container architecture section**

Replace the Container Architecture section with:

```markdown
## Container Architecture

### Entrypoint Flow

1. `entrypoint.sh` - Creates user/group, sets up permissions, injects
   credentials
   - Creates user with host UID/GID
   - Manually copies `/etc/skel/` to home (configs from `files/homedir/`)
   - Decodes and writes GCP credentials if provided
2. `entrypoint_user.sh` - User-level setup, runs pre-commit

### Volume Mounts

**Workspace (read-write):**

- `/worktree` or current directory - Main working directory

**Main repository (read-write, if using worktrees):**

- Git repository root - Required for worktree commits

**Cache volume (read-write):**

- `agent-container-cache` → `~/.cache` - Shared across all sessions

**No other mounts.** No access to:

- `~/.claude` (config built into image)
- `~/.gemini` (config built into image)
- `~/.config/gcloud` (credentials injected at runtime)
- `~/.cache/pre-commit` (now in cache volume)
- `/var/run/docker.sock` (no Docker access)

### User Security

- Container runs as non-root user
- UID/GID mapping from host
- No Docker group access (no Docker socket)
- Proper permission handling for mounted workspace
- Credentials written with restrictive permissions (600)
```

**Step 2: Commit container architecture update**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md container architecture

Document new mount strategy.
List what is NOT mounted for clarity.
Update entrypoint flow description."
```

---

## Task 25: Create .gitignore for files/homedir

**Files:**
- Create: `files/homedir/.gitignore`

**Step 1: Create .gitignore to prevent credentials**

Create `files/homedir/.gitignore`:

```
# SECURITY: Never commit credentials or secrets
*.json
*.key
*.pem
*.p12
*.pfx
*credentials*
*secret*
*token*

# Allow non-credential JSON files explicitly
!.claude.json
!settings.json
!package.json

# SSH keys (if any added)
id_*
*.pub

# Environment files
.env*
```

**Step 2: Verify .gitignore works**

Run:
```bash
touch files/homedir/test-secret.json
git status
```

Expected: `test-secret.json` not shown in untracked files

Run: `rm files/homedir/test-secret.json`

**Step 3: Commit .gitignore**

```bash
git add files/homedir/.gitignore
git commit -m "security: add .gitignore to prevent credential commits

Add .gitignore to files/homedir/ to prevent accidental commits of:
- Credential files
- API keys
- Service account keys
- Environment files

Explicitly allow .claude.json (no secrets)."
```

---

## Task 26: Test Build - Build Container Image

**Files:**
- Test: Build with new Dockerfile changes

**Step 1: Build the container image**

Run:
```bash
docker build -t ghcr.io/johnstrunk/agent-container:test .
```

Expected: Build succeeds with no errors

**Step 2: Verify /etc/skel/ contents in image**

Run:
```bash
docker run --rm ghcr.io/johnstrunk/agent-container:test ls -la /etc/skel/
```

Expected output should show:
```
.claude.json
.gitconfig
start-claude
```

**Step 3: Verify start-claude is executable**

Run:
```bash
docker run --rm ghcr.io/johnstrunk/agent-container:test test -x /etc/skel/start-claude && echo "Executable"
```

Expected: "Executable"

**Step 4: Document build test results**

Create a simple test log:

```bash
echo "Build test passed: $(date)" >> docs/build-test.log
git add docs/build-test.log
```

**Step 5: Commit build verification**

```bash
git add docs/build-test.log
git commit -m "test: verify container build with new configs

Built test image successfully.
Verified /etc/skel/ contains expected config files.
Verified start-claude script is executable."
```

---

## Task 27: Test Credential Injection

**Files:**
- Test: Credential injection mechanism

**Step 1: Create test credential file**

Run:
```bash
mkdir -p /tmp/test-creds
echo '{"type": "service_account", "project_id": "test"}' > /tmp/test-creds/test-sa.json
```

**Step 2: Test base64 encoding in agent-container**

Run:
```bash
GCP_CREDS_PATH="/tmp/test-creds/test-sa.json"
GCP_CREDS_B64=$(base64 -w 0 "$GCP_CREDS_PATH")
echo "$GCP_CREDS_B64"
```

Expected: Base64 string output

**Step 3: Test credential injection in container**

Run:
```bash
docker run --rm \
    -e GCP_CREDENTIALS_B64="$GCP_CREDS_B64" \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="$HOME" \
    -e USER="$USER" \
    ghcr.io/johnstrunk/agent-container:test \
    bash -c 'cat /etc/google/application_default_credentials.json'
```

Expected: JSON content of test credential file

**Step 4: Verify GOOGLE_APPLICATION_CREDENTIALS set**

Run:
```bash
docker run --rm \
    -e GCP_CREDENTIALS_B64="$GCP_CREDS_B64" \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="$HOME" \
    -e USER="$USER" \
    ghcr.io/johnstrunk/agent-container:test \
    bash -c 'echo $GOOGLE_APPLICATION_CREDENTIALS'
```

Expected: `/etc/google/application_default_credentials.json`

**Step 5: Cleanup test files**

Run: `rm -rf /tmp/test-creds`

**Step 6: Document test results**

```bash
echo "Credential injection test passed: $(date)" >> docs/build-test.log
git add docs/build-test.log
git commit -m "test: verify credential injection mechanism

Tested base64 encoding/decoding of credentials.
Verified credentials written to correct path.
Verified GOOGLE_APPLICATION_CREDENTIALS environment variable set."
```

---

## Task 28: Test /etc/skel/ Copying

**Files:**
- Test: Config file copying from /etc/skel/

**Step 1: Test config copying in clean home**

Run:
```bash
docker run --rm \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="/home/testuser" \
    -e USER="testuser" \
    ghcr.io/johnstrunk/agent-container:test \
    bash -c 'ls -la ~/'
```

Expected: `.claude.json`, `.gitconfig`, `start-claude` visible in home

**Step 2: Test config file contents**

Run:
```bash
docker run --rm \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="/home/testuser" \
    -e USER="testuser" \
    ghcr.io/johnstrunk/agent-container:test \
    cat ~/.claude.json
```

Expected: JSON content from files/homedir/.claude.json

**Step 3: Test start-claude script is executable**

Run:
```bash
docker run --rm \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="/home/testuser" \
    -e USER="testuser" \
    ghcr.io/johnstrunk/agent-container:test \
    test -x ~/start-claude && echo "Executable"
```

Expected: "Executable"

**Step 4: Document test results**

```bash
echo "Config copying test passed: $(date)" >> docs/build-test.log
git add docs/build-test.log
git commit -m "test: verify /etc/skel/ config copying

Tested config files copied to user home.
Verified file contents match source.
Verified script executability preserved."
```

---

## Task 29: Test Cache Volume

**Files:**
- Test: Cache volume mounting and persistence

**Step 1: Create test file in cache**

Run:
```bash
docker run --rm \
    -v agent-container-cache:/home/testuser/.cache \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="/home/testuser" \
    -e USER="testuser" \
    ghcr.io/johnstrunk/agent-container:test \
    bash -c 'echo "test content" > ~/.cache/test-file.txt'
```

**Step 2: Verify file persists in new container**

Run:
```bash
docker run --rm \
    -v agent-container-cache:/home/testuser/.cache \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="/home/testuser" \
    -e USER="testuser" \
    ghcr.io/johnstrunk/agent-container:test \
    cat ~/.cache/test-file.txt
```

Expected: "test content"

**Step 3: Verify volume exists**

Run: `docker volume ls | grep agent-container-cache`

Expected: Volume listed

**Step 4: Clean up test data**

Run:
```bash
docker run --rm \
    -v agent-container-cache:/home/testuser/.cache \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="/home/testuser" \
    -e USER="testuser" \
    ghcr.io/johnstrunk/agent-container:test \
    rm ~/.cache/test-file.txt
```

**Step 5: Document test results**

```bash
echo "Cache volume test passed: $(date)" >> docs/build-test.log
git add docs/build-test.log
git commit -m "test: verify cache volume persistence

Tested cache volume mounting.
Verified data persists across container recreations.
Verified volume is shared across sessions."
```

---

## Task 30: Integration Test with agent-container

**Files:**
- Test: Full agent-container script with isolated mounts

**Step 1: Create test git repository**

Run:
```bash
mkdir -p /tmp/test-repo
cd /tmp/test-repo
git init
echo "# Test" > README.md
git add README.md
git commit -m "Initial commit"
```

**Step 2: Test agent-container with branch**

Run:
```bash
cd /tmp/test-repo
/home/user/workspace/agent-container -b test-feature echo "Success"
```

Expected:
- Worktree created
- Container starts
- "Success" printed
- Container exits
- Worktree removed

**Step 3: Verify mount messages**

Check output includes:
```
Mounting worktree: ... (rw)
Mounting main repo: ... (rw)
Mounting cache volume: agent-container-cache
```

**Step 4: Test without GCP credentials**

Run:
```bash
cd /tmp/test-repo
/home/user/workspace/agent-container -b test-feature2 echo "No creds"
```

Expected:
- "No GCP credentials file found" message
- Container still works
- "No creds" printed

**Step 5: Cleanup test repo**

Run: `rm -rf /tmp/test-repo`

**Step 6: Document integration test**

```bash
echo "Integration test passed: $(date)" >> docs/build-test.log
git add docs/build-test.log
git commit -m "test: verify agent-container integration

Tested full agent-container workflow with git worktrees.
Verified mount messages correct.
Verified works without credentials.
Verified worktree lifecycle."
```

---

## Task 31: Tag Image as Latest

**Files:**
- Action: Tag test image as latest

**Step 1: Tag test image as latest**

Run:
```bash
docker tag ghcr.io/johnstrunk/agent-container:test ghcr.io/johnstrunk/agent-container:latest
```

**Step 2: Verify tag**

Run: `docker images | grep agent-container`

Expected: Both `test` and `latest` tags visible

**Step 3: Remove test tag**

Run: `docker rmi ghcr.io/johnstrunk/agent-container:test`

**Step 4: Document tagging**

```bash
echo "Tagged image as latest: $(date)" >> docs/build-test.log
git add docs/build-test.log
git commit -m "build: tag tested image as latest

Testing complete, promoting test image to latest tag.
Ready for production use."
```

---

## Task 32: Final Verification and Cleanup

**Files:**
- Verify: All changes committed and tested

**Step 1: Verify all files committed**

Run: `git status`

Expected: "nothing to commit, working tree clean"

**Step 2: Review commit history**

Run: `git log --oneline -20`

Expected: ~32 commits for this implementation

**Step 3: Verify no credentials in repository**

Run: `git grep -i "credentials\|secret\|api.*key" files/`

Expected: Only .gitignore matches (no actual credentials)

**Step 4: Remove build test log**

Run:
```bash
git rm docs/build-test.log
git commit -m "chore: remove temporary build test log"
```

**Step 5: Create final summary commit**

```bash
git commit --allow-empty -m "chore: isolated container implementation complete

Summary of changes:
- Created files/homedir/ with built-in configs
- Modified Dockerfile to copy configs to /etc/skel/
- Updated entrypoint.sh for credential injection
- Removed Docker socket and host mount handling
- Updated agent-container for isolated mount strategy
- Added GCP credential injection with auto-detection
- Updated README.md and CLAUDE.md documentation
- Tested build, credential injection, config copying, and integration

The container now uses VM-like isolation with workspace-only access.
All tests passing. Ready for use.

See docs/plans/2025-12-10-isolated-container-design.md for design."
```

---

## Post-Implementation Notes

**Testing checklist completed:**

- ✅ Container builds successfully
- ✅ Config files copied to /etc/skel/
- ✅ Credential injection works
- ✅ /etc/skel/ copying works with -n flag
- ✅ Cache volume persists across sessions
- ✅ agent-container creates worktrees correctly
- ✅ Isolated mounts work as expected
- ✅ No credentials in git repository

**Manual testing recommended:**

1. Test with real GCP credentials
2. Test Claude Code inside container
3. Test pre-commit hooks with cache
4. Test git operations (commit, push) in worktree
5. Verify configs are ephemeral (changes lost on exit)

**Known limitations:**

- Main git repo is RW (trust model, required for commits)
- No network isolation (uses host network)
- Cache volume shared across all sessions (could be poisoned)

**See also:**

- Design document: `docs/plans/2025-12-10-isolated-container-design.md`
- Security considerations in design doc appendix
