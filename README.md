# AI Development Environments

Isolated development environments for AI coding agents, available in two
approaches.

## Choose Your Approach

| Feature | Container | VM |
| ------- | --------- | --- |
| **Startup time** | ~2 seconds | ~30-60 seconds |
| **Isolation** | Strong (namespaces) | Strongest (full VM) |
| **Nested virtualization** | No | Yes (via Lima) |
| **Resource overhead** | Minimal | Moderate |
| **Platform support** | Linux, macOS, Windows | Linux, macOS, Windows |
| **Best for** | Quick iterations, development | Testing, cross-platform |
| **Requires** | Docker or Podman | Lima |

## Quick Start

### Container Approach

Fast, lightweight isolation using Docker or Podman containers.

→ **[Container Documentation](container/README.md)**

**Prerequisites:** Docker or Podman (auto-detected)

```bash
cd container
./agent-container -b my-feature-branch
```

### VM Approach

Full virtual machine isolation using Lima. Works on Linux and macOS.

→ **[VM Documentation](vm/README.md)**

**Prerequisites:** Lima

```bash
cd vm
./agent-vm -b my-feature-branch
```

## What's Inside

Both approaches provide:

- **AI Coding Agents**: Claude Code, Gemini CLI, OpenCode AI, GitHub
  Copilot
- **Development Tools**: Git, Node.js, Python, Go, Terraform
- **Code Quality**: pre-commit hooks, linting, formatting
- **Isolation**: Agent cannot access host filesystem or credentials

## Common Resources

Both approaches share configurations and package lists from `common/`:

- `common/homedir/` - Shared configuration files (.claude.json, .gitconfig)
- `common/packages/` - Package lists (apt, npm, python) and version pins

## Integration Tests

End-to-end tests that validate both container and VM environments can
successfully run AI assistants after repository changes.

**Requirements:**

- Valid credentials (GCP service account or API keys)
- Docker (for container tests) or Lima (for VM tests)

**Run tests:**

```bash
# Test container approach
./test-integration.sh --container

# Test VM approach
./test-integration.sh --vm

# Test both
./test-integration.sh --all

# Custom credentials
./test-integration.sh --container --gcp-credentials ~/my-creds.json
```

**Note:** These tests make real API calls and are not suitable for CI. Run
locally before committing changes to configs, Dockerfiles, or Lima
configurations.

See `docs/plans/2026-01-05-integration-tests-design.md` for design details.

## Breaking Changes

### 2026-01-05: GCP Credential Environment Variable

The custom `GCP_CREDENTIALS_PATH` environment variable has been replaced with
the industry-standard `GOOGLE_APPLICATION_CREDENTIALS`.

**Migration required for VM approach:**

```bash
# Old (no longer works)
export GCP_CREDENTIALS_PATH="~/my-service-account.json"
./vm/agent-vm -b my-branch

# New
export GOOGLE_APPLICATION_CREDENTIALS="~/my-service-account.json"
./vm/agent-vm -b my-branch
```

**Container and integration tests:** No action required (CLI flag still works)

**Credential detection order:**

- Container: `--gcp-credentials` flag → `GOOGLE_APPLICATION_CREDENTIALS` →
  default
- VM: `GOOGLE_APPLICATION_CREDENTIALS` → default
- Integration tests: `--gcp-credentials` flag →
  `GOOGLE_APPLICATION_CREDENTIALS` → default

Default location: `~/.config/gcloud/application_default_credentials.json`

## License

MIT License - see [LICENSE](LICENSE) file for details.
