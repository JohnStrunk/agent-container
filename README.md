# Agent Container

A Docker-based development environment for working with AI coding agents
(Claude Code and Gemini CLI) using Git worktrees.

## Overview

This project provides a containerized environment that enables developers to
work with AI coding agents on isolated Git branches using worktrees. The
container comes pre-configured with:

- **Claude Code** - Anthropic's AI coding assistant
- **Gemini CLI** - Google's AI coding assistant  
- **Development tools** - Git, Node.js, Python, Docker CLI, and more
- **Code quality tools** - pre-commit, hadolint, pipenv, poetry

## Features

- **Isolated Development**: Each branch gets its own worktree and container instance
- **AI Agent Support**: Pre-installed Claude Code and Gemini CLI
- **Docker Integration**: Access to Docker socket for running additional containers
- **User Permissions**: Proper UID/GID mapping to avoid permission issues
- **Persistent Configuration**: Mounts for AI agent configurations and caches

## Quick Start

1. **Clone this repository** and create a symlink to make `start-work` globally available:

   ```bash
   git clone https://github.com/johnstrunk/agent-container.git
   mkdir -p ~/.local/bin
   ln -s "$(realpath agent-container/start-work)" ~/.local/bin/start-work
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
```

### Configuration

The container automatically mounts several directories for persistent configuration:

- `~/.claude` - Claude Code configuration
- `~/.gemini` - Gemini CLI configuration  
- `~/.config/gcloud` - Google Cloud configuration
- `~/.cache/pre-commit` - Pre-commit cache

### Environment Variables

Set these environment variables to configure the AI agents:

**Claude Code:**

- `ANTHROPIC_MODEL` - Model to use (default: claude-3-5-sonnet-20241022)
- `ANTHROPIC_SMALL_FAST_MODEL` - Fast model for simple tasks
- `ANTHROPIC_VERTEX_PROJECT_ID` - Google Cloud project for Vertex AI
- `CLOUD_ML_REGION` - Cloud region for Vertex AI
- `CLAUDE_CODE_USE_VERTEX` - Use Vertex AI instead of direct API

**Gemini CLI:**

- `GEMINI_API_KEY` - API key for Gemini

## Requirements

- Docker
- Git
- Bash

## File Structure

- `Dockerfile` - Container image definition
- `entrypoint.sh` - Container startup script with user setup
- `start-work` - Main script to create worktrees and start containers
- `LICENSE` - MIT License

## Docker Image

The container is based on Debian 13 slim and includes:

- **Runtime**: Node.js, Python 3, Docker CLI
- **AI Agents**: Claude Code, Gemini CLI  
- **Development Tools**: Git, curl, gosu
- **Python Tools**: pip, pipenv, poetry, pre-commit, uv
- **Linting**: hadolint for Dockerfile linting

## License

MIT License - see [LICENSE](LICENSE) file for details.
