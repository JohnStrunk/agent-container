# Claude Code Assistant Configuration - Bootc Unified

## Project Overview

This repository provides a **unified bootable container (bootc)** approach for
creating isolated AI development environments. A single bootc image can be
deployed in two modes:

1. **Container mode** - Fast startup with git worktrees
2. **VM mode** - Full isolation with nested virtualization and Docker

## Key Technologies

- **Base Image:** Fedora-bootc:43
- **Container Runtime:** Podman
- **VM Infrastructure:** Terraform + libvirt/KVM
- **Build Tool:** bootc-image-builder
- **AI Agents:** Claude Code, Gemini CLI

## Quick Start

### Container Mode (Fast)

```bash
# Start interactive session with git worktree
./start-work -b feature-branch

# Use current directory
./start-work
```

### VM Mode (Full Isolation)

```bash
# Launch VM (auto-builds everything)
./vm-up.sh

# Connect to VM
./vm-connect.sh

# Destroy VM
./vm-down.sh
```

## Architecture

### Single Image, Two Modes

```text
bootc/Containerfile ──> bootc image ──┬──> Container (podman run)
                                      └──> qcow2 ──> VM (libvirt)
```

**Container mode:**

- Direct podman run of bootc image
- Git worktree workflow for isolated branches
- Fast startup, no VM overhead
- Read-only root, writable /var and /etc
- No Docker or nested virtualization

**VM mode:**

- Convert bootc image to qcow2 disk with bootc-image-builder
- Launch KVM/libvirt VM via Terraform
- Full OS with nested virtualization (host-passthrough CPU)
- Docker and libvirt available inside
- Runtime package installation via `sudo dnf install`

### Directory Structure

```text
/
├── start-work              # Container mode launcher
├── vm-up.sh               # VM mode launcher (auto-build)
├── vm-down.sh             # Destroy VM
├── vm-connect.sh          # SSH to VM
├── vm-git-push            # Push git branch to VM
├── vm-git-fetch           # Fetch git branch from VM
├── vm-dir-push            # Rsync directory to VM
├── vm-dir-pull            # Rsync directory from VM
├── vm-common.sh           # Shared VM functions
├── CLAUDE.md              # This file
├── bootc/                 # Build inputs
│   ├── Containerfile      # Single source of truth
│   ├── entrypoint.sh      # Container mode startup
│   └── homedir/           # Configs copied to /etc/skel/
└── terraform/             # VM infrastructure
    ├── main.tf
    ├── variables.tf
    ├── outputs.tf
    └── cloud-init.yaml.tftpl
```

## Development Workflow

### Container Mode Workflow

```bash
# Automatic build and run
./start-work -b my-feature

# Inside container
git status
# work on code
exit

# Changes preserved in git worktree
```

### VM Mode Workflow

```bash
# 1. Launch VM (builds bootc image + qcow2 if needed)
./vm-up.sh

# 2. Push your work to VM
./vm-git-push my-feature

# 3. Connect and work
./vm-connect.sh
# Inside VM: cd ~/workspace, work on code

# 4. Pull changes back
./vm-git-fetch my-feature

# 5. Cleanup
./vm-down.sh
```

## Smart Build System

Scripts automatically detect changes and rebuild only what's needed:

```text
bootc/Containerfile changed → rebuild bootc image → regenerate qcow2 → update VM
terraform/*.tf changed → reapply terraform
No changes → skip rebuilds
```

**Change detection:**

- Compares file timestamps to built artifact creation times
- Cascading rebuilds (Containerfile → image → qcow2 → VM)
- Terraform plan diff detection

## Modifying the Environment

### Adding Packages

**Edit:** `bootc/Containerfile`

```dockerfile
RUN dnf install -y \
    postgresql-client \
    redis
```

**Apply:**

- Container mode: `./start-work` (auto-rebuilds)
- VM mode: `./vm-up.sh` (auto-rebuilds)

### Adding Homedir Configs

**Add files to:** `bootc/homedir/`

Files are copied to `/etc/skel/` and then to user home directory.

### Runtime Package Installation (VM Only)

Inside running VM:

```bash
sudo dnf install postgresql-server
# Persists across reboots (bootc layering)
```

## VM File Transfer

### Git-based transfer

```bash
# Push branch to VM
./vm-git-push feature-auth

# Fetch branch from VM
./vm-git-fetch feature-auth
```

### Directory-based transfer

```bash
# Push directory to VM workspace
./vm-dir-push ./my-project

# Pull directory from VM workspace
./vm-dir-pull ./my-project
```

## Testing and Quality

### Pre-commit Hooks

```bash
# Run before committing
pre-commit run --all-files
```

### Testing Changes

**Container mode:**

```bash
./start-work
# Test functionality inside container
```

**VM mode:**

```bash
./vm-up.sh
./vm-connect.sh
# Test inside VM
```

## Security Model

### Container Mode Isolation

**Agent can access:**

- Workspace directory (read-write)
- Main git repository (read-write)
- Cache volume (shared)

**Agent cannot access:**

- Host filesystem outside workspace
- Docker socket
- Host credentials

### VM Mode Isolation

**Agent can access:**

- Full VM filesystem
- Docker inside VM
- Nested virtualization

**Agent cannot access:**

- Host filesystem (use vm-dir-* for transfers)
- Host Docker
- Host credentials (injected via cloud-init if provided)

## Troubleshooting

### Rebuild from scratch

```bash
# Container mode
podman rmi ghcr.io/johnstrunk/agent-bootc:latest
./start-work

# VM mode
rm -rf .build/
./vm-down.sh
./vm-up.sh
```

### VM won't start

```bash
cd terraform
terraform destroy -auto-approve
cd ..
./vm-up.sh
```

### Check build artifacts

```bash
# Check bootc image
podman images | grep agent-bootc

# Check qcow2
ls -lh .build/disk.qcow2
```

## Benefits of Unified Approach

- **Consistency** - Same packages, configs, tools in both modes
- **Faster VM boot** - Pre-installed packages (no cloud-init installs)
- **Atomic updates** - `bootc upgrade` for reproducible VM state
- **Simpler maintenance** - One Containerfile vs two build processes
- **Flexibility** - Choose deployment mode per use case
