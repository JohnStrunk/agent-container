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

Credentials are detected in this order:
  1. --gcp-credentials <path> flag (highest priority)
  2. GOOGLE_APPLICATION_CREDENTIALS environment variable
  3. Default: ~/.config/gcloud/application_default_credentials.json

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
                if [[ -z "$2" || "$2" == --* ]]; then
                    log_error "--gcp-credentials requires a path argument"
                    usage
                    exit "$EXIT_INVALID_ARGS"
                fi
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

    # Apply credential precedence: CLI flag → env var → default
    if [[ -z "$GCP_CREDS_PATH" ]]; then  # No --gcp-credentials flag
        if [[ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]]; then
            GCP_CREDS_PATH="$GOOGLE_APPLICATION_CREDENTIALS"
        else
            GCP_CREDS_PATH="$GCP_CREDS_DEFAULT"
        fi
    fi
}

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

        if ! virsh list &>/dev/null; then
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

    if [[ "$has_credentials" == false ]]; then
        log_error "No credentials found. Need at least one of:"
        log_error "  - GCP credentials file at: $GCP_CREDS_PATH"
        log_error "    Run: gcloud auth application-default login"
        log_error "  - ANTHROPIC_API_KEY environment variable"
        log_error "  - GEMINI_API_KEY environment variable"
        ((errors++))
    fi

    return $errors
}

# shellcheck disable=SC2317
cleanup_container() {
    log "Cleaning up container resources..."
    # Docker handles cleanup via --rm flag, nothing to do
    log "Container cleanup complete"
}

# shellcheck disable=SC2317
cleanup_vm() {
    log "Cleaning up VMs..."
    if [[ -d vm ]] && [[ -f vm/agent-vm ]]; then
        (
            cd vm || exit
            # Clean up any test VMs that might still be running
            ./agent-vm -b test-branch-1 --destroy 2>/dev/null || true
            ./agent-vm -b test-branch-2 --destroy 2>/dev/null || true
        )
    fi
    log "VM cleanup complete"
}

# shellcheck disable=SC2317
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

    # Print final status message
    echo ""
    echo "========================================"
    if [[ $exit_code -eq 0 ]]; then
        echo "RESULT: ALL TESTS PASSED ✓"
    else
        echo "RESULT: TESTS FAILED ✗"
        echo "Exit code: $exit_code"
    fi
    echo "========================================"
    echo ""

    exit "$exit_code"
}

generate_test_command() {
    cat <<'EOF'
#!/bin/bash
set -e -o pipefail

echo "[Test] Sending prompt to Claude Code..."

# One-shot prompt with 60s timeout
# Redirect stdin from /dev/null to prevent TTY setup issues
timeout 60 claude -p "Repeat this phrase exactly: 'All systems go!'" \
    < /dev/null > /tmp/claude-response.txt 2>&1 || {
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

run_with_timeout() {
    local timeout_seconds=$1
    shift
    timeout "$timeout_seconds" "$@"
}

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

    # Redirect stdin from /dev/null to break TTY connection
    # This prevents start-work from allocating a TTY in non-interactive context
    if ! run_with_timeout 90 ./container/start-work \
        "${gcp_creds_arg[@]}" \
        -- bash -c "$(generate_test_command)" < /dev/null; then
        log_error "Container test failed"
        return 1
    fi

    local total_time
    total_time=$(($(date +%s) - start_time))
    log_step "Container Test: PASS (${total_time}s)"
    return 0
}

test_vm() {
  echo "Testing VM approach with multi-instance support..."

  cd vm/ || exit 1

  # Test 1: Create first VM
  echo "Test: Creating first VM"
  ./agent-vm -b test-branch-1 -- echo "VM 1 ready"
  if [ $? -ne 0 ]; then
    echo "FAIL: Could not create first VM"
    return 1
  fi

  # Test 2: Create second VM (parallel)
  echo "Test: Creating second VM in parallel"
  ./agent-vm -b test-branch-2 -- echo "VM 2 ready"
  if [ $? -ne 0 ]; then
    echo "FAIL: Could not create second VM"
    ./agent-vm -b test-branch-1 --destroy
    return 1
  fi

  # Test 3: Verify both running
  echo "Test: Verifying both VMs are running"
  if ! virsh list --state-running 2>/dev/null | grep -q "test-branch-1"; then
    echo "FAIL: First VM not running"
    ./agent-vm -b test-branch-1 --destroy
    ./agent-vm -b test-branch-2 --destroy
    return 1
  fi

  if ! virsh list --state-running 2>/dev/null | grep -q "test-branch-2"; then
    echo "FAIL: Second VM not running"
    ./agent-vm -b test-branch-1 --destroy
    ./agent-vm -b test-branch-2 --destroy
    return 1
  fi

  # Test 4: Verify filesystem mounts
  echo "Test: Verifying filesystem mounts"
  if ! ./agent-vm -b test-branch-1 -- mountpoint -q /worktree; then
    echo "FAIL: Worktree not mounted in first VM"
    ./agent-vm -b test-branch-1 --destroy
    ./agent-vm -b test-branch-2 --destroy
    return 1
  fi

  # Test 5: Test reconnection
  echo "Test: Reconnecting to first VM"
  if ! ./agent-vm -b test-branch-1 -- echo "Reconnected"; then
    echo "FAIL: Could not reconnect to first VM"
    ./agent-vm -b test-branch-1 --destroy
    ./agent-vm -b test-branch-2 --destroy
    return 1
  fi

  # Test 6: Verify list command
  echo "Test: Listing VMs"
  if ! ./agent-vm --list | grep -q "test-branch-1"; then
    echo "FAIL: List command did not show first VM"
    ./agent-vm -b test-branch-1 --destroy
    ./agent-vm -b test-branch-2 --destroy
    return 1
  fi

  # Cleanup
  echo "Cleaning up test VMs..."
  ./agent-vm -b test-branch-1 --destroy
  ./agent-vm -b test-branch-2 --destroy

  cd ..
  echo "VM tests PASSED"
  return 0
}

main() {
    parse_args "$@"

    # Check environment - integration tests cannot run in container
    if [[ -f /etc/agent-environment ]]; then
        local env_type
        env_type=$(cat /etc/agent-environment)
        if [[ "$env_type" == "agent-container" ]]; then
            log_error "Integration tests cannot run inside the container environment"
            log_error "The container does not have Docker or VM support"
            log_error "Run integration tests from the host machine instead"
            exit "$EXIT_PREREQ_FAILED"
        fi
        log "Detected environment: $env_type"
    fi

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

    # Success - cleanup_all will print the final status message
    exit "$EXIT_SUCCESS"
}

main "$@"
