# Integration Tests for AI Development Environments

## Overview

This design document describes end-to-end integration tests that verify AI
assistants (Claude Code) can successfully start and operate after repository
changes. The tests validate credential injection, configuration deployment,
and basic AI agent functionality for both container and VM approaches.

## Motivation

**Current testing gaps:**

- **Static analysis only**: Pre-commit hooks validate syntax but not runtime
  behavior
- **No credential validation**: Cannot verify credential injection actually
  works
- **Config deployment untested**: Changes to `common/homedir/` configs may
  break environments
- **Manual verification required**: Developer must manually test after
  changes
- **Past failures**: Multiple instances of broken credential passing and
  config deployment

**Desired outcome:**

- Automated tests that catch credential and config issues before they reach
  users
- End-to-end validation of full environment lifecycle
- Fast feedback during development
- Confidence that both approaches work after changes

## Design Principles

### 1. Full Lifecycle Testing

**Tests run complete build/provision → test → cleanup cycle.**

- Container: Docker build → start container → test Claude → cleanup
- VM: Terraform provision → cloud-init → test Claude → destroy
- No shortcuts or mocking
- Tests actual production paths

### 2. Real Credentials Required

**Tests use actual API credentials, not mocks.**

- Same credential mechanisms as production
- Tests credential injection from host to environment
- Validates credential format and permissions
- Not suitable for CI (requires secrets, costs money)

### 3. Developer-Focused

**Designed for local execution before commits.**

- Runs on developer workstation
- Clear verbose output shows progress
- Fast enough for iterative development (3-6 minutes)
- Clean state after every run

### 4. Simple Validation

**Uses deterministic prompt with flexible matching.**

- One-shot prompt: "Repeat this phrase exactly: 'All systems go!'"
- Validates response contains expected phrase
- Tolerates extra politeness text from model
- Fast validation (60 second timeout)

### 5. Always Cleanup

**Never leaves resources behind.**

- Cleanup runs via trap EXIT (always executes)
- Removes containers, VMs, temporary files
- Safe to run repeatedly
- No manual cleanup required

## Architecture

### File Structure

```text
/home/user/workspace/
├── test-integration.sh          # Main test script (new)
├── container/
│   ├── start-work              # Used by container test
│   └── Dockerfile              # Rebuilt by test
└── vm/
    ├── vm-up.sh                # Used by VM test
    ├── vm-connect.sh           # Used by VM test (indirectly)
    └── main.tf                 # Applied by test
```

Single unified script at repository root: `test-integration.sh`

### Command-Line Interface

```bash
# Run specific test
./test-integration.sh --container
./test-integration.sh --vm

# Run both sequentially
./test-integration.sh --all

# Pass custom credentials (inherits from start-work/vm-up.sh)
./test-integration.sh --container --gcp-credentials ~/my-creds.json

# Force rebuild (bypass Docker cache)
./test-integration.sh --container --rebuild
```

### Environment Detection

Both container and VM environments include an environment marker file at
`/etc/agent-environment` that identifies the execution context:

- **Container**: Contains `agent-container`
- **VM**: Contains `agent-vm`
- **Host**: File does not exist

The integration test script checks this marker and **prevents execution
inside the container environment**, which lacks Docker and VM support. Tests
can run from the host or VM environments.

```bash
# /etc/agent-environment content
agent-container  # In container
agent-vm         # In VM
# (file absent)  # On host
```

This prevents accidental test execution in environments that cannot support
the required tooling (Docker, Terraform, libvirt).

### Test Execution Flow

#### Container Test

```text
1. Validate prerequisites (Docker running, credentials exist)
2. Build container image (5 min timeout)
   docker build -t ghcr.io/johnstrunk/agent-container -f container/Dockerfile .
3. Start container with test command (90s timeout)
   ./container/start-work -- bash -c "$(test_claude_command)"
4. Validate Claude response contains "All systems go!"
5. Cleanup (automatic via docker --rm)
```

#### VM Test

```text
1. Validate prerequisites (Terraform, libvirt, credentials)
2. Destroy any existing VM from previous test
3. Provision VM via Terraform (5 min timeout)
   cd vm && ./vm-up.sh
4. Wait for cloud-init completion (2 min timeout)
   ssh claude@vm 'cloud-init status --wait'
5. Run Claude test via SSH (60s timeout)
   ssh claude@vm "$(test_claude_command)"
6. Validate response contains "All systems go!"
7. Cleanup: terraform destroy (automatic via trap EXIT)
```

