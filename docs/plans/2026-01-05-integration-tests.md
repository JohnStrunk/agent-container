# Integration Tests Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task.

**Goal:** Implement end-to-end integration tests that validate AI assistants
can start and operate correctly after repository changes, catching credential
injection and configuration deployment failures.

**Architecture:** Single bash script (`test-integration.sh`) at repository
root that runs full lifecycle tests (build/provision → test Claude Code →
cleanup) for both container and VM approaches. Uses real credentials, verbose
logging, and deterministic validation via one-shot Claude prompt.

**Tech Stack:** Bash, Docker, Terraform, Claude Code CLI, trap handlers,
timeout command

---

## Task 1: Create Test Script Foundation

**Files:**

- Create: `test-integration.sh`

**Step 1: Create test script with shebang and basic structure**

Create `test-integration.sh`:

```bash
#!/bin/bash

set -e -o pipefail

# Script version
VERSION="1.0.0"

# Default paths
GCP_CREDS_DEFAULT="$HOME/.config/gcloud/application_default_credentials.json"
GCP_CREDS_PATH=""

# Test configuration
TEST_TYPE=""
FORCE_REBUILD=false

# Exit codes
EXIT_SUCCESS=0
EXIT_TEST_FAILED=1
EXIT_PREREQ_FAILED=2
EXIT_INVALID_ARGS=3

# Placeholder for main function
main() {
    echo "Integration tests - placeholder"
}

main "$@"
```

**Step 2: Make script executable**

Run: `chmod +x test-integration.sh`

Expected: File is now executable

**Step 3: Test basic script execution**

Run: `./test-integration.sh`

Expected output: `Integration tests - placeholder`

**Step 4: Commit foundation**

```bash
git add test-integration.sh
git commit -m "feat: add integration test script foundation

Add basic structure for integration tests with exit codes and default
configuration. Script is executable but not yet functional.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Implement Logging Functions

**Files:**

- Modify: `test-integration.sh`

**Step 1: Add logging helper functions**

Add after exit codes, before main function in `test-integration.sh`:

```bash
# Logging functions with timestamps
log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

log_step() {
    echo ""
    echo "[$(date '+%H:%M:%S')] === $* ==="
    echo ""
}

log_error() {
    echo "[$(date '+%H:%M:%S')] ERROR: $*" >&2
}
```

**Step 2: Update main to use logging**

Replace main function:

```bash
main() {
    log_step "Integration Tests v${VERSION}"
    log "Placeholder for tests"
}
```

**Step 3: Test logging output**

Run: `./test-integration.sh`

Expected output with timestamps:

```text
[HH:MM:SS] === Integration Tests v1.0.0 ===
[HH:MM:SS] Placeholder for tests
```

**Step 4: Commit logging functions**

```bash
git add test-integration.sh
git commit -m "feat: add timestamped logging functions

Add log(), log_step(), and log_error() helper functions with timestamp
formatting for test output.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Implement CLI Argument Parsing

**Files:**

- Modify: `test-integration.sh`

**Step 1: Add usage function**

Add before main function:

```bash
usage() {
    cat <<EOF
Integration Tests for AI Development Environments

Usage: $0 [options] <--container|--vm|--all>

Options:
  --container                Run container approach test
  --vm                       Run VM approach test
  --all                      Run both tests sequentially
  --gcp-credentials <path>   Path to GCP credentials JSON file
                            (default: ~/.config/gcloud/application_default_credentials.json)
  --rebuild                  Force rebuild (bypass Docker cache)
  -h, --help                 Show this help

Examples:
  $0 --container
  $0 --vm
  $0 --all
  $0 --container --gcp-credentials ~/my-creds.json

Exit Codes:
  0 - All tests passed
  1 - Test failure
  2 - Prerequisite validation failed
  3 - Invalid arguments
EOF
}
```

**Step 2: Add argument parsing**

Add before main function:

```bash
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --container)
                TEST_TYPE="container"
                shift
                ;;
            --vm)
                TEST_TYPE="vm"
                shift
                ;;
            --all)
                TEST_TYPE="all"
                shift
                ;;
            --gcp-credentials)
                GCP_CREDS_PATH="$2"
                shift 2
                ;;
            --rebuild)
                FORCE_REBUILD=true
                shift
                ;;
            -h|--help)
                usage
                exit "$EXIT_SUCCESS"
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit "$EXIT_INVALID_ARGS"
                ;;
        esac
    done

    # Validate required arguments
    if [[ -z "$TEST_TYPE" ]]; then
        log_error "Must specify --container, --vm, or --all"
        usage
        exit "$EXIT_INVALID_ARGS"
    fi

    # Set default credentials path if not provided
    if [[ -z "$GCP_CREDS_PATH" ]]; then
        GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
    fi
}
```

