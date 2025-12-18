# Claude Code Assistant Configuration

## Project Overview

This repository provides **two approaches** for creating isolated AI
development environments:

1. **Container** - Docker-based, fast startup, strong isolation
2. **VM** - Libvirt/KVM-based, full VM isolation, nested virtualization

## Determining Which Approach You're Working With

Check your current directory:

```bash
pwd
```

- If in `/path/to/repo/container` → Use container approach
- If in `/path/to/repo/vm` → Use VM approach
- If at root `/path/to/repo` → Ask user which approach they want

## Approach-Specific Documentation

**Container Approach:**

→ See [container/CLAUDE.md](container/CLAUDE.md) for detailed instructions

**VM Approach:**

→ See [vm/CLAUDE.md](vm/CLAUDE.md) for detailed instructions

## Common Resources

Both approaches share resources from `common/`:

- `common/homedir/` - Configuration files deployed to user home directory
  - `.claude.json` - Claude Code settings
  - `.gitconfig` - Git configuration
  - `.claude/settings.json` - Claude settings
  - `.local/bin/start-claude` - Helper script
- `common/packages/` - Package lists and version pins
  - `apt-packages.txt` - Debian packages
  - `npm-packages.txt` - Node.js packages
  - `python-packages.txt` - Python packages
  - `versions.txt` - Version numbers for tools

## General Guidelines

- Use TodoWrite tool for complex multi-step tasks
- Run pre-commit checks after all changes
- Follow approach-specific testing procedures
- Commit frequently with descriptive messages

## Getting Help

If unclear which approach to work with, ask the user:

"Are you working with the container approach or the VM approach?"
