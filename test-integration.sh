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

# Placeholder for main function
main() {
    parse_args "$@"

    log_step "Integration Tests v${VERSION}"
    log "Test type: $TEST_TYPE"
    log "GCP credentials: $GCP_CREDS_PATH"
    log "Force rebuild: $FORCE_REBUILD"
}

main "$@"