**Step 3: Update main to call parse_args**

Replace main function:

```bash
main() {
    parse_args "$@"

    log_step "Integration Tests v${VERSION}"
    log "Test type: $TEST_TYPE"
    log "GCP credentials: $GCP_CREDS_PATH"
    log "Force rebuild: $FORCE_REBUILD"
}
```

**Step 4: Test argument parsing**

Run: `./test-integration.sh --help`

Expected: Shows usage information

Run: `./test-integration.sh --container`

Expected: Shows test type as "container"

Run: `./test-integration.sh`

Expected: Error message about missing test type, then usage

**Step 5: Commit argument parsing**

```bash
git add test-integration.sh
git commit -m "feat: add CLI argument parsing and usage

Implement argument parsing for --container, --vm, --all, and credential
options. Add usage documentation and validation.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Implement Prerequisite Validation

**Files:**

- Modify: `test-integration.sh`

**Step 1: Add prerequisite validation function**

Add before main function:

```bash
validate_prerequisites() {
    local errors=0

    log "Validating prerequisites..."

    # Check Docker for container tests
    if [[ "$TEST_TYPE" == "container" ]] || [[ "$TEST_TYPE" == "all" ]]; then
        if ! command -v docker &>/dev/null; then
            log_error "docker not found. Install Docker first."
            ((errors++))
        elif ! docker info &>/dev/null; then
            log_error "Docker daemon not running"
            log_error "  Start with: sudo systemctl start docker"
            ((errors++))
        else
            log "✓ Docker installed and running"
        fi
    fi

    # Check Terraform and libvirt for VM tests
    if [[ "$TEST_TYPE" == "vm" ]] || [[ "$TEST_TYPE" == "all" ]]; then
        if ! command -v terraform &>/dev/null; then
            log_error "terraform not found. Install Terraform first."
            ((errors++))
        else
            log "✓ Terraform installed"
        fi

        if ! virsh list &>/dev/null 2>&1; then
            log_error "libvirt not accessible"
            log_error "  Check: sudo systemctl status libvirtd"
            ((errors++))
        else
            log "✓ libvirt accessible"
        fi
    fi

    # Check credentials
    local has_credentials=false

    if [[ -f "$GCP_CREDS_PATH" ]]; then
        log "✓ GCP credentials found: $GCP_CREDS_PATH"
        has_credentials=true
    fi

    if [[ -n "$ANTHROPIC_API_KEY" ]]; then
        log "✓ ANTHROPIC_API_KEY environment variable set"
        has_credentials=true
    fi

    if [[ -n "$GEMINI_API_KEY" ]]; then
        log "✓ GEMINI_API_KEY environment variable set"
        has_credentials=true
    fi

    if [[ "$has_credentials" == "false" ]]; then
        log_error "No credentials found. Need at least one of:"
        log_error "  - GCP credentials file at: $GCP_CREDS_PATH"
        log_error "    Run: gcloud auth application-default login"
        log_error "  - ANTHROPIC_API_KEY environment variable"
        log_error "  - GEMINI_API_KEY environment variable"
        ((errors++))
    fi

    return $errors
}
```

**Step 2: Update main to call validation**

Replace main function:

```bash
main() {
    parse_args "$@"

    log_step "Integration Tests v${VERSION}"

    if ! validate_prerequisites; then
        log_error "Prerequisite validation failed"
        exit "$EXIT_PREREQ_FAILED"
    fi

    log "All prerequisites validated"
}
```

**Step 3: Test prerequisite validation (should fail without Docker)**

Run: `./test-integration.sh --container`

Expected: If Docker not running, shows error and exits with code 2

**Step 4: Test with credentials check**

Run: `./test-integration.sh --container --gcp-credentials /nonexistent/path`

Expected: Error about missing credentials

**Step 5: Commit prerequisite validation**

```bash
git add test-integration.sh
git commit -m "feat: add prerequisite validation

Validate Docker, Terraform, libvirt, and credentials before running tests.
Provide clear error messages with remediation steps.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Implement Cleanup Handlers

**Files:**

- Modify: `test-integration.sh`

**Step 1: Add cleanup functions**

Add after validate_prerequisites function:

