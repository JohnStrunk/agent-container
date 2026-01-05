# Claude Code Assistant Configuration - Container Approach

**[← Back to root CLAUDE.md](../CLAUDE.md)**

## Project Overview

This is the **Container approach** - a Docker-based development
environment for working with AI coding agents (Claude Code and Gemini CLI)
using Git worktrees.

**Isolation Model:** The container uses VM-like isolation where only the
workspace directory is accessible to the agent. No access to host configs,
credentials, or Docker socket. This enables safe unsupervised agent
operation.

The project provides containerized isolation for development work with AI
assistants.

## Project Structure

```text
container/
├── Dockerfile              # Container image definition
├── entrypoint.sh          # Container startup script
├── entrypoint_user.sh     # User-level setup
├── start-work             # Main script
├── README.md              # Container documentation
└── CLAUDE.md              # This file

../common/
├── homedir/               # Shared configs (.claude.json, .gitconfig)
└── packages/              # Package lists (apt, npm, python)
```

## Key Technologies & Tools

### Container Environment

- **Base**: Debian 13 slim
- **Runtime**: Node.js, Python 3, Docker CLI
- **AI Agents**: Claude Code, Gemini CLI (installed via npm)
- **Development Tools**: Git, curl, gosu, ripgrep, jq, yq
- **Python Tools**: pip, pipenv, poetry, pre-commit, uv
- **Languages**: Go (v1.25.0), Python 3
- **Linting**: hadolint for Dockerfile validation

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

## Development Workflow

### Isolation Model (IMPORTANT)

**This container uses VM-like isolation for safe agent operation.**

**Agent can access:**

- Workspace directory (read-write)
- Main git repository (read-write, for worktree commits)
- Built-in configs from `../common/homedir/` (ephemeral)
- Injected credentials (ephemeral)
- Shared cache volume `agent-container-cache`

**Agent CANNOT access:**

- Host filesystem outside workspace
- Host configs (`~/.claude`, `~/.config/gcloud`, etc.)
- Docker socket
- Host credentials or secrets

**Configuration files:**

- Located in `../common/homedir/` directory
- Built into container image at build time
- Automatically copied to agent's home directory
- Changes inside container are NOT persistent
- To modify permanently: edit `../common/homedir/` and rebuild image

**Credentials:**

- Never stored in git repository
- Injected at container startup via `--gcp-credentials` flag
- Auto-detected from `~/.config/gcloud/application_default_credentials.json`
- Deleted when container exits
- See `start-work --help` for details

**Security:**

- Agent cannot damage host configs
- Agent cannot leak credentials between sessions
- Agent cannot access Docker or escalate privileges
- Limited blast radius (only workspace accessible)

**See:** `docs/plans/2025-12-10-isolated-container-design.md` for complete
design.

### Task Management

**CRITICAL**: Always use the TodoWrite tool to plan and track tasks. This is
essential for:

- Breaking down complex tasks into manageable steps
- Tracking progress throughout the session
- Ensuring no steps are missed
- Providing visibility to users about current progress

### Pre-commit Quality Checks (MANDATORY)

**ALL changes must pass pre-commit checks before completion.** This project
has strict quality standards:

```bash
# ALWAYS run this after making ANY changes
pre-commit run --files <filename>

# For multiple files or all files
pre-commit run --all-files

# Install hooks (required once per environment)
pre-commit install
```

**Common pre-commit fixes needed:**

- Files must end with exactly one newline
- No trailing whitespace
- Markdown must follow strict linting rules (see below)
- Shell scripts must pass shellcheck
- No secrets or credentials in files

### Building and Testing

```bash
# Build the container image
cd /home/user/workspace/container
docker build -t ghcr.io/johnstrunk/agent-container -f Dockerfile ..

# Test with current directory
./start-work

# Test with a git branch (creates worktree)
./start-work feature-branch-name
```

### Specific Tool Validation via Pre-commit

**IMPORTANT**: All linting tools work ONLY through pre-commit hooks.
Direct tool commands are not available in this environment.

```bash
# Lint Dockerfile specifically (through pre-commit)
pre-commit run hadolint --files Dockerfile

# Validate shell scripts specifically (through pre-commit)
pre-commit run shellcheck --files *.sh

# Check markdown formatting specifically (through pre-commit)
pre-commit run markdownlint --files *.md
```

## File Modification Guidelines

### Shell Scripts

- Use `#!/bin/bash` shebang
- Include `set -e -o pipefail` for safety
- Follow shellcheck recommendations
- Use double quotes for variables: `"$VARIABLE"`
- Use local variables in functions: `local var_name="$1"`

### Dockerfile

- Follow hadolint recommendations
- Don't worry about providing image digests. Renovate-bot handles this.
- Use build cache mounts where appropriate
- Minimize layers and use multi-stage builds when beneficial
- Pin version numbers for reproducibility

