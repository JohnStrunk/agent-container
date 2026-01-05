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
    log "Cleaning up VM..."
    if [[ -d vm ]] && [[ -f vm/main.tf ]]; then
        (
            cd vm || exit
            if terraform state list 2>/dev/null | grep -q .; then
                terraform destroy -auto-approve \
                    -var="user_uid=$(id -u)" \
                    -var="user_gid=$(id -g)" 2>&1 | \
                    grep -v "^$" || true
            else
                log "No VM to clean up"
            fi
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

    exit "$exit_code"
}

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

    if ! run_with_timeout 90 ./container/start-work \
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

    # Export GOOGLE_APPLICATION_CREDENTIALS for vm-up.sh
    export GOOGLE_APPLICATION_CREDENTIALS="$GCP_CREDS_PATH"

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

    local ssh_cmd="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -i vm_ssh_key"

    if ! run_with_timeout 120 bash -c "
        while ! $ssh_cmd claude@${vm_ip} 'cloud-init status --wait' 2>/dev/null; do
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

    # shellcheck disable=SC2086
    if ! run_with_timeout 90 $ssh_cmd "claude@${vm_ip}" \
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

    log_step "All Tests Passed!"
    exit "$EXIT_SUCCESS"
}

main "$@"
