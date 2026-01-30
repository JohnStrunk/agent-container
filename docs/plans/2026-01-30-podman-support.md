# Podman Support Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task.

**Goal:** Add Podman support alongside Docker for both agent-container
runtime and agent-vm nested containerization.

**Architecture:** Create container runtime abstraction layer that detects
and uses either Docker or Podman. Support both runtimes in parallel without
breaking existing Docker workflows. Add Podman to VM package lists for
nested containerization support.

**Tech Stack:** Bash scripting, Podman CLI (Docker-compatible API), Docker
CLI, Debian package management, Terraform cloud-init templates

---

## Task 1: Create Container Runtime Detection Library

**Files:**

- Create: `container/lib/container-runtime.sh`

**Step 1: Write container runtime detection function**

Create the runtime detection library with Docker/Podman auto-detection:

```bash
#!/bin/bash
# Container runtime abstraction layer
# Detects and uses Docker or Podman

set -e -o pipefail

# Detect available container runtime
# Returns: "docker" or "podman" or exits with error
detect_runtime() {
    local runtime=""

    # Check CONTAINER_RUNTIME environment variable first
    if [[ -n "${CONTAINER_RUNTIME:-}" ]]; then
        runtime="$CONTAINER_RUNTIME"
        if ! command -v "$runtime" &>/dev/null; then
            echo "ERROR: CONTAINER_RUNTIME=$runtime but $runtime not found" >&2
            exit 1
        fi
        echo "$runtime"
        return 0
    fi

    # Auto-detect: prefer Docker for backwards compatibility
    if command -v docker &>/dev/null; then
        runtime="docker"
    elif command -v podman &>/dev/null; then
        runtime="podman"
    else
        echo "ERROR: No container runtime found (docker or podman)" >&2
        echo "Install one of:" >&2
        echo "  - Docker: https://docs.docker.com/engine/install/" >&2
        echo "  - Podman: https://podman.io/getting-started/installation" >&2
        exit 1
    fi

    echo "$runtime"
}

# Get runtime-specific flags for build command
# Args: $1 = runtime (docker/podman)
get_build_flags() {
    local runtime="$1"
    case "$runtime" in
        docker)
            # Docker build flags (empty for now, reserved for future use)
            echo ""
            ;;
        podman)
            # Podman build flags
            # --format docker: Use Docker image format for compatibility
            echo "--format docker"
            ;;
        *)
            echo "ERROR: Unknown runtime: $runtime" >&2
            exit 1
            ;;
    esac
}

# Get runtime-specific flags for run command
# Args: $1 = runtime (docker/podman)
get_run_flags() {
    local runtime="$1"
    case "$runtime" in
        docker)
            # Docker run flags (empty for now)
            echo ""
            ;;
        podman)
            # Podman run flags
            # --userns=keep-id: Map container user to host user (rootless)
            # Note: Only use for rootless podman, not for root podman
            if [[ "${EUID:-$(id -u)}" != "0" ]]; then
                echo "--userns=keep-id"
            else
                echo ""
            fi
            ;;
        *)
            echo "ERROR: Unknown runtime: $runtime" >&2
            exit 1
            ;;
    esac
}

# Validate runtime is accessible and working
# Args: $1 = runtime (docker/podman)
validate_runtime() {
    local runtime="$1"

    if ! command -v "$runtime" &>/dev/null; then
        echo "ERROR: $runtime not found in PATH" >&2
        return 1
    fi

    # Check runtime daemon/service is accessible
    if ! "$runtime" info &>/dev/null; then
        echo "ERROR: $runtime daemon not running or not accessible" >&2
        if [[ "$runtime" == "docker" ]]; then
            echo "  Start with: sudo systemctl start docker" >&2
        elif [[ "$runtime" == "podman" ]]; then
            echo "  Podman can run rootless (no daemon needed)" >&2
            echo "  Check permissions or try: systemctl --user start podman" >&2
        fi
        return 1
    fi

    return 0
}
```

**Step 2: Verify library syntax**

Run shellcheck on the new library file:

```bash
pre-commit run shellcheck --files container/lib/container-runtime.sh
```

Expected: PASS (no shellcheck errors)

**Step 3: Commit runtime detection library**

```bash
git add container/lib/container-runtime.sh
git commit -m "$(cat <<'EOF'
feat: add container runtime detection library

Create abstraction layer to support both Docker and Podman:
- Auto-detect available runtime (Docker preferred for compatibility)
- Support CONTAINER_RUNTIME env var for manual override
- Runtime-specific build and run flags
- Validation to ensure runtime is accessible

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Update agent-container Script for Runtime Abstraction

**Files:**

- Modify: `container/agent-container:1-216`

**Step 1: Source runtime detection library**

Add library sourcing after shebang and before functions:

```bash
#!/bin/bash

set -e -o pipefail

# Source container runtime detection library
SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
# shellcheck source=container/lib/container-runtime.sh
source "$SCRIPT_DIR/lib/container-runtime.sh"
```

**Step 2: Detect runtime early in script**

Add runtime detection after argument parsing (after line 101):

```bash
# Detect container runtime
CONTAINER_RUNTIME=$(detect_runtime)
if ! validate_runtime "$CONTAINER_RUNTIME"; then
    exit 1
fi
echo "Using container runtime: $CONTAINER_RUNTIME"
```

**Step 3: Update build_image function**

Replace hardcoded `docker build` with runtime variable:

```bash
function build_image {
    echo "Building agent container image from $SCRIPT_DIR ..."
    local build_flags
    build_flags=$(get_build_flags "$CONTAINER_RUNTIME")
    # shellcheck disable=SC2086
    $CONTAINER_RUNTIME build $build_flags -t "$IMAGE_NAME" \
        -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR/.."
}
```

**Step 4: Update docker run command**

Replace `docker run` with runtime variable and runtime-specific flags
(around line 199):

```bash
# Build environment variable flags from common list
ENVVAR_FLAGS=()
ENVVARS_FILE="$SCRIPT_DIR/../common/packages/envvars.txt"
if [[ -f "$ENVVARS_FILE" ]]; then
    while IFS= read -r var || [[ -n "$var" ]]; do
        # Skip empty lines and comments
        [[ -z "$var" || "$var" =~ ^# ]] && continue
        ENVVAR_FLAGS+=(-e "$var")
    done < "$ENVVARS_FILE"
fi

# Get runtime-specific run flags
RUNTIME_FLAGS=()
runtime_flags_str=$(get_run_flags "$CONTAINER_RUNTIME")
if [[ -n "$runtime_flags_str" ]]; then
    read -ra RUNTIME_FLAGS <<< "$runtime_flags_str"
fi

$CONTAINER_RUNTIME run --rm "${TTY_FLAGS[@]}" \
    --name "$CONTANIER_NAME" \
    --hostname "$CONTANIER_NAME" \
    "${MOUNT_ARGS[@]}" \
    "${RUNTIME_FLAGS[@]}" \
    -w "$WORKTREE_DIR" \
    -e EUID="$(id -u)" \
    -e EGID="$(id -g)" \
    -e HOME="$HOME" \
    -e USER="$USER" \
    "${CREDENTIAL_ARGS[@]}" \
    "${ENVVAR_FLAGS[@]}" \
    ghcr.io/johnstrunk/agent-container:latest "${CONTAINER_COMMAND[@]}"
```

**Step 5: Update help text**

Update usage function to document CONTAINER_RUNTIME env var:

```bash
Environment Variables:
  CONTAINER_RUNTIME          Container runtime to use (docker or podman)
                            (auto-detected if not set, prefers docker)
  ANTHROPIC_API_KEY          Anthropic API key for Claude
  ANTHROPIC_MODEL            Model to use (default: claude-3-5-sonnet-20241022)
  GEMINI_API_KEY             Google Gemini API key
  (See README.md for complete list)
```

**Step 6: Update storage help text**

Update cache volume reference in usage function:

```bash
Storage:
  * Worktrees are stored in $WORKTREE_BASE_DIR
  * Cache volume: <runtime> volume ls | grep agent-container-cache
  * Clear cache: <runtime> volume rm agent-container-cache
```

**Step 7: Run shellcheck**

```bash
pre-commit run shellcheck --files container/agent-container
```

Expected: PASS (no shellcheck errors)

**Step 8: Commit agent-container updates**

```bash
git add container/agent-container
git commit -m "$(cat <<'EOF'
feat: add runtime abstraction to agent-container

Update agent-container to use runtime detection library:
- Auto-detect Docker or Podman (Docker preferred)
- Support CONTAINER_RUNTIME env var override
- Apply runtime-specific build and run flags
- Update help text with runtime information

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Update Integration Tests for Multi-Runtime Support

**Files:**

- Modify: `test-integration.sh:1-553`

**Step 1: Add runtime detection to integration tests**

Add runtime detection after argument parsing (after line 126):

```bash
parse_args "$@"

# Detect container runtime for container tests
if [[ "$TEST_TYPE" == "container" ]] || [[ "$TEST_TYPE" == "all" ]]; then
    # Source runtime detection from container/lib
    SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
    # shellcheck source=container/lib/container-runtime.sh
    source "$SCRIPT_DIR/container/lib/container-runtime.sh"

    CONTAINER_RUNTIME=$(detect_runtime)
    log "Detected container runtime: $CONTAINER_RUNTIME"
fi
```

**Step 2: Update validate_prerequisites function**

Replace hardcoded `docker` checks with runtime variable (around line 134):

```bash
# Check Docker/Podman for container tests
if [[ "$TEST_TYPE" == "container" ]] || [[ "$TEST_TYPE" == "all" ]]; then
    if ! command -v docker &>/dev/null && \
       ! command -v podman &>/dev/null; then
        log_error "No container runtime found (docker or podman)"
        log_error "  Install Docker: https://docs.docker.com/engine/install/"
        log_error "  Install Podman: https://podman.io/getting-started/installation"
        ((errors++))
    elif [[ -n "${CONTAINER_RUNTIME:-}" ]]; then
        if ! validate_runtime "$CONTAINER_RUNTIME"; then
            ((errors++))
        else
            log "✓ $CONTAINER_RUNTIME installed and running"
        fi
    fi
fi
```

**Step 3: Update test_container function**

Replace hardcoded `docker build` with runtime variable (around line 293):

```bash
# Step 1: Build image
log "[Container] Building image with $CONTAINER_RUNTIME..."
local build_cmd=("$CONTAINER_RUNTIME" build -t ghcr.io/johnstrunk/agent-container
                 -f container/Dockerfile .)

# Add runtime-specific build flags
local build_flags
build_flags=$(get_build_flags "$CONTAINER_RUNTIME")
if [[ -n "$build_flags" ]]; then
    read -ra build_flags_array <<< "$build_flags"
    build_cmd+=("${build_flags_array[@]}")
fi

if [[ "$FORCE_REBUILD" == "true" ]]; then
    log "[Container] Force rebuild enabled (--no-cache)"
    build_cmd+=(--no-cache)
fi
```

**Step 4: Run shellcheck on test script**

```bash
pre-commit run shellcheck --files test-integration.sh
```

Expected: PASS (no shellcheck errors)

**Step 5: Commit integration test updates**

```bash
git add test-integration.sh
git commit -m "$(cat <<'EOF'
feat: add multi-runtime support to integration tests

Update integration tests to work with Docker or Podman:
- Auto-detect available runtime
- Validate runtime before running tests
- Use runtime-specific build flags
- Log which runtime is being tested

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add Podman to VM Package Lists

**Files:**

- Modify: `vm/cloud-init.yaml.tftpl:210`

**Step 1: Add podman package to cloud-init**

Replace `docker.io` with both Docker and Podman:

```yaml
  # VM-specific packages for nested virtualization
  - docker.io
  - podman
  - qemu-system-x86
  - qemu-guest-agent
  - libvirt-daemon-system
```

**Step 2: Add podman group membership**

Add user to podman group after Docker group (after line 65):

```yaml
  # Add user to docker group for container access
  - usermod -aG docker ${default_user}
  # Add user to podman group (if it exists)
  - getent group podman && usermod -aG podman ${default_user} || true
```

**Step 3: Validate Terraform configuration**

```bash
cd vm
terraform fmt
terraform validate
```

Expected: Success (no validation errors)

**Step 4: Commit cloud-init changes**

```bash
git add vm/cloud-init.yaml.tftpl
git commit -m "$(cat <<'EOF'
feat: add Podman support to agent-vm

Install Podman alongside Docker in agent-vm:
- Add podman to apt package list
- Add user to podman group for rootless access
- Enables testing Podman-based projects in VM

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Update Documentation for Podman Support

**Files:**

- Modify: `container/README.md`
- Modify: `container/CLAUDE.md`
- Modify: `vm/README.md`
- Modify: `vm/CLAUDE.md`
- Modify: `README.md`

**Step 1: Update container/README.md**

Add Podman support section after Docker installation section:

```markdown
## Prerequisites

### Container Runtime

You need either Docker or Podman installed:

**Docker (recommended for compatibility):**

- [Install Docker Engine](https://docs.docker.com/engine/install/)
- Add user to docker group: `sudo usermod -aG docker $USER`
- Log out and back in for group changes to take effect

**Podman (alternative):**

- [Install Podman](https://podman.io/getting-started/installation)
- Works rootless by default (no daemon required)
- Debian: `sudo apt-get install -y podman`

The `agent-container` script auto-detects which runtime is available,
preferring Docker for backwards compatibility. Override with:

```bash
CONTAINER_RUNTIME=podman ./agent-container -b feature-name
```

### Other Requirements

- Git (for worktree management)
- Bash 4.0+
```

**Step 2: Update container/CLAUDE.md**

Add runtime detection to Key Technologies section:

```markdown
### Container Environment

- **Base**: Debian 13 slim
- **Runtime**: Docker or Podman (auto-detected)
- **AI Agents**: Claude Code, Gemini CLI (installed via npm)
```

Add to Environment Variables section:

```markdown
### Container Runtime

- `CONTAINER_RUNTIME` - Force specific runtime (docker or podman)
  - Default: Auto-detect (prefers docker)
  - Override: `CONTAINER_RUNTIME=podman ./agent-container -b feature`
```

**Step 3: Update vm/README.md**

Add to Prerequisites section:

```markdown
The VM includes both Docker and Podman for testing container-based
projects. Use either runtime within the VM:

```bash
# Use Docker (default)
docker run hello-world

# Use Podman
podman run hello-world
```

**Step 4: Update vm/CLAUDE.md**

Add to Key Technologies section:

```markdown
- **Development Tools**: Git, Node.js, Python, Go, Docker, Podman,
  Terraform
```

**Step 5: Update root README.md**

Add to Features section for container approach:

```markdown
### Container Approach Features

- **Fast startup**: ~2 seconds from command to shell
- **Multi-runtime**: Works with Docker or Podman
- **Git worktree integration**: One container per branch
```

Add to Prerequisites section:

```markdown
## Prerequisites

### Container Approach

- Docker or Podman
- Git
- Bash 4.0+

See [container/README.md](container/README.md) for detailed installation.
```

**Step 6: Run markdownlint on all updated files**

```bash
pre-commit run markdownlint --files container/README.md
pre-commit run markdownlint --files container/CLAUDE.md
pre-commit run markdownlint --files vm/README.md
pre-commit run markdownlint --files vm/CLAUDE.md
pre-commit run markdownlint --files README.md
```

Expected: PASS (all markdown files pass linting)

**Step 7: Commit documentation updates**

```bash
git add container/README.md container/CLAUDE.md vm/README.md vm/CLAUDE.md README.md
git commit -m "$(cat <<'EOF'
docs: add Podman support documentation

Document Podman support across all READMEs:
- Container runtime auto-detection
- CONTAINER_RUNTIME environment variable
- Podman installation instructions
- VM includes both Docker and Podman

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Add CI/CD Support for Podman

**Files:**

- Modify: `.github/workflows/ci-workflow.yaml:66-88`

**Step 1: Add Podman installation to devcontainer job**

Add step to install Podman before building devcontainer:

```yaml
  devcontainer:
    name: "Build devcontainer image"
    runs-on: ubuntu-latest

    steps:
      - name: Checkout repository
        # https://github.com/actions/checkout
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

      - name: Install Podman
        run: |
          sudo apt-get update
          sudo apt-get install -y podman

      - name: Set up Docker Buildx
        # https://github.com/docker/setup-buildx-action
        uses: docker/setup-buildx-action@8d2750c68a42422c14e847fe6c8ac0403b4cbd6f # v3.12.0
        id: setup-buildx

      - name: Expose variables required for actions cache
        # https://github.com/crazy-max/ghaction-github-runtime
        uses: crazy-max/ghaction-github-runtime@3cb05d89e1f492524af3d41a1c98c83bc3025124 # v3.1.0

      - name: Build devcontainer with Docker
        run: npx -- @devcontainers/cli build --workspace-folder . --cache-from type=gha,scope=devcontainer --cache-to type=gha,mode=min,scope=devcontainer

      - name: Build image with Podman
        run: |
          cd container
          source lib/container-runtime.sh
          CONTAINER_RUNTIME=podman
          build_flags=$(get_build_flags "$CONTAINER_RUNTIME")
          # shellcheck disable=SC2086
          podman build $build_flags -t ghcr.io/johnstrunk/agent-container \
            -f Dockerfile ..
```

**Step 2: Run yamllint on workflow file**

```bash
pre-commit run yamllint --files .github/workflows/ci-workflow.yaml
```

Expected: PASS (no YAML linting errors)

**Step 3: Commit CI workflow updates**

```bash
git add .github/workflows/ci-workflow.yaml
git commit -m "$(cat <<'EOF'
ci: add Podman build validation to CI

Add Podman-specific build step to CI workflow:
- Install Podman on Ubuntu runner
- Build image with Podman to verify compatibility
- Validate both Docker and Podman work in CI

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Add Podman Testing Documentation

**Files:**

- Create: `docs/plans/2026-01-30-podman-testing-guide.md`

**Step 1: Write testing guide**

Create comprehensive testing guide for Podman support:

```markdown
# Podman Testing Guide

## Overview

This document describes how to test Podman support for the
agent-container project.

## Testing Prerequisites

- Podman installed and accessible
- No Docker installed (for pure Podman testing)
- OR both Docker and Podman (for multi-runtime testing)

## Test Scenarios

### Scenario 1: Pure Podman (No Docker)

**Environment:**

- Podman installed
- Docker NOT installed

**Test Steps:**

1. Verify Podman is detected:

   ```bash
   cd container
   source lib/container-runtime.sh
   detect_runtime
   # Expected output: podman
   ```

2. Build image with Podman:

   ```bash
   ./agent-container -b test-podman
   # Expected: Image builds with Podman
   ```

3. Run container:

   ```bash
   ./agent-container -b test-podman -- echo "Hello from Podman"
   # Expected: "Hello from Podman" printed
   ```

4. Run integration tests:

   ```bash
   cd ..
   ./test-integration.sh --container
   # Expected: PASS
   ```

### Scenario 2: Docker Preferred (Both Installed)

**Environment:**

- Both Docker and Podman installed

**Test Steps:**

1. Verify Docker is preferred:

   ```bash
   cd container
   source lib/container-runtime.sh
   detect_runtime
   # Expected output: docker
   ```

2. Override to use Podman:

   ```bash
   CONTAINER_RUNTIME=podman ./agent-container -b test-override
   # Expected: Uses Podman
   ```

### Scenario 3: VM Nested Containerization

**Environment:**

- agent-vm with both Docker and Podman

**Test Steps:**

1. Create VM workspace:

   ```bash
   cd vm
   ./agent-vm -b test-podman
   ```

2. Test Docker inside VM:

   ```bash
   docker run hello-world
   # Expected: Success
   ```

3. Test Podman inside VM:

   ```bash
   podman run hello-world
   # Expected: Success
   ```

4. Test Podman project workflow:

   ```bash
   # Clone a Podman-based project
   git clone https://github.com/example/podman-project
   cd podman-project
   podman build -t test .
   # Expected: Build succeeds
   ```

## Troubleshooting

### Podman Permission Denied

**Symptom:** `permission denied while trying to connect to the Podman socket`

**Solution:**

```bash
# Enable rootless Podman
systemctl --user enable --now podman.socket

# Or run as root (not recommended)
sudo podman ...
```

### Podman Image Format Issues

**Symptom:** Image built with Podman not compatible with Docker

**Solution:** Library automatically adds `--format docker` for Podman builds

### User Namespace Mapping Issues

**Symptom:** File permission errors in Podman containers

**Solution:** Library automatically adds `--userns=keep-id` for rootless
Podman

## Validation Checklist

- [ ] Podman-only environment works
- [ ] Docker-only environment works
- [ ] Both runtimes work with auto-detection
- [ ] CONTAINER_RUNTIME override works
- [ ] Integration tests pass with Podman
- [ ] VM has both Docker and Podman
- [ ] Documentation is accurate and complete
```

**Step 2: Run markdownlint**

```bash
pre-commit run markdownlint --files docs/plans/2026-01-30-podman-testing-guide.md
```

Expected: PASS

**Step 3: Commit testing guide**

```bash
git add docs/plans/2026-01-30-podman-testing-guide.md
git commit -m "$(cat <<'EOF'
docs: add Podman testing guide

Create comprehensive testing guide for Podman support:
- Pure Podman testing (no Docker)
- Multi-runtime testing (both installed)
- VM nested containerization testing
- Troubleshooting common issues

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Run Final Pre-commit and Integration Tests

**Files:**

- All modified files

**Step 1: Run pre-commit on all files**

```bash
pre-commit run --all-files
```

Expected: PASS (all hooks pass)

**Step 2: Fix any pre-commit issues**

If pre-commit finds issues:

```bash
# Review failed hooks
# Fix issues manually or with auto-fixes
# Re-run pre-commit
pre-commit run --all-files
```

Expected: PASS (all hooks pass after fixes)

**Step 3: Run container integration tests with Docker**

```bash
./test-integration.sh --container
```

Expected: PASS (all container tests pass with Docker)

**Step 4: Run container integration tests with Podman (if available)**

```bash
CONTAINER_RUNTIME=podman ./test-integration.sh --container
```

Expected: PASS (all container tests pass with Podman)

**Step 5: Create final summary commit**

```bash
git commit --allow-empty -m "$(cat <<'EOF'
feat: complete Podman support implementation

Summary of changes:
- Created container runtime abstraction library
- Updated agent-container for multi-runtime support
- Updated integration tests for Docker/Podman
- Added Podman to agent-vm package lists
- Updated all documentation
- Added CI validation for Podman builds
- Created comprehensive testing guide

Both Docker and Podman are now fully supported for:
- agent-container runtime (auto-detected)
- agent-vm nested containerization
- CI/CD validation

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Implementation Notes

### Design Decisions

1. **Backwards Compatibility**: Auto-detection prefers Docker to avoid
   breaking existing workflows
2. **Runtime Abstraction**: Library pattern allows future runtime additions
   (e.g., containerd, nerdctl)
3. **Explicit Overrides**: CONTAINER_RUNTIME env var for manual control
4. **VM Approach**: Both runtimes installed for maximum flexibility in
   testing

### Testing Strategy

1. Pre-commit validation after each task
2. Incremental integration testing (per component)
3. Final end-to-end validation with both runtimes
4. CI validation ensures both runtimes work

### Rollback Plan

If issues arise:

1. Each task is committed separately
2. Use `git revert` to undo specific commits
3. Library abstraction allows disabling Podman without removing code

### Future Enhancements

- Add support for other runtimes (containerd, nerdctl)
- Add runtime-specific performance optimizations
- Add runtime selection to agent-container CLI flags
- Consider Podman-specific features (pods, systemd integration)