### Documentation

**Markdown files have STRICT formatting requirements:**

- **Line length**: Maximum 80 characters per line
- **Code blocks**: Must specify language (e.g., `bash`, `text`, `yaml`)
- **Headings**: Must have blank lines before AND after
- **Lists**: Must have blank lines before AND after
- **Code blocks**: Must have blank lines before AND after
- **File ending**: Must end with exactly one newline
- **No trailing whitespace** on any line

**Common markdown fixes:**

```bash
# Check markdown before committing (ONLY through pre-commit)
pre-commit run markdownlint --files <filename>.md
```

Note: Auto-fix is not available - markdownlint only validates. You must
manually fix all reported issues

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

### GCP Credential Injection

For Vertex AI, use credential file injection instead of mounting:

```bash
# Auto-detect from default location
start-work -b feature

# Custom path
start-work -b feature --gcp-credentials ~/my-sa.json
```

Credentials are ephemeral and deleted when container exits.

## Container Architecture

### Entrypoint Flow

1. `entrypoint.sh` - Creates user/group, sets up permissions, injects
   credentials
   - Creates user with host UID/GID
   - Manually copies `/etc/skel/` to home (configs from `../common/homedir/`)
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

### Environment Identification

The container includes an environment marker file at
`/etc/agent-environment` containing `agent-container`. This identifies the
execution context and is used to prevent integration tests from running
inside the container (which lacks Docker and VM support).

## Common Tasks

### Adding New Tools

1. **Plan your actions**: Create tasks for each step
2. Update Dockerfile to install the tool
3. Update entrypoint scripts if user-level setup is needed
4. Update README.md with usage instructions
5. **MANDATORY**: Run `pre-commit run --all-files` and fix any issues
6. Test the build and functionality
7. **Mark tasks complete** as you finish each step

**Note**: All linting (hadolint, shellcheck, etc.) happens through pre-commit.
No direct tool commands are available.

### Modifying Pre-commit Hooks

1. **Plan your actions**: Create tasks for testing changes
2. Edit `.pre-commit-config.yaml`
3. Run `pre-commit install` to update hooks
4. **CRITICAL**: Test with `pre-commit run --all-files`
5. Fix any issues that arise (may require multiple iterations)
6. Verify all checks pass before considering complete

### Updating Dependencies

1. **Plan your actions**: Break down into specific updates
2. Update version numbers in Dockerfile
3. Update pre-commit hook versions in `.pre-commit-config.yaml`
4. **MANDATORY**: Run pre-commit checks after each change
5. Rebuild and test the container
6. Verify all quality checks pass

### Creating or Modifying Documentation

**CRITICAL WORKFLOW** for any `.md` file changes:

1. **Plan your actions**: Include pre-commit verification as a task
2. Make your documentation changes
3. **IMMEDIATELY** run: `pre-commit run --files <filename>.md`
4. **Fix ALL issues** found (may require multiple rounds)
5. **Re-run** pre-commit until all checks pass
6. Only then consider the task complete

**Expected markdown issues and fixes:**

- Line too long → Break into multiple lines
- Missing language in code block → Add `bash`, `text`, etc.
- Missing blank lines → Add blank lines around headings/lists/code blocks
- Missing final newline → Will be auto-fixed by end-of-file-fixer

## Security Considerations

- Pin all external dependencies with specific versions
- Use minimal base images
- Run as non-root user
- Validate all inputs in shell scripts
- Use detect-secrets pre-commit hook to prevent credential leaks

## Testing Strategy

**Multi-layered validation approach:**

1. **Pre-commit validation** (MANDATORY for all changes)
   - Run `pre-commit run --files <changed-files>` after each change
   - Fix all issues before proceeding
   - Must pass 100% before task completion

2. **Component-specific testing**
   - Manual testing with `./start-work` script
   - Container build testing
   - Volume mount and permission testing
   - AI agent functionality testing within container

3. **Iterative quality checking**
   - Test early and often during development
   - Fix issues immediately when found
   - Re-run checks until all pass

### Integration Tests

Run end-to-end tests to validate container environment:

```bash
# From repository root
./test-integration.sh --container
```

This tests:

- Docker image builds successfully
- Credentials inject correctly
- Config files deploy from `common/homedir/`
- Claude Code starts and responds to prompts

**When to run:**

- Before committing Dockerfile changes
- Before committing changes to `common/homedir/` configs
- Before committing entrypoint script changes
- After updating package lists in `common/packages/`

## Maintenance Notes

- Container image is published to `ghcr.io/johnstrunk/agent-container`
- Renovate bot handles dependency updates
- Pre-commit hooks ensure code quality
- All shell scripts should pass shellcheck
- Dockerfile should pass hadolint validation