```bash
cleanup_container() {
    log "Cleaning up container resources..."
    # Docker handles cleanup via --rm flag, nothing to do
    log "Container cleanup complete"
}

cleanup_vm() {
    log "Cleaning up VM..."
    if [[ -d vm ]] && [[ -f vm/main.tf ]]; then
        cd vm || return
        if terraform state list 2>/dev/null | grep -q .; then
            terraform destroy -auto-approve \
                -var="user_uid=$(id -u)" \
                -var="user_gid=$(id -g)" 2>&1 | \
                grep -v "^$" || true
        else
            log "No VM to clean up"
        fi
        cd .. || return
    fi
    log "VM cleanup complete"
}

cleanup_all() {
    local exit_code=$?

    echo ""
    log "Running cleanup..."

    if [[ "$TEST_TYPE" == "container" ]] || [[ "$TEST_TYPE" == "all" ]]; then
        cleanup_container
    fi

    if [[ "$TEST_TYPE" == "vm" ]] || [[ "$TEST_TYPE" == "all" ]]; then
        cleanup_vm
    fi

    exit $exit_code
}
```

**Step 2: Add trap handler in main**

Update main function to add trap:

```bash
main() {
    parse_args "$@"

    # Set cleanup trap
    trap cleanup_all EXIT

    log_step "Integration Tests v${VERSION}"

    if ! validate_prerequisites; then
        log_error "Prerequisite validation failed"
        exit "$EXIT_PREREQ_FAILED"
    fi

    log "All prerequisites validated"
    log "Cleanup handlers registered"
}
```

**Step 3: Test cleanup (should run on exit)**

Run: `./test-integration.sh --container`

Expected: Shows "Running cleanup..." and "Container cleanup complete" before
exit

**Step 4: Commit cleanup handlers**

```bash
git add test-integration.sh
git commit -m "feat: add cleanup handlers with trap EXIT

Implement cleanup_container(), cleanup_vm(), and cleanup_all() functions.
Register trap handler to ensure cleanup always runs on script exit.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Implement Claude Test Command Generator

**Files:**

- Modify: `test-integration.sh`

**Step 1: Add test command generator function**

Add after cleanup functions:

```bash
generate_test_command() {
    cat <<'EOF'
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
EOF
}
```

**Step 2: Add helper to run with timeout**

Add after generate_test_command:

```bash
run_with_timeout() {
    local timeout_seconds=$1
    shift
    timeout "$timeout_seconds" "$@"
}
```

**Step 3: Test command generation**

Run: `./test-integration.sh --container`

Expected: No errors (command not yet executed)

**Step 4: Commit test command generator**

```bash
git add test-integration.sh
git commit -m "feat: add Claude test command generator

Implement generate_test_command() that creates bash script for testing
Claude Code with one-shot prompt. Add run_with_timeout() helper.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Implement Container Test

**Files:**

- Modify: `test-integration.sh`

**Step 1: Add container test function**

Add after run_with_timeout:

```bash
test_container() {
    log_step "Starting Container Integration Test"
    local start_time
    start_time=$(date +%s)

    # Step 1: Build image
    log "[Container] Building image..."
    local build_cmd=(docker build -t ghcr.io/johnstrunk/agent-container
                     -f container/Dockerfile .)

    if [[ "$FORCE_REBUILD" == "true" ]]; then
        log "[Container] Force rebuild enabled (--no-cache)"
        build_cmd+=(--no-cache)
    fi

    if ! run_with_timeout 300 "${build_cmd[@]}"; then
        log_error "Container build failed"
        return 1
    fi

    local build_time
    build_time=$(($(date +%s) - start_time))
    log "[Container] Build complete (${build_time}s)"

    # Step 2: Run test in container
    log "[Container] Testing Claude Code in container..."

    local gcp_creds_arg=()
    if [[ -f "$GCP_CREDS_PATH" ]]; then
        gcp_creds_arg=(--gcp-credentials "$GCP_CREDS_PATH")
    fi

    if ! run_with_timeout 90 ./container/agent-container \
        "${gcp_creds_arg[@]}" \
        -- bash -c "$(generate_test_command)"; then
        log_error "Container test failed"
        return 1
    fi

    local total_time
    total_time=$(($(date +%s) - start_time))
    log_step "Container Test: PASS (${total_time}s)"
    return 0
}
```

**Step 2: Update main to call container test**

Update main function:

```bash
main() {
    parse_args "$@"

    # Set cleanup trap
    trap cleanup_all EXIT

    log_step "Integration Tests v${VERSION}"

    if ! validate_prerequisites; then
        log_error "Prerequisite validation failed"
        exit "$EXIT_PREREQ_FAILED"
    fi

    # Run tests based on type
    if [[ "$TEST_TYPE" == "container" ]]; then
        if ! test_container; then
            exit "$EXIT_TEST_FAILED"
        fi
    elif [[ "$TEST_TYPE" == "vm" ]]; then
        log "VM test not yet implemented"
        exit "$EXIT_TEST_FAILED"
    elif [[ "$TEST_TYPE" == "all" ]]; then
        if ! test_container; then
            exit "$EXIT_TEST_FAILED"
        fi
        log "VM test not yet implemented"
        exit "$EXIT_TEST_FAILED"
    fi

    log_step "All Tests Passed!"
    exit "$EXIT_SUCCESS"
}
```

**Step 3: Test container test (DRY RUN - do not actually run if no Docker)**

If Docker is available and you have credentials:

Run: `./test-integration.sh --container`

Expected: Builds container, runs Claude test, shows PASS or detailed error

**Step 4: Commit container test**

```bash
git add test-integration.sh
git commit -m "feat: implement container integration test

Add test_container() function that builds Docker image and tests Claude
Code with one-shot prompt. Includes timeout handling and timing output.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Implement VM Test

**Files:**

- Modify: `test-integration.sh`

**Step 1: Add VM test function**

Add after test_container:

```bash
test_vm() {
    log_step "Starting VM Integration Test"
    local start_time
    start_time=$(date +%s)

    # Change to vm directory
    cd vm || {
        log_error "vm directory not found"
        return 1
    }

    # Step 1: Check for existing VM and destroy it
    log "[VM] Checking for existing VM..."
    if terraform state list 2>/dev/null | grep -q libvirt_domain.agent_vm; then
        log "[VM] Found existing VM from previous test, destroying..."
        terraform destroy -auto-approve \
            -var="user_uid=$(id -u)" \
            -var="user_gid=$(id -g)" 2>&1 | \
            grep -v "^$" || true
    fi

    # Step 2: Provision VM
    log "[VM] Provisioning VM with Terraform..."

    # Set GCP credentials path if custom
    if [[ -n "$GCP_CREDS_PATH" ]] && [[ "$GCP_CREDS_PATH" != "$GCP_CREDS_DEFAULT" ]]; then
        export GCP_CREDENTIALS_PATH="$GCP_CREDS_PATH"
    fi

    if ! run_with_timeout 300 ./vm-up.sh; then
        log_error "VM provisioning failed"
        cd .. || return 1
        return 1
    fi

    local provision_time
    provision_time=$(($(date +%s) - start_time))
    log "[VM] VM provisioned (${provision_time}s)"

    # Step 3: Get VM IP
    local vm_ip
    vm_ip=$(terraform output -raw vm_ip 2>/dev/null || echo "")
    if [[ -z "$vm_ip" ]]; then
        log_error "Failed to get VM IP from terraform output"
        cd .. || return 1
        return 1
    fi

    log "[VM] VM IP: $vm_ip"

    # Step 4: Wait for cloud-init to complete
    log "[VM] Waiting for cloud-init to complete..."

    local ssh_opts=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
                    -o LogLevel=ERROR -i vm_ssh_key)

    if ! run_with_timeout 120 bash -c "
        while ! ssh ${ssh_opts[*]} claude@${vm_ip} \
            'cloud-init status --wait' 2>/dev/null; do
            sleep 5
        done
    "; then
        log_error "cloud-init failed or timed out"
        cd .. || return 1
        return 1
    fi

    log "[VM] cloud-init complete"

    # Step 5: Run Claude test via SSH
    log "[VM] Testing Claude Code in VM..."

    if ! run_with_timeout 90 ssh "${ssh_opts[@]}" "claude@${vm_ip}" \
        "bash -s" < <(generate_test_command); then
        log_error "Claude test failed in VM"
        cd .. || return 1
        return 1
    fi

    cd .. || return 1

    local total_time
    total_time=$(($(date +%s) - start_time))
    log_step "VM Test: PASS (${total_time}s)"
    return 0
}
```

**Step 2: Update main to call VM test**

Replace the VM test section in main:

```bash
    # Run tests based on type
    if [[ "$TEST_TYPE" == "container" ]]; then
        if ! test_container; then
            exit "$EXIT_TEST_FAILED"
        fi
    elif [[ "$TEST_TYPE" == "vm" ]]; then
        if ! test_vm; then
            exit "$EXIT_TEST_FAILED"
        fi
    elif [[ "$TEST_TYPE" == "all" ]]; then
        if ! test_container; then
            exit "$EXIT_TEST_FAILED"
        fi
        if ! test_vm; then
            exit "$EXIT_TEST_FAILED"
        fi
    fi
