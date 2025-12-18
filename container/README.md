# Container Approach - Agent Container

Docker-based development environment for working with AI coding agents using
Git worktrees.

**[← Back to main documentation](../README.md)**

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

## Quick Start

1. **Clone this repository** and create a symlink to make `start-work` globally available:

   ```bash
   git clone https://github.com/johnstrunk/agent-container.git
   mkdir -p ~/.local/bin
   ln -s "$(realpath agent-container/container/start-work)" ~/.local/bin/start-work
   # Ensure ~/.local/bin is in your PATH
   ```

2. **Navigate to your development repository** and start working on a branch:

   ```bash
   cd <your-development-repo>
   start-work my-feature-branch
   ```

This will:

- Build the agent container image (if needed)
- Create a Git worktree for the specified branch
- Start the container with the worktree mounted
- Drop you into an interactive shell with AI agents available

## Usage

### Working with Branches

```bash
# Start work on a new branch (created from current HEAD)
start-work new-feature

# Switch to an existing branch
start-work existing-branch
```

### Inside the Container

Once in the container, you can use:

```bash
# Start Claude Code
claude

# Start Gemini CLI
gemini

# Start GitHub Copilot CLI
copilot
```

### Configuration

The container uses built-in configurations from `../common/homedir/`:

- `.claude.json` - Claude Code settings (model, preferences)
- `.gitconfig` - Git configuration (name, email, aliases)
- `start-claude` - Helper script

**These are built into the container image and NOT shared with your host.**
Changes you make inside the container are lost when it exits.

To customize permanently:

1. Edit files in `../common/homedir/`
2. Rebuild the image:
   `docker build -t ghcr.io/johnstrunk/agent-container -f Dockerfile ..`
3. Restart your container

**Automatic mounts (OLD BEHAVIOR) have been removed.**

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
start-work -b feature  # Uses ~/.config/gcloud/application_default_credentials.json

# Override with custom path
start-work -b feature --gcp-credentials ~/my-service-account.json
```

The credential file is:

- Base64-encoded and injected at container startup
- Written to `/etc/google/application_default_credentials.json`
- Deleted when container exits (ephemeral)
- Never stored in the git repository

## Requirements

- Docker
- Git
- Bash

## File Structure

- `Dockerfile` - Container image definition
- `entrypoint.sh` - Container startup script with user setup
- `entrypoint_user.sh` - User-level initialization
- `start-work` - Script to create worktrees and start containers
- `../common/homedir/` - Shared configuration files (built into container)
  - `.claude.json` - Claude Code settings
  - `.gitconfig` - Git configuration
  - `start-claude` - Helper script
- `../common/packages/` - Package lists (used during build)
  - `apt-packages.txt` - Debian packages
  - `npm-packages.txt` - Node.js packages
  - `python-packages.txt` - Python packages
  - `versions.txt` - Version pins

## Docker Image

The container is based on Debian 13 slim and includes:

- **Runtime**: Node.js, Python 3, Docker CLI
- **AI Agents**: Claude Code, Gemini CLI, GitHub Copilot CLI  
- **Development Tools**: Git, curl, gosu
- **Python Tools**: pip, pipenv, poetry, pre-commit, uv
- **Linting**: hadolint for Dockerfile linting

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

## License

MIT License - see [LICENSE](LICENSE) file for details.
