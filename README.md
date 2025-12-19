# AI Development Environments

Isolated development environments for AI coding agents, available in two
approaches.

## Choose Your Approach

| Feature | Container | VM |
|---------|-----------|-----|
| **Startup time** | ~2 seconds | ~30-60 seconds |
| **Isolation** | Strong (namespaces) | Strongest (full VM) |
| **Nested virtualization** | No | Yes (libvirt/KVM) |
| **Resource overhead** | Minimal | Moderate |
| **Best for** | Quick iterations, development | Infrastructure testing, VMs |
| **Requires** | Docker | libvirt/KVM, Terraform |

## Quick Start

### Container Approach

Fast, lightweight isolation using Docker containers.

→ **[Container Documentation](container/README.md)**

```bash
cd container
./start-work -b my-feature-branch
```

### VM Approach

Full virtual machine isolation with nested virtualization support.

→ **[VM Documentation](vm/README.md)**

```bash
cd vm
./vm-up.sh
```

## What's Inside

Both approaches provide:

- **AI Coding Agents**: Claude Code, Gemini CLI, GitHub Copilot CLI
- **Development Tools**: Git, Node.js, Python, Go, Terraform
- **Code Quality**: pre-commit hooks, linting, formatting
- **Isolation**: Agent cannot access host filesystem or credentials

## Common Resources

Both approaches share configurations and package lists from `common/`:

- `common/homedir/` - Shared configuration files (.claude.json, .gitconfig)
- `common/packages/` - Package lists (apt, npm, python) and version pins

## License

MIT License - see [LICENSE](LICENSE) file for details.
