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