### Test Command

Both tests execute the same validation command:

```bash
#!/bin/bash
set -e -o pipefail

echo "[Test] Sending prompt to Claude Code..."

# One-shot prompt with 60s timeout
timeout 60 claude -p "Repeat this phrase exactly: 'All systems go!'" \
  > /tmp/claude-response.txt 2>&1 || {
  echo "ERROR: Claude did not respond within timeout"
  cat /tmp/claude-response.txt
  exit 1
}

# Validate response contains expected phrase
if grep -q "All systems go!" /tmp/claude-response.txt; then
  echo "[Test] ✓ Claude response validated"
  echo "[Test] Response: $(cat /tmp/claude-response.txt)"
  exit 0
else
  echo "ERROR: Claude response did not contain expected phrase"
  echo "Response was:"
  cat /tmp/claude-response.txt
  exit 1
fi
```

**Note:** This requires adding `-p`/`--print` flag support to the
`start-claude` helper script or calling `claude` directly with the flag.

### Timeouts

| Phase | Timeout | Rationale |
|-------|---------|-----------|
| Docker build | 5 min | Handles slow builds, downloads |
| VM provision | 5 min | Terraform apply + VM boot |
| cloud-init wait | 2 min | Package installation in VM |
| Claude response | 60 sec | API call + response generation |
| **Total (Container)** | **3-6 min** | Mostly build time |
| **Total (VM)** | **2-4 min** | Provision + cloud-init |

### Credential Handling

**Philosophy:** Reuse exact same mechanisms as production scripts.

**Container approach:**

```bash
# Auto-detect from default location
./test-integration.sh --container

# Custom path via flag
./test-integration.sh --container --gcp-credentials ~/my-creds.json

# Passed to start-work:
./container/start-work ${GCP_CREDS_ARG:+--gcp-credentials "$GCP_CREDS_PATH"}
```

**VM approach:**

```bash
# Auto-detect from default location
./test-integration.sh --vm

# Custom path via environment variable
GCP_CREDENTIALS_PATH=~/my-creds.json ./test-integration.sh --vm

# Used by vm-up.sh (auto-detects or uses env var)
cd vm && ./vm-up.sh
```

**Validation before tests:**

```bash
if [[ ! -f "$GCP_CREDS_PATH" ]] && \
   [[ -z "$ANTHROPIC_API_KEY" ]] && \
   [[ -z "$GEMINI_API_KEY" ]]; then
  echo "ERROR: No credentials found. Need at least one of:"
  echo "  - GCP credentials: gcloud auth application-default login"
  echo "  - ANTHROPIC_API_KEY environment variable"
  echo "  - GEMINI_API_KEY environment variable"
  exit 2
fi
```

### Helper Functions

```bash
# Logging with timestamps
log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

log_step() {
  echo "[$(date '+%H:%M:%S')] === $* ==="
}

# Timeout wrapper
run_with_timeout() {
  local timeout=$1
  shift
  timeout "$timeout" "$@"
}

# Cleanup handlers (runs on EXIT)
trap cleanup_all EXIT

cleanup_all() {
  local exit_code=$?

  if [[ "$TEST_TYPE" == "container" ]] || [[ "$TEST_TYPE" == "all" ]]; then
    cleanup_container
  fi

  if [[ "$TEST_TYPE" == "vm" ]] || [[ "$TEST_TYPE" == "all" ]]; then
    cleanup_vm
  fi

  exit $exit_code
}

cleanup_container() {
  log "Cleaning up container resources..."
  # Docker handles cleanup via --rm flag
}

cleanup_vm() {
  log "Cleaning up VM..."
  cd vm && terraform destroy -auto-approve \
    -var="user_uid=$(id -u)" \
    -var="user_gid=$(id -g)" 2>&1 | grep -v "^$" || true
  cd ..
}
```

## Error Handling

### Prerequisite Validation

Before running tests, validate required tools and credentials:

