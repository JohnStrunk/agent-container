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