```

**Step 3: Test VM test (DRY RUN - do not actually run if no libvirt)**

If Terraform and libvirt are available:

Run: `./test-integration.sh --vm`

Expected: Provisions VM, waits for cloud-init, tests Claude, shows PASS

**Step 4: Commit VM test**

```bash
git add test-integration.sh
git commit -m "feat: implement VM integration test

Add test_vm() function that provisions VM via Terraform, waits for
cloud-init, and tests Claude Code via SSH. Includes cleanup of stale VMs.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 9: Add Shellcheck Compliance

**Files:**

- Modify: `test-integration.sh`

**Step 1: Run shellcheck and fix issues**

Run: `shellcheck test-integration.sh`

Expected: May show warnings about quoting, variable usage, etc.

**Step 2: Fix common shellcheck issues**

Common fixes needed:

- Quote variables: `"$var"` instead of `$var`
- Use `|| true` for commands that may fail
- Disable specific checks where needed with `# shellcheck disable=SC####`

Make fixes as needed based on shellcheck output.

**Step 3: Run shellcheck again**

Run: `shellcheck test-integration.sh`

Expected: No errors or warnings (or only disabled ones)

**Step 4: Commit shellcheck fixes**

```bash
git add test-integration.sh
git commit -m "fix: resolve shellcheck warnings

Fix quoting, variable usage, and other shellcheck warnings for
test-integration.sh script.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 10: Run Pre-commit Checks

**Files:**

- Modify: `test-integration.sh`

**Step 1: Run all pre-commit hooks on test script**

Run: `pre-commit run --files test-integration.sh`

Expected: All hooks pass (or show what needs fixing)

**Step 2: Fix any pre-commit issues**

Common issues:

- Trailing whitespace
- Missing final newline
- Shellcheck warnings

Make fixes as needed.

**Step 3: Run pre-commit again**

Run: `pre-commit run --files test-integration.sh`

Expected: All hooks pass

**Step 4: Commit pre-commit fixes (if any)**

```bash
git add test-integration.sh
git commit -m "fix: resolve pre-commit issues for test script

Fix trailing whitespace, line endings, and other pre-commit hook issues.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 11: Update Root README

**Files:**

- Modify: `README.md`

**Step 1: Read current README to understand structure**

Run: `cat README.md`

**Step 2: Add integration tests section**

Add after the main content (before any existing sections about
contributing/license):

```markdown
## Integration Tests

End-to-end tests that validate both container and VM environments can
successfully run AI assistants after repository changes.

**Requirements:**

- Valid credentials (GCP service account or API keys)
- Docker (for container tests) or Terraform + libvirt (for VM tests)

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
locally before committing changes to configs, Dockerfiles, or Terraform
files.

See `docs/plans/2026-01-05-integration-tests-design.md` for design details.
```

**Step 3: Run markdownlint on README**

Run: `pre-commit run markdownlint --files README.md`

Expected: May show line length or formatting issues

**Step 4: Fix markdownlint issues**

Fix any reported issues (typically line length > 80 chars)

**Step 5: Commit README update**

```bash
git add README.md
git commit -m "docs: add integration tests section to README

Document how to run integration tests and link to design document.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 12: Update Container CLAUDE.md

**Files:**

- Modify: `container/CLAUDE.md`

**Step 1: Read current container CLAUDE.md**

Run: `cat container/CLAUDE.md | head -50`

**Step 2: Add testing section**

Add after "Testing Strategy" section (around line 340):

```markdown
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
```

**Step 3: Run pre-commit on container/CLAUDE.md**

Run: `pre-commit run --files container/CLAUDE.md`

Note: Should be excluded by markdownlint config for docs/plans, but run to
verify

**Step 4: Commit container CLAUDE.md update**

```bash
git add container/CLAUDE.md
git commit -m "docs: add integration tests section to container CLAUDE.md

Document when and how to run container integration tests.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 13: Update VM CLAUDE.md

**Files:**

- Modify: `vm/CLAUDE.md`

**Step 1: Read current VM CLAUDE.md**

Run: `cat vm/CLAUDE.md | head -50`

**Step 2: Add testing section**

Add after "Testing Strategy" section (around line 70):