```bash
validate_prerequisites() {
  local errors=0

  # Check Docker for container tests
  if [[ "$TEST_TYPE" == "container" ]] || [[ "$TEST_TYPE" == "all" ]]; then
    if ! command -v docker &>/dev/null; then
      log "ERROR: docker not found. Install Docker first."
      ((errors++))
    fi

    if ! docker info &>/dev/null; then
      log "ERROR: Docker daemon not running"
      log "  Start with: sudo systemctl start docker"
      ((errors++))
    fi
  fi

  # Check Terraform and libvirt for VM tests
  if [[ "$TEST_TYPE" == "vm" ]] || [[ "$TEST_TYPE" == "all" ]]; then
    if ! command -v terraform &>/dev/null; then
      log "ERROR: terraform not found. Install Terraform first."
      ((errors++))
    fi

    if ! virsh list &>/dev/null; then
      log "ERROR: libvirt not accessible"
      log "  Check: sudo systemctl status libvirtd"
      ((errors++))
    fi
  fi

  # Check credentials
  if [[ ! -f "$GCP_CREDS_PATH" ]] && \
     [[ -z "$ANTHROPIC_API_KEY" ]] && \
     [[ -z "$GEMINI_API_KEY" ]]; then
    log "ERROR: No credentials found. Need at least one of:"
    log "  - GCP: gcloud auth application-default login"
    log "  - ANTHROPIC_API_KEY environment variable"
    log "  - GEMINI_API_KEY environment variable"
    ((errors++))
  fi

  return $errors
}
```

### Edge Cases

**Stale VM from previous failed test:**

```bash
# Before VM test, check if VM already exists
if terraform state list 2>/dev/null | grep -q libvirt_domain.agent_vm; then
  log "WARNING: Found existing VM from previous test, destroying..."
  terraform destroy -auto-approve || true
fi
```

**Docker build cache issues:**

```bash
# Option to force rebuild with --rebuild flag
if [[ "$FORCE_REBUILD" == "true" ]]; then
  docker build --no-cache -t ghcr.io/johnstrunk/agent-container \
    -f container/Dockerfile .
fi
```

**Claude response contains extra text:**

```bash
# Grep is flexible - just check phrase exists anywhere
if grep -q "All systems go!" /tmp/claude-response.txt; then
  # PASS - doesn't matter if Claude added politeness
fi
```

**cloud-init still running when SSH connects:**

```bash
# Explicit wait for cloud-init completion
ssh claude@vm 'cloud-init status --wait'
# Blocks until complete or timeout (120s)
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All tests passed |
| 1 | Test failure (Claude didn't respond, build failed, etc.) |
| 2 | Prerequisite validation failed (missing tools, credentials) |
| 3 | Invalid arguments |

### Verbose Output

All tests produce verbose timestamped output:

```text
[10:45:23] === Starting Container Integration Test ===
[10:45:23] [Container] Building image...
[10:47:45] [Container] Build complete (142s)
[10:47:45] [Container] Testing Claude Code in container...
[10:47:46] [Test] Sending prompt to Claude Code...
[10:47:52] [Test] ✓ Claude response validated
[10:47:52] [Test] Response: All systems go!
[10:47:52] Cleaning up container resources...
[10:47:52] === Container Test: PASS (149s) ===
```

On failure, show relevant context:

```text
[10:45:52] ERROR: Container test failed
[10:45:52] Last 50 lines of output:
[... output ...]
[10:45:52] Check credentials with:
[10:45:52]   gcloud auth application-default login
[10:45:52] Or set ANTHROPIC_API_KEY environment variable
```

## Implementation Requirements

### Changes to start-claude Script

The `common/homedir/.local/bin/start-claude` script needs modification to
support one-shot prompt execution:

**Current behavior:**

- Interactive shell that launches Claude Code CLI
- Sets up MCP servers and plugins on first run

**Required addition:**

```bash
# Add -p/--print flag support
if [[ "$1" == "-p" ]] || [[ "$1" == "--print" ]]; then
  shift
  # Pass prompt directly to claude
  exec claude -p "$*"
fi

# Otherwise, run interactive mode (existing behavior)
exec claude
```

Alternatively, the test can call `claude -p` directly if the binary is in
PATH.

### Documentation Updates

After implementation:

1. Update root `README.md` with integration test section
2. Update `container/CLAUDE.md` and `vm/CLAUDE.md` with testing guidance
3. Add integration test section to root `CLAUDE.md`

## Testing Strategy

### Manual Testing During Development

```bash
# Test container approach
./test-integration.sh --container

# Test VM approach
./test-integration.sh --vm

# Test both
./test-integration.sh --all

