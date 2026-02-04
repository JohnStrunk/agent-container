# Claude Code Assistant Configuration

## Project Overview

This repository provides **two approaches** for creating isolated AI
development environments:

1. **Container** - Docker-based, `agent-container` command, fast startup
2. **VM** - Lima-based, `agent-vm` command (similar workflow)

Both approaches support worktrees, filesystem sharing, and multi-instance
operation.

## Determining Which Approach You're Working With

Check your current directory:

```bash
pwd
```

- If in `/path/to/repo/container` → Use container approach
- If in `/path/to/repo/vm` → Use VM approach (`agent-vm` command)
- If at root `/path/to/repo` → Ask user which approach they want

## Approach-Specific Documentation

**Container Approach:**

→ See [container/CLAUDE.md](container/CLAUDE.md) for detailed instructions

**VM Approach:**

→ See [vm/CLAUDE.md](vm/CLAUDE.md) for detailed instructions

## Integration Tests

Before committing changes that affect environment setup (Dockerfiles,
Lima configs, credential injection, or `common/` configs), run
integration tests:

```bash
./test-integration.sh --all
```

This validates that AI assistants can start and operate correctly after your
changes.

See design: `docs/plans/2026-01-05-integration-tests-design.md`

## Common Resources

Both approaches share resources from `common/` - this is the **single
source of truth** for configuration:

- `common/homedir/` - Configuration files deployed to user home
  directory
  - `.claude.json` - Claude Code settings
  - `.gitconfig` - Git configuration
  - `.claude/settings.json` - Claude settings
  - `.local/bin/start-claude` - Helper script
- `common/packages/` - Package lists and version pins
  - `apt-packages.txt` - Debian packages
  - `npm-packages.txt` - Node.js packages
  - `python-packages.txt` - Python packages
  - `versions.txt` - Version numbers for tools (Go, hadolint)
  - `envvars.txt` - Environment variables to pass through
- `common/scripts/` - Shared installation scripts
  - `install-tools.sh` - Claude Code and other tools

Any changes to packages, versions, or configuration should be made in
`common/` and will automatically apply to both container and VM
approaches.

## General Guidelines

- Use TodoWrite tool for complex multi-step tasks
- Run pre-commit checks after all changes
- Follow approach-specific testing procedures
- Commit frequently with descriptive messages

## Getting Help

If unclear which approach to work with, ask the user:

"Are you working with the container approach or the VM approach?"
