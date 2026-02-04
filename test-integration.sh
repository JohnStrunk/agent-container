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

    # Check Lima for VM tests
    if [[ "$TEST_TYPE" == "vm" ]] || [[ "$TEST_TYPE" == "all" ]]; then
        if ! command -v limactl &>/dev/null; then
            log_error "limactl not found. Install Lima first."
            log_error "  Linux: sudo apt-get install lima"
            log_error "  macOS: brew install lima"
            ((errors++))
        else
            local lima_version
            lima_version=$(limactl --version 2>&1 | head -n1 || echo "unknown")
            log "✓ Lima installed: $lima_version"
        fi

        if ! command -v sshfs &>/dev/null; then
            log "⚠ sshfs not installed (optional, SSHFS mount tests will be skipped)"
            log "  Linux: sudo apt-get install sshfs"
            log "  macOS: brew install macfuse && brew install sshfs"
        else
            log "✓ sshfs installed"
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
            # Clean up the single agent-vm instance
            ./agent-vm destroy 2>/dev/null || true
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

# Source profile.d scripts to get PATH and environment
for script in /etc/profile.d/*.sh; do
    [ -r "$script" ] && source "$script"
done

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
    # This prevents agent-container from allocating a TTY in non-interactive context
    if ! run_with_timeout 90 ./container/agent-container \
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

test_vm_approach() {
    log_step "Testing VM Approach (Lima)"

    cd vm/ || exit "$EXIT_PREREQ_FAILED"

    # Save repo root and current branch to restore later
    local repo_root
    repo_root="$(cd .. && pwd)"
    local original_branch
    original_branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
    local original_dir
    original_dir="$(pwd)"
    log "Saved original branch: ${original_branch:-<detached HEAD>}"
    log "Repo root: $repo_root"

    # Generate unique branch names to avoid conflicts
    local timestamp
    timestamp=$(date +%s)
    local test_branch_1="test-vm-integration-${timestamp}-1"
    local test_branch_2="test-vm-integration-${timestamp}-2"
    log "Using temporary branches: $test_branch_1, $test_branch_2"

    # Cleanup function for temporary branches
    # shellcheck disable=SC2317
    cleanup_test_branches() {
        local exit_code=$?

        log "Cleaning up temporary test branches..."

        # Change to repo root using absolute path
        cd "$repo_root" || {
            log_error "Failed to cd to repo root: $repo_root"
            return "$exit_code"
        }

        # Restore original branch first (so we can delete test branches)
        if [[ -n "$original_branch" ]]; then
            current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
            if [[ "$current_branch" != "$original_branch" ]]; then
                log "Restoring original branch: $original_branch"
                git checkout "$original_branch" 2>/dev/null || log_error "Failed to restore original branch"
            fi
        fi

        # Delete test branches if they exist (must be done after checkout to avoid "cannot delete checked out branch" error)
        if git show-ref --verify --quiet "refs/heads/$test_branch_1"; then
            log "Deleting branch: $test_branch_1"
            git branch -D "$test_branch_1" 2>/dev/null || true
        fi

        if git show-ref --verify --quiet "refs/heads/$test_branch_2"; then
            log "Deleting branch: $test_branch_2"
            git branch -D "$test_branch_2" 2>/dev/null || true
        fi

        # Return to original directory
        cd "$original_dir" || log_error "Failed to restore directory: $original_dir"

        return "$exit_code"
    }

    # Set trap to cleanup branches on exit
    trap cleanup_test_branches RETURN

    # Cleanup any existing test artifacts
    log "Cleaning up any existing test VMs..."
    ./agent-vm destroy 2>/dev/null || true

    # Test 1: Validate Lima template
    log "Test 1: Validating Lima template..."
    if ! run_with_timeout 10 limactl validate agent-vm.yaml; then
        log_error "Lima template validation failed"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Lima template valid"

    # Test 2: Create VM via agent-vm start
    log "Test 2: Creating VM via agent-vm start..."
    if ! run_with_timeout 300 ./agent-vm start; then
        log_error "Failed to create VM"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ VM created successfully"

    # Test 3: Verify VM exists in Lima
    log "Test 3: Verifying VM exists in Lima..."
    if ! limactl list --format json 2>/dev/null | grep -q '"name":"agent-vm"'; then
        log_error "VM not found in Lima list"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ VM exists in Lima"

    # Test 4: Check VM status command
    log "Test 4: Checking VM status..."
    status_output=$(./agent-vm status 2>&1)
    if ! echo "$status_output" | grep -q "State: Running"; then
        log_error "VM not showing as running in status"
        echo "$status_output"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ VM status shows running"

    # Test 5: Verify provisioning completion
    log "Test 5: Verifying provisioning completion..."
    # Check environment marker file
    if ! ./agent-vm connect -- test -f /etc/agent-environment; then
        log_error "Environment marker file not found"
        return "$EXIT_TEST_FAILED"
    fi
    # Check Claude Code is installed
    if ! ./agent-vm connect -- which claude >/dev/null 2>&1; then
        log_error "Claude Code not installed in VM"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Provisioning completed"

    # Test 6: Create first workspace
    log "Test 6: Creating first workspace..."
    if ! ./agent-vm connect "$test_branch_1" -- echo "Workspace 1 created"; then
        log_error "Failed to create first workspace"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ First workspace created"

    # Test 7: Create second workspace (same VM)
    log "Test 7: Creating second workspace in same VM..."
    if ! ./agent-vm connect "$test_branch_2" -- echo "Workspace 2 created"; then
        log_error "Failed to create second workspace"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Second workspace created"

    # Test 8: Test Claude Code in VM
    log "Test 8: Testing Claude Code in VM..."
    test_script=$(generate_test_command)
    if ! ./agent-vm connect "$test_branch_1" -- bash -l -c "cat > /tmp/test-claude.sh << 'TESTEOF'
$test_script
TESTEOF
chmod +x /tmp/test-claude.sh
/tmp/test-claude.sh" < /dev/null; then
        log_error "Claude Code test failed in VM"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Claude Code works in VM"

    # Test 9: Verify SSHFS mount
    log "Test 9: Verifying SSHFS mount..."
    if ! command -v sshfs >/dev/null 2>&1; then
        log "⚠ SSHFS not installed, skipping mount test"
    elif [[ -d "$HOME/.agent-vm-mounts/workspace" ]] && mountpoint -q "$HOME/.agent-vm-mounts/workspace" 2>/dev/null; then
        log "✓ SSHFS mount active"
        # Verify we can access workspace files
        local repo_name
        repo_name="$(basename "$repo_root")"
        if ls "$HOME/.agent-vm-mounts/workspace/${repo_name}-${test_branch_1}" >/dev/null 2>&1; then
            log "✓ Can access workspace files via SSHFS"
        else
            log_error "SSHFS mount exists but cannot access workspace files"
            return "$EXIT_TEST_FAILED"
        fi
    else
        log "⚠ SSHFS available but mount not active (continuing)"
    fi

    # Test 10: Test git push operation
    log "Test 10: Testing git push to VM workspace..."
    local repo_name
    repo_name="$(basename "$repo_root")"
    cd "$repo_root" || exit "$EXIT_TEST_FAILED"
    # Make a small change to push
    echo "# Test file for integration test" > test-integration-file.txt
    git add test-integration-file.txt
    git commit -m "Test commit for integration test" >/dev/null 2>&1 || true
    cd "$original_dir" || exit "$EXIT_TEST_FAILED"
    if ! ./agent-vm push "$test_branch_1" 2>&1; then
        log_error "Failed to push to VM workspace"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Git push successful"

    # Test 11: Test git fetch operation
    log "Test 11: Testing git fetch from VM workspace..."
    # Make a change in VM (pre-commit hooks may modify files, so we commit twice if needed)
    if ! ./agent-vm connect "$test_branch_1" -- bash -c "echo 'VM change' >> test-vm-change.txt && git add test-vm-change.txt && git commit -m 'VM test commit' || (git add test-vm-change.txt && git commit -m 'VM test commit')"; then
        log_error "Failed to make commit in VM"
        return "$EXIT_TEST_FAILED"
    fi
    # Fetch it back
    if ! ./agent-vm fetch "$test_branch_1" 2>&1; then
        log_error "Failed to fetch from VM workspace"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Git fetch successful"

    # Test 12: Test workspace listing
    log "Test 12: Testing workspace listing..."
    list_output=$(./agent-vm status 2>&1)
    if ! echo "$list_output" | grep -q "${repo_name}-${test_branch_1}"; then
        log_error "Workspace $test_branch_1 not found in status"
        echo "$list_output"
        return "$EXIT_TEST_FAILED"
    fi
    if ! echo "$list_output" | grep -q "${repo_name}-${test_branch_2}"; then
        log_error "Workspace $test_branch_2 not found in status"
        echo "$list_output"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Workspace listing correct"

    # Test 13: Test environment variable injection
    log "Test 13: Testing environment variable injection..."
    # Test that connection-time env vars work (from envvars.txt)
    export TEST_ENV_VAR="integration-test-value"
    # shellcheck disable=SC2016
    if ! ./agent-vm connect "$test_branch_1" -- bash -c 'echo "TEST_ENV_VAR=$TEST_ENV_VAR"' | grep -q "integration-test-value"; then
        log_error "Environment variable not passed to VM"
        return "$EXIT_TEST_FAILED"
    fi
    unset TEST_ENV_VAR
    log "✓ Environment variables injected"

    # Test 14: Test credential injection (if available)
    log "Test 14: Testing credential injection..."
    if [[ -f "$GCP_CREDS_PATH" ]]; then
        # Check if GCP credentials are present in VM
        if ! ./agent-vm connect -- test -f /etc/google/application_default_credentials.json; then
            log_error "GCP credentials not found in VM"
            return "$EXIT_TEST_FAILED"
        fi
        # Check if env var is set
        # shellcheck disable=SC2016
        if ! ./agent-vm connect -- bash -l -c 'test -n "$GOOGLE_APPLICATION_CREDENTIALS"'; then
            log_error "GOOGLE_APPLICATION_CREDENTIALS not set in VM"
            return "$EXIT_TEST_FAILED"
        fi
        log "✓ Credentials injected correctly"
    else
        log "⚠ No GCP credentials available, skipping credential test"
    fi

    # Test 15: Test resource override with --memory/--vcpu
    log "Test 15: Testing resource override..."
    # Destroy and recreate with custom resources
    ./agent-vm destroy 2>/dev/null || true
    if ! run_with_timeout 300 ./agent-vm start --memory 4 --vcpu 2; then
        log_error "Failed to create VM with custom resources"
        return "$EXIT_TEST_FAILED"
    fi
    # Verify resources (check status output)
    status_output=$(./agent-vm status 2>&1)
    if ! echo "$status_output" | grep -q "CPUs: 2"; then
        log_error "CPU count not set correctly"
        echo "$status_output"
        return "$EXIT_TEST_FAILED"
    fi
    if ! echo "$status_output" | grep -q "Memory: 4 GiB"; then
        log_error "Memory not set correctly"
        echo "$status_output"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Resource override works"

    # Test 16: Test workspace cleanup
    log "Test 16: Testing workspace cleanup..."
    # Create a test workspace
    ./agent-vm connect "$test_branch_1" -- echo "Test workspace" >/dev/null 2>&1
    # Clean it
    if ! ./agent-vm clean -f "$test_branch_1" 2>&1; then
        log_error "Failed to clean workspace"
        return "$EXIT_TEST_FAILED"
    fi
    # Verify it's gone
    if ./agent-vm status 2>&1 | grep -q "${repo_name}-${test_branch_1}"; then
        log_error "Workspace still exists after clean"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Workspace cleanup successful"

    # Test 17: Test clean-all workspaces
    log "Test 17: Testing clean-all workspaces..."
    # Create test workspaces
    ./agent-vm connect "$test_branch_1" -- echo "Test workspace 1" >/dev/null 2>&1
    ./agent-vm connect "$test_branch_2" -- echo "Test workspace 2" >/dev/null 2>&1
    # Clean all
    if ! ./agent-vm clean-all -f 2>&1; then
        log_error "Failed to clean all workspaces"
        return "$EXIT_TEST_FAILED"
    fi
    # Verify all gone
    status_output=$(./agent-vm status 2>&1)
    if echo "$status_output" | grep -q "${repo_name}-${test_branch_1}" || \
       echo "$status_output" | grep -q "${repo_name}-${test_branch_2}"; then
        log_error "Workspaces still exist after clean-all"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Clean-all successful"

    # Test 18: Test SSHFS unmounting
    log "Test 18: Testing SSHFS unmounting..."
    if command -v sshfs >/dev/null 2>&1; then
        # Unmount happens during destroy, verify mount is active first
        if mountpoint -q "$HOME/.agent-vm-mounts/workspace" 2>/dev/null; then
            log "✓ SSHFS mount active before destroy"
        fi
    else
        log "⚠ SSHFS not installed, skipping unmount test"
    fi

    # Test 19: Test VM destruction
    log "Test 19: Testing VM destruction..."
    if ! ./agent-vm destroy 2>&1; then
        log_error "Failed to destroy VM"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ VM destroyed"

    # Test 20: Verify VM is completely removed
    log "Test 20: Verifying VM is completely removed..."
    # Check Lima
    if limactl list --format json 2>/dev/null | grep -q '"name":"agent-vm"'; then
        log_error "VM still exists in Lima after destroy"
        return "$EXIT_TEST_FAILED"
    fi
    # Check SSHFS unmounted
    if command -v sshfs >/dev/null 2>&1 && mountpoint -q "$HOME/.agent-vm-mounts/workspace" 2>/dev/null; then
        log_error "SSHFS mount still active after destroy"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ VM completely removed"

    # Test 21: Verify no Lima state left behind (except .lima directory which is persistent)
    log "Test 21: Verifying Lima state cleanup..."
    # The .lima/agent-vm directory may still exist but should be empty or minimal
    # We just verify the VM is not in the active list
    if limactl list 2>&1 | grep -q "agent-vm"; then
        log_error "VM still in Lima list after destroy"
        return "$EXIT_TEST_FAILED"
    fi
    log "✓ Lima state cleaned up"

    cd ..
    log_step "VM approach tests: PASS"
    return "$EXIT_SUCCESS"
}

main() {
    parse_args "$@"

    # Detect container runtime for container tests
    if [[ "$TEST_TYPE" == "container" ]] || [[ "$TEST_TYPE" == "all" ]]; then
        # Source runtime detection from container/lib
        SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
        # shellcheck source=container/lib/container-runtime.sh
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/container/lib/container-runtime.sh"

        CONTAINER_RUNTIME=$(detect_runtime)
        log "Detected container runtime: $CONTAINER_RUNTIME"
    fi

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
        if ! test_vm_approach; then
            exit "$EXIT_TEST_FAILED"
        fi
    elif [[ "$TEST_TYPE" == "all" ]]; then
        if ! test_container; then
            exit "$EXIT_TEST_FAILED"
        fi
        if ! test_vm_approach; then
            exit "$EXIT_TEST_FAILED"
        fi
    fi

    # Success - cleanup_all will print the final status message
    exit "$EXIT_SUCCESS"
}

main "$@"