# Test with custom credentials
./test-integration.sh --container --gcp-credentials ~/test-sa.json
```

### When to Run

**Required:**

- Before committing changes to `common/homedir/` configs
- Before committing changes to `Dockerfile` or `entrypoint*.sh`
- Before committing changes to `main.tf` or `cloud-init.yaml.tftpl`
- Before releases

**Recommended:**

- After modifying credential injection logic
- After updating package lists in `common/packages/`
- When testing new Claude Code versions

### Future Enhancements (Out of Scope)

**Not included in initial implementation:**

- Multiple credential types in same test run
- Performance benchmarking (track timing trends)
- Testing multiple Claude Code models
- Testing Gemini CLI (focus on Claude Code first)
- CI integration (requires secure credential storage)
- Parallel test execution (container and VM simultaneously)
- Testing MCP servers and plugin installation

These can be added incrementally after initial implementation proves
valuable.

## Security Considerations

**Credentials:**

- Tests require real credentials (GCP service account or API keys)
- Never committed to git
- Same security model as production usage
- Ephemeral in container/VM (deleted on exit)

**Test isolation:**

- Each test run uses clean environment
- No cross-contamination between runs
- Safe to run on developer workstation

**Cleanup:**

- Always runs via trap EXIT
- Prevents resource leaks
- No manual cleanup required

## Success Criteria

**Implementation is successful when:**

1. `test-integration.sh --container` passes on clean checkout
2. `test-integration.sh --vm` passes on clean checkout
3. Both tests catch broken credential injection
4. Both tests catch broken config deployment
5. Tests complete in under 6 minutes (container) and 4 minutes (VM)
6. Cleanup always runs, no leftover resources
7. Clear error messages guide troubleshooting

## Appendix: Example Test Output

### Successful Container Test

```text
[10:45:23] === Starting Container Integration Test ===
[10:45:23] Validating prerequisites...
[10:45:23] ✓ Docker installed and running
[10:45:23] ✓ Credentials found: /home/user/.config/gcloud/application_default_credentials.json
[10:45:23] [Container] Building image...
[10:47:45] [Container] Build complete (142s)
[10:47:45] [Container] Testing Claude Code in container...
[10:47:46] [Test] Sending prompt to Claude Code...
[10:47:52] [Test] ✓ Claude response validated
[10:47:52] [Test] Response: All systems go!
[10:47:52] Cleaning up container resources...
[10:47:52] === Container Test: PASS (149s) ===
```

### Successful VM Test

```text
[10:50:00] === Starting VM Integration Test ===
[10:50:00] Validating prerequisites...
[10:50:00] ✓ Terraform installed
[10:50:00] ✓ libvirt accessible
[10:50:00] ✓ Credentials found
[10:50:00] [VM] Checking for existing VM...
[10:50:01] [VM] Provisioning VM with Terraform...
[10:51:23] [VM] VM provisioned (83s)
[10:51:23] [VM] Waiting for cloud-init to complete...
[10:51:45] [VM] cloud-init complete
[10:51:45] [VM] Testing Claude Code...
[10:51:46] [Test] Sending prompt to Claude Code...
[10:51:52] [Test] ✓ Claude response validated
[10:51:52] [Test] Response: All systems go!
[10:51:52] Cleaning up VM...
[10:52:15] [VM] Terraform destroy complete
[10:52:15] === VM Test: PASS (135s) ===
```

### Failed Test (Missing Credentials)

```text
[10:55:00] === Starting Container Integration Test ===
[10:55:00] Validating prerequisites...
[10:55:00] ✓ Docker installed and running
[10:55:00] ERROR: No credentials found. Need at least one of:
[10:55:00]   - GCP credentials: gcloud auth application-default login
[10:55:00]   - ANTHROPIC_API_KEY environment variable
[10:55:00]   - GEMINI_API_KEY environment variable
[10:55:00] === Prerequisite validation failed ===
```

### Failed Test (Claude Error)

```text
[11:00:00] === Starting Container Integration Test ===
[11:00:00] Validating prerequisites...
[11:00:00] ✓ Docker installed and running
[11:00:00] ✓ Credentials found
[11:00:00] [Container] Building image...
[11:02:15] [Container] Build complete (135s)
[11:02:15] [Container] Testing Claude Code in container...
[11:02:16] [Test] Sending prompt to Claude Code...
[11:02:17] ERROR: Claude did not respond within timeout
[11:02:17] Last output:
[11:02:17] Error: Invalid credentials format
[11:02:17] Check credentials with:
[11:02:17]   gcloud auth application-default login
[11:02:17] Or set ANTHROPIC_API_KEY environment variable
[11:02:17] Cleaning up container resources...
[11:02:17] === Container Test: FAIL (137s) ===
```
