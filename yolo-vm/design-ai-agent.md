# AI Agent Integration Design for yolo-vm

## Overview

This design extends the yolo-vm Debian 13 deployment to support running AI
coding agents (starting with claude-code) autonomously within the VM. The
design prioritizes security isolation by avoiding host filesystem mounts and
minimizing credential scope.

## Security Requirements

### Credential Isolation

- **No host filesystem mounts**: All credentials injected during VM
  provisioning
- **Service account model**: Use dedicated GCP service account with minimal
  permissions
- **Vertex AI only**: Service account should only have Vertex AI API access
- **Single-use credentials**: Credentials written once during cloud-init,
  no runtime mounting

### Autonomous Operation

- VM must be self-contained with all required tools
- Agent runs with limited credentials (cannot access broader GCP resources)
- Unprivileged default user has access to all tools and credentials

## Technical Architecture

### Package Requirements

Based on the agent-container implementation, the following packages are
required:

**System packages:**

- `nodejs` - JavaScript runtime for npm-based agents
- `npm` - Package manager for installing AI agents
- `python3` - Python runtime for tooling ecosystem
- `python3-pip` - Python package manager
- `docker.io` - Docker CLI for container operations
- `jq` - JSON processing utility
- `yq` - YAML processing utility
- `ripgrep` - Fast code search tool
- `gosu` - User switching utility
- `ca-certificates` - SSL/TLS certificates
- `curl` - HTTP client
- `unzip` - Archive extraction

**Language runtimes:**

- Go 1.25.0 (installed from official tarball)
- Python 3 (from Debian packages)

**Python tools (installed via uv):**

- `pre-commit` - Git hook framework
- `poetry` - Python dependency management
- `pipenv` - Python environment management
- `dvc[all]` - Data version control

**AI agents (installed via npm):**

- `@anthropic-ai/claude-code` - Claude Code agent
- `@google/gemini-cli` - Gemini CLI agent
- `@github/copilot` - GitHub Copilot CLI

### Installation Strategy

#### System-Wide Tool Installation

All tools must be accessible to the unprivileged default user. Installation
locations:

1. **Go**: `/usr/local/go/` with `/usr/local/go/bin` in PATH
2. **uv**: `/usr/local/bin/uv` and `/usr/local/bin/uvx`
3. **Python tools**: System-wide via `uv pip install --system`
4. **npm packages**: Global via `npm install -g` → `/usr/local/lib/node_modules/`

#### Cloud-Init Installation Flow

```yaml
packages:
  - nodejs
  - npm
  - python3
  - python3-pip
  - docker.io
  - jq
  - yq
  - ripgrep
  - gosu
  - ca-certificates
  - curl
  - unzip
  # ... existing packages ...

runcmd:
  # Install Go
  - curl -fsSL https://go.dev/dl/go1.25.0.linux-amd64.tar.gz -o /tmp/go.tar.gz
  - tar -C /usr/local -xzf /tmp/go.tar.gz
  - rm /tmp/go.tar.gz

  # Install uv
  - curl -fsSL https://astral.sh/uv/install.sh | sh
  - mv /root/.cargo/bin/uv /usr/local/bin/
  - mv /root/.cargo/bin/uvx /usr/local/bin/

  # Install Python tools system-wide
  - uv pip install --system pre-commit poetry pipenv 'dvc[all]'

  # Install AI agents globally
  - npm install -g @anthropic-ai/claude-code@latest
  - npm install -g @google/gemini-cli@latest
  - npm install -g @github/copilot@latest
```

### Credential Management

#### Service Account Credentials

**Terraform variable:**

```hcl
variable "gcp_service_account_key_path" {
  description = "Path to GCP service account JSON key file for Vertex AI access"
  type        = string
  default     = ""
}
```

**Cloud-init injection:**

```yaml
write_files:
  - path: /etc/google/application_default_credentials.json
    permissions: '0644'
    content: |
      ${gcp_service_account_key}
```

**Environment configuration** (`/etc/profile.d/ai-agent.sh`):

```bash
export GOOGLE_APPLICATION_CREDENTIALS=/etc/google/application_default_credentials.json
export ANTHROPIC_VERTEX_PROJECT_ID="${vertex_project_id}"
export CLOUD_ML_REGION="${vertex_region}"
export CLAUDE_CODE_USE_VERTEX="true"
export PATH="/usr/local/go/bin:$PATH"
```

#### Terraform Variables

New variables required:

```hcl
variable "gcp_service_account_key_path" {
  description = "Path to GCP service account JSON key file"
  type        = string
  default     = ""
}

variable "vertex_project_id" {
  description = "Google Cloud project ID for Vertex AI"
  type        = string
  default     = ""
}

variable "vertex_region" {
  description = "Google Cloud region for Vertex AI"
  type        = string
  default     = "us-central1"
}
```

### Security Considerations

#### Service Account Permissions

Recommended minimal IAM permissions for the service account:

- `aiplatform.endpoints.predict` - Vertex AI inference
- `aiplatform.models.get` - Model access

**Do NOT grant:**

- Compute instance access
- Storage bucket access
- Other GCP service permissions
- Project-level admin permissions

#### Credential Scope

- Credentials are read-only at `/etc/google/application_default_credentials.json`
- Accessible to all users (world-readable) - acceptable since it's a limited
  service account
- No mechanism to mount or inject additional credentials at runtime
- VM is isolated - compromised agent cannot access host resources

## Implementation Plan Reference

See implementation plan at:
`docs/plans/2025-10-30-ai-agent-integration.md`

## Testing Strategy

### Verification Steps

1. **Tool availability**: Verify all tools accessible to default user
2. **Credential validation**: Test Vertex AI authentication
3. **Agent execution**: Run `claude-code` to verify full stack
4. **Environment variables**: Verify all required env vars are set
5. **Python tools**: Test `pre-commit`, `poetry`, etc.
6. **Path configuration**: Verify Go and uv in PATH

### Test Commands

```bash
# SSH as default user
ssh debian@<VM_IP>

# Verify tools
which claude-code
which uv
which go
which pre-commit

# Check environment
echo $GOOGLE_APPLICATION_CREDENTIALS
echo $ANTHROPIC_VERTEX_PROJECT_ID
echo $CLAUDE_CODE_USE_VERTEX

# Test Vertex AI auth
gcloud auth application-default print-access-token

# Run claude-code
claude-code --version
```

## Migration Path

This design is backward-compatible with existing yolo-vm deployments:

- New variables have sensible defaults (empty strings)
- If service account path not provided, credentials are not injected
- Agent packages are always installed but won't function without credentials
- Existing minimal VM functionality remains unchanged

## Future Enhancements

Potential future improvements:

1. **Multiple agent support**: Add configuration for Gemini and Copilot
2. **Credential rotation**: Support for refreshable credentials
3. **Agent-specific configurations**: Per-agent config file injection
4. **Monitoring**: Add logging/telemetry for agent usage
5. **Resource limits**: cgroups/systemd for agent resource constraints
