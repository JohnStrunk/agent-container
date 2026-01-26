# Isolated Container Design for AI Coding Agents

## Overview

This design document describes the transition from the current shared-mount
container approach to a VM-like isolated container environment for AI coding
agents. The goal is to provide strong isolation while maintaining the
performance benefits of containers over VMs.

## Motivation

**Current limitations:**

- **Weak isolation**: Container shares ~10 host directories (configs,
  caches, credentials, Docker socket)
- **Security concerns**: Agent can modify host configs, access credentials,
  run Docker containers
- **Unsuitable for unsupervised use**: Too much access to host system

**VM approach strengths:**

- **Strong isolation**: Only workspace directory accessible
- **Credential safety**: Credentials injected at VM creation, isolated from
  host
- **Safe for unsupervised agents**: Limited blast radius

**VM approach weaknesses:**

- **Slow startup**: VM boot time measured in seconds
- **Complex sync**: Requires rsync/sshfs for file transfer
- **Infrastructure overhead**: Terraform, libvirt, networking setup

**Desired outcome:**

Combine container speed with VM isolation:

- Fast startup (containers start in milliseconds)
- Direct workspace access (no rsync/sshfs needed)
- Strong isolation (agent can't access host filesystem)
- Multiple concurrent sessions (via git worktrees)

## Design Principles

### 1. Workspace-Only Isolation

**Only the workspace directory is shared between host and container.**

- Agent works directly on workspace files (fast, no sync needed)
- Agent cannot access any other host directories
- Changes in workspace persist; everything else is ephemeral

### 2. Built-in Configuration

**Non-secret configs are built into the container image.**

- Stored in `files/homedir/` directory in repository
- Copied to user home via `/etc/skel/` mechanism
- Version controlled and reproducible
- No secrets or credentials in git repository

### 3. Runtime Credential Injection

**Credentials are injected at container startup, not stored in git.**

- Environment variables passed from host
- Credential files base64-encoded and injected
- Auto-detected from standard locations with override support
- Ephemeral (deleted when container exits)

### 4. Shared Caches for Performance

**Tool caches shared across all container sessions via Docker volumes.**

- Pre-commit hooks installed once, reused forever
- Python/Node packages cached
- Fast startup after first run
- Isolated from host filesystem

### 5. Trusted Agent within Boundaries

**Agent is trusted within its limited environment.**

- Has write access to git repo (required for worktree commits)
- Cannot access Docker socket
- Cannot access host configs or credentials
- Cannot affect other branches' worktrees (each in own container)

## Architecture

### Container Mounts

**Workspace directory (read-write):**

```bash
-v "$WORKTREE_DIR:$WORKTREE_DIR:rw"
```

- Agent's working directory
- Where code changes happen
- Persists after container exit

**Main git repository (read-write):**

```bash
-v "$MAIN_REPO_DIR:$MAIN_REPO_DIR:rw"
```

- Only mounted when using git worktrees
- Required for worktree commits (writes to `.git/objects/`, refs, logs)
- Agent trusted not to damage main `.git` directory
- Isolation comes from other boundaries

**Cache volume (read-write):**

```bash
-v "agent-container-cache:$HOME/.cache"
```

- Single Docker volume for all caches
- Shared across all container sessions
- Contains: pre-commit, uv, npm, go-build, etc.
- Persists across container recreations

**No other mounts:**

- No Docker socket
- No host configs (`~/.claude`, `~/.config/gcloud`, etc.)
- No host caches
- No host credentials
- No personal directories (Obsidian notes, etc.)

### Configuration Management

**Directory structure:**

```text
agent-container/
├── files/
│   └── homedir/
│       ├── .claude.json        # Claude settings (no API keys)
│       ├── .gitconfig          # Git config template
│       └── start-claude        # Helper script (optional)
├── Dockerfile
├── entrypoint.sh
├── entrypoint_user.sh
└── agent-container
```

**Built into image:**

```dockerfile
# In Dockerfile
COPY files/homedir/ /etc/skel/
```

**Copied to user home:**

```bash
# In entrypoint.sh (manual copy due to mount ordering)
useradd -o -u "$EUID" -g "$EGID" -d "$HOMEDIR" "$USERNAME"
mkdir -p "$HOMEDIR"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR"
gosu "$USERNAME" cp -rn /etc/skel/. "$HOMEDIR/"
```

The `-n` flag prevents overwriting files that already exist (handles
pre-existing mount paths).

**What goes in `files/homedir/`:**

- ✅ `.claude.json` with model preferences, settings
- ✅ `.gitconfig` with name, email, aliases
- ✅ Helper scripts like `start-claude`
- ✅ Tool configurations without secrets
- ❌ API keys or tokens
- ❌ Service account credentials
- ❌ Personal access tokens
- ❌ SSH private keys

### Credential Injection

**Supported credential types:**

1. **Environment variables** (always supported)
2. **GCP service account JSON** (optional)

**Environment variable passthrough:**

```bash
# In agent-container script
docker run \
    -e ANTHROPIC_API_KEY \
    -e ANTHROPIC_MODEL \
    -e ANTHROPIC_VERTEX_PROJECT_ID \
    -e CLOUD_ML_REGION \
    -e CLAUDE_CODE_USE_VERTEX \
    -e GEMINI_API_KEY \
    ...
```

**GCP credential file injection:**

```bash
# Auto-detect from standard location
DEFAULT_GCP_CREDS="$HOME/.config/gcloud/application_default_credentials.json"

# Override with flag
agent-container -b feature --gcp-credentials ~/custom-sa-key.json

# Base64 encode and inject
if [[ -f "$GCP_CREDS_PATH" ]]; then
    GCP_CREDS_B64=$(base64 -w 0 "$GCP_CREDS_PATH")
    docker run -e GCP_CREDENTIALS_B64="$GCP_CREDS_B64" ...
fi
```

**Entrypoint credential handling:**

```bash
# In entrypoint.sh
if [[ -n "$GCP_CREDENTIALS_B64" ]]; then
    mkdir -p /etc/google
    echo "$GCP_CREDENTIALS_B64" | base64 -d > \
        /etc/google/application_default_credentials.json
    chmod 600 /etc/google/application_default_credentials.json
    chown "$USERNAME":"$GROUPNAME" \
        /etc/google/application_default_credentials.json
    export GOOGLE_APPLICATION_CREDENTIALS=\
        /etc/google/application_default_credentials.json
fi
```

**Security properties:**

- Credentials never stored in git repository
- Credentials ephemeral (deleted when container exits)
- Each container session gets fresh credential injection
- No credential sharing between containers
- No credential pollution of host filesystem

### Git Worktree Support

**Mount strategy:**

Both worktree and main repository are mounted read-write:

```bash
MOUNT_ARGS+=(
    "-v" "$WORKTREE_DIR:$WORKTREE_DIR:rw"
    "-v" "$MAIN_REPO_DIR:$MAIN_REPO_DIR:rw"
)
```

**Why both need write access:**

Git worktrees write to the main repository's `.git/` directory:

- `.git/objects/` - New commit objects
- `.git/refs/heads/$branch` - Branch pointer updates
- `.git/logs/` - Reflog entries

Read-only main repository would break all git operations (commit, fetch,
push, etc.).

**Trust model:**

- Agent is trusted not to intentionally damage `.git`
- Agent can commit to its worktree branch normally
- Agent could theoretically modify other branches (trusted not to)
- Isolation comes from other boundaries:
  - No host filesystem access
  - No Docker access
  - No access to host credentials
  - Each worktree session in separate container

**Alternative considered and rejected:**

Clone branch instead of worktree:

- ❌ Slower startup (full clone)
- ❌ Requires rsync/fetch to get changes back
- ❌ Loses worktree workflow benefits
- ✅ Stronger git isolation

Trade-off decision: Keep worktree workflow, trust agent within boundaries.

**Non-git mode:**

When not using `-b branch` flag:

```bash
# Only mount current directory
MOUNT_ARGS+=("-v" "$CURRENT_DIR:$CURRENT_DIR:rw")
# No main repo mount needed
```

### Cache Strategy

**Single shared volume:**

```bash
docker run \
    -v "agent-container-cache:$HOME/.cache" \
    ...
```

**What gets cached:**

- `~/.cache/pre-commit` - Pre-commit hook installations
- `~/.cache/uv` - Python package downloads
- `~/.cache/npm` - Node package downloads
- `~/.cache/go-build` - Go build artifacts
- Any other tool caches under `~/.cache`

**Benefits:**

- First container run: Tools install/download as needed
- Subsequent runs: Instant (pre-commit hooks already installed, packages
  cached)
- Shared across all worktrees and branches
- Persists across container deletions
- Isolated from host (no risk of corrupting host caches)

**Maintenance:**

```bash
# Clear all caches (fresh start)
docker volume rm agent-container-cache

# Inspect cache contents
docker run --rm -v agent-container-cache:/cache alpine ls -lah /cache
```

## Implementation Changes

### 1. Dockerfile

**Add:**

```dockerfile
# Copy default configuration files
COPY files/homedir/ /etc/skel/

# These will be copied to user's home by entrypoint.sh
```

**Keep:**

- All existing tool installations
- Python tools (pre-commit, uv, poetry, etc.)
- AI agents (claude-code, gemini-cli, copilot)
- Development tools (git, go, nodejs, etc.)

### 2. entrypoint.sh

**Remove:**

```bash
# Docker socket group handling - NO LONGER NEEDED
if [[ -S /var/run/docker.sock ]]; then
    DOCKER_GID=$(stat -c '%g' /var/run/docker.sock)
    groupadd -g "$DOCKER_GID" docker || true
    usermod -aG docker "$USERNAME"
fi

# CONTAINER_MOUNT_PATHS permission fixing - NO LONGER NEEDED
if [[ -n "$CONTAINER_MOUNT_PATHS" ]]; then
    # ... complex permission fixing logic ...
fi
```

**Add:**

```bash
# Manual /etc/skel/ copying (due to mount ordering issues)
if [[ -d /etc/skel ]]; then
    gosu "$USERNAME" cp -rn /etc/skel/. "$HOMEDIR/"
fi

# Inject GCP credentials if provided
if [[ -n "$GCP_CREDENTIALS_B64" ]]; then
    mkdir -p /etc/google
    echo "$GCP_CREDENTIALS_B64" | base64 -d > \
        /etc/google/application_default_credentials.json
    chmod 600 /etc/google/application_default_credentials.json
    chown "$USERNAME":"$GROUPNAME" \
        /etc/google/application_default_credentials.json
    export GOOGLE_APPLICATION_CREDENTIALS=\
        /etc/google/application_default_credentials.json
fi
```

**Modify:**

```bash
# Create user without -m flag (home might already exist from mounts)
useradd -o -u "$EUID" -g "$EGID" -d "$HOMEDIR" "$USERNAME"
mkdir -p "$HOMEDIR"
chown "$USERNAME":"$GROUPNAME" "$HOMEDIR"
```

### 3. agent-container Script

**Remove mounts:**

```bash
# OLD - These are NO LONGER mounted:
CONTAINER_MOUNTS=(
    "$HOME/.cache/pre-commit"      # Now: Docker volume
    "$HOME/.cache/uv"              # Now: Docker volume
    "$HOME/.claude"                # Now: Built-in config
    "$HOME/.claude.json"           # Now: Built-in config
    "$HOME/.config/gcloud"         # Now: Credential injection
    "$HOME/.gemini"                # Now: Built-in config
    "$HOME/Documents/Obsidian/RedHat"  # Now: Not accessible (isolated)
)
# ... loop to mount these ... REMOVED

# Docker socket - NO LONGER MOUNTED
"-v" "/var/run/docker.sock:/var/run/docker.sock"

# Pre-commit fallback - NO LONGER NEEDED
"-v" "agent-container-pre-commit-cache:/.pre-commit-fallback"
```

**New mounts:**

```bash
# Core mounts (always needed)
MOUNT_ARGS=(
    "-v" "$WORKTREE_DIR:$WORKTREE_DIR:rw"
    "-v" "agent-container-cache:$HOME/.cache"
)

# Git worktree mode: mount main repo too
if [[ "$USE_GIT" == 1 ]]; then
    MOUNT_ARGS+=("-v" "$MAIN_REPO_DIR:$MAIN_REPO_DIR:rw")
fi
```

**Add credential handling:**

```bash
# Default credential path
GCP_CREDS_PATH="$HOME/.config/gcloud/application_default_credentials.json"

# Parse --gcp-credentials flag
while [[ $# -gt 0 ]]; do
    case $1 in
        --gcp-credentials)
            GCP_CREDS_PATH="$2"
            shift 2
            ;;
        # ... other flags ...
    esac
done

# Inject credentials if file exists
CREDENTIAL_ARGS=()
if [[ -f "$GCP_CREDS_PATH" ]]; then
    echo "Injecting GCP credentials from $GCP_CREDS_PATH"
    GCP_CREDS_B64=$(base64 -w 0 "$GCP_CREDS_PATH")
    CREDENTIAL_ARGS+=("-e" "GCP_CREDENTIALS_B64=$GCP_CREDS_B64")
fi
```

**Remove env var:**

```bash
# OLD - No longer pass CONTAINER_MOUNT_PATHS
-e CONTAINER_MOUNT_PATHS="$CONTAINER_MOUNT_PATHS"
```

**Docker run command:**

```bash
docker run --rm -it \
    --name "$CONTAINER_NAME" \
    --hostname "$CONTAINER_NAME" \
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

**Update usage documentation:**

```bash
function usage {
    cat - <<EOF
$0: Start using a coding agent on a git worktree

Usage: $0 [options] [-b <branch_name>] [command...]

Options:
  -b, --branch <name>         Branch name for git worktree
  --gcp-credentials <path>    Path to GCP service account JSON
                              (default: ~/.config/gcloud/application_default_credentials.json)
  -h, --help                  Show this help

Arguments:
  command...                  Optional command to execute in the container

Environment Variables:
  ANTHROPIC_API_KEY          Anthropic API key for Claude
  GEMINI_API_KEY             Google Gemini API key
  (See README.md for full list)

Examples:
  $0 -b feature-auth                    # Start interactive session
  $0 -b feature-auth -- claude          # Run claude directly
  $0 --gcp-credentials ~/custom-sa.json -b feature  # Custom GCP creds

Notes:
  * Worktrees are stored in $WORKTREE_BASE_DIR
  * Container has NO access to host filesystem except workspace
  * Configs and credentials are isolated per-container
  * Use docker volume rm agent-container-cache to clear caches
EOF
}
```

### 4. entrypoint_user.sh

**No major changes needed:**

- Pre-commit setup logic remains (uses cached volume)
- Python tool installation already in Dockerfile
- User-level initialization still needed

### 5. Create files/homedir/ Directory

**Initial files:**

```bash
mkdir -p files/homedir
```

**Example `.claude.json`:**

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

**Example `.gitconfig`:**

```ini
[user]
    name = Claude Code Agent
    email = agent@example.com

[core]
    editor = vim
    autocrlf = input

[alias]
    st = status
    co = checkout
    br = branch
    ci = commit
```

**Note:** Users can customize these in the container, but changes are lost
on exit. For persistent changes, modify `files/homedir/` and rebuild image.

## Security Analysis

### Threat Model

**Assumptions:**

- Host system is trusted
- User's environment variables are not compromised
- User's credential files are secure
- AI agent may make mistakes but is not malicious

**Protections:**

1. **Filesystem isolation**: Agent cannot access host files outside
   workspace
2. **No Docker access**: Agent cannot start containers or escalate
   privileges
3. **Ephemeral credentials**: Credentials deleted when container exits
4. **Isolated configs**: Agent cannot corrupt host configs
5. **Cache isolation**: Agent cannot corrupt host caches

**Residual risks:**

1. **Main .git modification**: Agent could damage git repository
   - Mitigation: Agent is trusted; backups recommended; git reflog exists
2. **Workspace destruction**: Agent could delete all workspace files
   - Mitigation: Git history preserves code; worktree easily recreated
3. **Credential exposure in container**: Agent could read/leak credentials
   - Mitigation: Limited-scope credentials; ephemeral session; no
     persistence
4. **Cache poisoning**: Agent could corrupt shared cache volume
   - Mitigation: Easy to clear (`docker volume rm`); low impact

### Comparison to VM

| Security Boundary | Isolated Container | VM (yolo-vm) |
|-------------------|-------------------|--------------|
| Filesystem isolation | ✅ Workspace only | ✅ Workspace only |
| Config isolation | ✅ Built-in | ✅ Injected |
| Credential isolation | ✅ Ephemeral | ✅ Ephemeral |
| Docker access | ✅ None | ✅ None |
| Main repo protection | ⚠️ RW (trusted) | ✅ Not mounted |
| Network isolation | ❌ Host network | ✅ NAT network |
| Kernel isolation | ❌ Shared kernel | ✅ Separate kernel |
| Startup speed | ✅ Milliseconds | ❌ Seconds |
| File access speed | ✅ Direct | ⚠️ SSHFS/rsync |

**Trade-off summary:**

Container sacrifices some VM isolation (kernel, network, main .git) for:

- 10-100x faster startup
- Direct filesystem access (no sync lag)
- Simpler infrastructure (no libvirt/Terraform)

Suitable for supervised or semi-supervised agent use. For completely
unsupervised agents with untrusted code, VM provides stronger guarantees.

### Best Practices

**For users:**

1. **Use limited-scope credentials**: GCP service account with minimal IAM
   roles
2. **Regular git backups**: Push to remote frequently
3. **Review agent changes**: Don't blindly merge worktree branches
4. **Clear caches periodically**: `docker volume rm agent-container-cache`
5. **Keep credentials secure**: Don't commit to git, use secure storage

**For credential management:**

```bash
# Create limited-scope GCP service account
gcloud iam service-accounts create claude-code-dev \
    --display-name="Claude Code Agent (Dev)"

# Grant minimal permissions (example: Vertex AI only)
gcloud projects add-iam-policy-binding $PROJECT \
    --member="serviceAccount:claude-code-dev@$PROJECT.iam.gserviceaccount.com" \
    --role="roles/aiplatform.user"

# Create key
gcloud iam service-accounts keys create \
    ~/.config/gcloud/claude-code-dev.json \
    --iam-account=claude-code-dev@$PROJECT.iam.gserviceaccount.com

# Use with agent-container
agent-container -b feature \
    --gcp-credentials ~/.config/gcloud/claude-code-dev.json
```

## Performance Characteristics

### Startup Time

**First run (cold start):**

- Container image pull: ~30-60 seconds (one-time)
- Container start: ~500ms
- Pre-commit install: ~10-30 seconds (one-time per project)
- **Total first run**: ~60-90 seconds

**Subsequent runs (warm start):**

- Container start: ~500ms
- Pre-commit (cached): ~100ms
- **Total warm start**: ~1 second

**Compare to VM:**

- VM first boot: ~30-60 seconds
- VM subsequent boots: ~15-30 seconds
- **Container is 15-60x faster after first run**

### File I/O Performance

**Direct mount (container):**

- Native filesystem performance
- No network overhead
- No sync lag
- Instant visibility of changes (both directions)

**SSHFS/rsync (VM):**

- Network overhead on every operation
- Rsync required for large changes
- Potential sync conflicts
- Latency on file operations

**Container provides significantly better file I/O experience.**

### Cache Hit Rates

**Expected cache behavior:**

- Pre-commit hooks: ~100% hit rate after first run
- Python packages (uv): ~80-90% hit rate (depends on project)
- Node packages (npm): ~70-80% hit rate (depends on lock file)
- Go builds: ~60-70% hit rate (depends on code changes)

**Cache volume grows over time:**

- Initial: ~100-200 MB
- After 10 projects: ~500 MB - 1 GB
- Steady state: ~1-2 GB

**Cleanup strategy:**

```bash
# Clear all caches (fresh start)
docker volume rm agent-container-cache

# Inspect cache size
docker system df -v | grep agent-container-cache
```

## Migration Path

### Phase 1: Parallel Implementation

1. Keep existing `agent-container` script
2. Create new `agent-container-isolated` script
3. Users can test isolated mode without breaking existing workflow
4. Gather feedback and iterate

### Phase 2: Default Switch

1. Rename `agent-container` → `agent-container-legacy`
2. Rename `agent-container-isolated` → `agent-container`
3. Update documentation
4. Announce change to users

### Phase 3: Legacy Removal

1. After sufficient adoption (e.g., 3-6 months)
2. Remove `agent-container-legacy`
3. Clean up documentation references

### Backwards Compatibility

**Breaking changes:**

- No Docker socket access (agents using Docker must adapt)
- No access to host configs (agents expecting `~/.config/foo` won't work)
- No access to host caches (minor performance impact on first run)
- Main repo is RW instead of RO (lower isolation)

**Migration assistance:**

- Document what changed and why
- Provide examples of adapting workflows
- Offer support for edge cases

## Future Enhancements

### 1. Additional Credential Types

Support for more credential injection mechanisms:

- AWS credentials (`~/.aws/credentials`)
- Azure credentials
- Generic credential file injection (`--credential-file`)
- Secret management integration (HashiCorp Vault, etc.)

### 2. Network Isolation

Optional network isolation modes:

```bash
# Full network isolation (no internet)
agent-container -b feature --network none

# Limited network (specific domains only)
agent-container -b feature --network restricted
```

Requires Docker network configuration and potentially proxy setup.

### 3. Resource Limits

Optional container resource constraints:

```bash
# Limit CPU and memory
agent-container -b feature --cpus 2 --memory 4g

# Limit disk I/O
agent-container -b feature --device-write-bps /dev/sda:10mb
```

Prevents runaway agent processes from impacting host.

### 4. Audit Logging

Log all agent actions for review:

```bash
# Enable audit log
agent-container -b feature --audit-log ~/agent-logs/

# Review what agent did
cat ~/agent-logs/feature-2025-12-10.log
```

Useful for understanding agent behavior and debugging issues.

### 5. Session Recording

Record terminal session for playback:

```bash
# Record session
agent-container -b feature --record

# Replay later
asciinema play ~/.claude/sessions/feature-2025-12-10.cast
```

Useful for training, debugging, and documentation.

## References

- [VM Design Document](../yolo-vm/design-vm.md) - Original VM-based approach
- [VM Security Policy](../yolo-vm/SECURITY.md) - Security considerations
  for VMs
- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [Git Worktrees Documentation](https://git-scm.com/docs/git-worktree)

## Appendix: Decision Log

### Why RW main repo instead of RO?

**Decision**: Mount main git repository read-write.

**Rationale**: Git worktrees require write access to main `.git/` directory
for all operations (commit, fetch, push, etc.). Read-only mount breaks
fundamental git functionality.

**Alternatives considered:**

1. Clone instead of worktree - Rejected (slow, complex sync)
2. Overlayfs for selective RW - Rejected (complex, fragile)
3. Trust agent within boundaries - **Selected**

**Trade-off**: Lower isolation of git repository, higher functionality and
simplicity.

### Why single cache volume instead of multiple?

**Decision**: Use one `agent-container-cache` volume for all caches.

**Rationale**: Simpler management, fewer mounts, easier to clear all caches
at once.

**Alternatives considered:**

1. Separate volumes per tool - Rejected (complex, many mounts)
2. No caching - Rejected (slow)
3. Single volume - **Selected**

**Trade-off**: Can't selectively clear one tool's cache, but simplicity wins.

### Why base64 encoding for credentials instead of mount?

**Decision**: Base64-encode credential files and pass via environment
variable.

**Rationale**: Maintains isolation model (no host filesystem mounts),
credentials are ephemeral, follows VM pattern.

**Alternatives considered:**

1. Mount credential file read-only - Rejected (breaks isolation model)
2. Copy via docker cp - Rejected (container must be running first)
3. Base64 via env var - **Selected**

**Trade-off**: Slightly more complex, but maintains isolation.

### Why trust model for git instead of full isolation?

**Decision**: Trust agent not to damage main `.git` directory.

**Rationale**: Git is core to workflow, breaking git operations is not
acceptable. Agent is AI assistant, not malware. Risk is acceptable.

**Alternatives considered:**

1. Clone instead of worktree - Rejected (slow, complex sync)
2. Read-only git - Rejected (breaks git)
3. Trust within boundaries - **Selected**

**Trade-off**: Agent could theoretically damage git, but probability is low
and impact is recoverable (git reflog, backups).
