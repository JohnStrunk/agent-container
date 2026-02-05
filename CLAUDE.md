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

## Determining Your Execution Environment

To determine whether you're running on the host, inside a VM, or inside a
container:

```bash
cat /etc/agent-environment 2>/dev/null || echo "host"
```

- `agent-vm` → Running inside a Lima VM
- `agent-container` → Running inside a Docker container
- `host` → Running on the host machine

This is useful when developing this repository itself, as the VM and
container environments support nested virtualization/containers for
testing changes.

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

## Developing This Repository

This repository is frequently developed from within the VM environment itself.
It supports nested virtualization/containers for testing changes:

### Nested VM Testing

When working inside a VM (`cat /etc/agent-environment` shows `agent-vm`),
you can test VM provisioning changes using nested virtualization:

**Memory requirements:**

- Outer VM needs enough memory for nested VM's default allocation (8GB)
- Recommended: 16GB for outer VM to comfortably run nested VM with
  defaults
- Adjust with `./agent-vm start --memory <GB>` if needed

**Startup time:**

- Nested VMs take approximately **5 minutes** to start (vs 4 minutes for
  host-level VMs)
- This is due to nested virtualization overhead

**Example workflow:**

```bash
# Check you're in the VM
cat /etc/agent-environment  # Should show: agent-vm

# Navigate to VM directory
cd ~/workspace/agent-container-fix-lima/vm

# Make changes to lima-provision.sh or agent-vm.yaml
# ...

# Test with nested VM (will be slow)
./agent-vm destroy  # Clean up previous test VM
./agent-vm start
./agent-vm connect
# Verify your changes work
exit

# Or run integration tests
cd ..
./test-integration.sh --vm
```

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