```markdown
### Integration Tests

Run end-to-end tests to validate VM environment:

```bash
# From repository root
./test-integration.sh --vm
```

This tests:

- Terraform provisions VM successfully
- cloud-init completes without errors
- Credentials inject correctly via vm-up.sh
- Config files deploy from `common/homedir/`
- Claude Code starts and responds to prompts

**When to run:**

- Before committing Terraform configuration changes
- Before committing cloud-init template changes
- Before committing changes to `common/homedir/` configs
- After updating package lists in `common/packages/`
```

**Step 3: Run pre-commit on vm/CLAUDE.md**

Run: `pre-commit run --files vm/CLAUDE.md`

**Step 4: Commit VM CLAUDE.md update**

```bash
git add vm/CLAUDE.md
git commit -m "docs: add integration tests section to vm CLAUDE.md

Document when and how to run VM integration tests.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 14: Update Root CLAUDE.md

**Files:**

- Modify: `CLAUDE.md`

**Step 1: Read current root CLAUDE.md**

Run: `cat CLAUDE.md`

**Step 2: Add integration testing guidance**

Add after the "Approach-Specific Documentation" section:

```markdown
## Integration Tests

Before committing changes that affect environment setup (Dockerfiles,
Terraform configs, credential injection, or `common/` configs), run
integration tests:

```bash
./test-integration.sh --all
```

This validates that AI assistants can start and operate correctly after your
changes.

See design: `docs/plans/2026-01-05-integration-tests-design.md`
```

**Step 3: Run pre-commit on CLAUDE.md**

Run: `pre-commit run --files CLAUDE.md`

**Step 4: Commit root CLAUDE.md update**

```bash
git add CLAUDE.md
git commit -m "docs: add integration tests guidance to root CLAUDE.md

Add guidance for when to run integration tests before committing changes.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 15: Final Validation

**Files:**

- Test: `test-integration.sh`
- Verify: All documentation

**Step 1: Run final pre-commit on all changed files**

Run: `pre-commit run --all-files`

Expected: All hooks pass

**Step 2: Verify script is executable**

Run: `ls -la test-integration.sh`

Expected: `-rwxr-xr-x` permissions

**Step 3: Test help output**

Run: `./test-integration.sh --help`

Expected: Shows complete usage information

**Step 4: Test invalid arguments**

Run: `./test-integration.sh --invalid`

Expected: Error message and usage, exit code 3

**Step 5: Manual test (if credentials available)**

If you have credentials and Docker/Terraform:

Run: `./test-integration.sh --container` (or `--vm`)

Expected: Complete test passes or shows clear error messages

**Step 6: Final commit (if any fixes needed)**

```bash
git add .
git commit -m "fix: final validation fixes for integration tests

Final cleanup and validation of integration test implementation.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Testing Checklist

After implementation, verify:

- [ ] `./test-integration.sh --help` shows usage
- [ ] `./test-integration.sh` without args shows error
- [ ] `./test-integration.sh --container` validates prerequisites
- [ ] `./test-integration.sh --vm` validates prerequisites
- [ ] Script is executable (`chmod +x`)
- [ ] Shellcheck passes: `shellcheck test-integration.sh`
- [ ] Pre-commit hooks pass: `pre-commit run --files test-integration.sh`
- [ ] Cleanup runs on exit (trap handler works)
- [ ] Documentation updated in all CLAUDE.md and README.md files
- [ ] All commits follow conventional commit format
- [ ] All commits include Claude Code footer

## Implementation Notes

**Key design decisions:**

1. **No modification to start-claude needed**: Claude Code already supports
   `-p` flag natively, and start-claude passes all args through via
   `exec claude "$@"`

2. **Trap-based cleanup**: Ensures cleanup always runs on exit, even on
   failures or Ctrl+C

3. **Verbose output by default**: Shows progress during long-running
   operations (builds, provisioning)

4. **Flexible credential handling**: Inherits mechanisms from agent-container and
   vm-up.sh scripts

5. **Deterministic validation**: Simple grep for expected phrase, tolerates
   extra text from Claude

**Common pitfalls to avoid:**

- Don't forget to quote variables in bash
- Don't forget to make script executable
- Don't forget to test cleanup handler
- Don't commit without running pre-commit hooks
- Don't skip documentation updates

**If tests fail:**

- Check prerequisites (Docker running, libvirt accessible)
- Verify credentials exist and are valid
- Check network connectivity for API calls
- Review Claude Code CLI output for errors
- Ensure cloud-init completes on VM (may take 2-3 minutes)
