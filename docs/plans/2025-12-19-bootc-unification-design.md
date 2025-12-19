# Bootc Unification Design

**Date:** 2025-12-19
**Status:** Approved for Implementation

## Overview

Unify the current container and VM approaches into a single bootable container
(bootc) image that can be deployed in two modes:

1. **Container mode** - Fast startup with git worktrees (current container
   workflow)
2. **VM mode** - Full isolation with nested virtualization and Docker (current
   VM workflow)

## Goals

- Single image source of truth for both deployment modes
- Guaranteed consistency between container and VM environments
- Maintain current workflows (git worktrees, vm-git-*, vm-dir-* scripts)
- Automated builds with smart change detection
- Clean top-level directory structure

## Technology Stack

- **Base Image:** fedora-bootc:43 (switching from Debian 13)
- **Build Tool:** Podman with bootc-compatible Containerfile
- **VM Conversion:** bootc-image-builder (qcow2 format)
- **VM Orchestration:** Terraform with libvirt provider
- **Package Management:** DNF (Fedora) instead of APT (Debian)

## Architecture

### Deployment Modes

#### Container Mode

```bash
./start-work my-branch
```

- Runs bootc image directly as OCI container
- Mounts git worktree and main repo (read-write)
- Fast startup, no VM overhead
- Read-only root filesystem with writable /var and /etc overlays
- Dynamic UID/GID mapping for host compatibility
- No Docker or nested virtualization access

#### VM Mode

```bash
./vm-up.sh
```

- Converts bootc image to qcow2 disk image
- Launches libvirt/KVM VM with Terraform
- Full OS with nested virtualization (host-passthrough CPU)
- Docker and libvirt available inside VM
- Runtime package installation via sudo dnf
- File transfer via vm-dir-* and vm-git-* scripts

### Directory Structure

```
/
├── start-work              # Auto-build + run container
├── vm-up.sh               # Auto-build + launch VM
├── vm-*.sh                # VM utility scripts
├── vm-common.sh
├── CLAUDE.md
├── bootc/                 # Build inputs only
│   ├── Containerfile      # fedora-bootc:43 based
│   ├── entrypoint.sh      # Container-mode startup
│   └── homedir/           # Copied to /etc/skel/
│       ├── .claude.json
│       ├── .gitconfig
│       └── .local/bin/start-claude
├── terraform/             # VM infrastructure (tucked away)
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── cloud-init.yaml.tftpl
└── .build/                # Build artifacts (gitignored)
    ├── disk.qcow2         # Generated VM disk
    └── qcow2/             # Temp bootc-image-builder output
```

### Build Pipeline

```
bootc/Containerfile ──┬──> bootc image ───> qcow2 disk ───> VM
bootc/homedir/*       ─┘                      ↑
                                              │
terraform/*.tf ───────────────────────────────┘
```

### Change Detection

**Smart rebuilding:**

1. **Bootc image** - Rebuild if any bootc/ files newer than image
2. **Qcow2 disk** - Rebuild if bootc image updated
3. **VM** - Reapply if Terraform files changed or qcow2 updated

**Implementation:**
- Timestamp comparison between source files and built artifacts
- Podman image inspect for image creation time
- Terraform plan -detailed-exitcode for infrastructure changes

## Migration from Current Infrastructure

### Package Conversions

| Current (Debian) | Bootc (Fedora) |
|------------------|----------------|
| apt-get install | dnf install |
| Most packages same names | git, curl, docker, etc. |
| gosu | su-exec or built-in runuser |

### Configuration Files

- **No changes needed** - homedir/ configs work identically
- `.claude.json`, `.gitconfig` copied to `/etc/skel/` at build time
- Container entrypoint copies to user home with correct UID/GID

### VM Provisioning

| Current | Bootc |
|---------|-------|
| Cloud-init installs packages (5-10 min) | Everything pre-installed (<1 min) |
| Debian cloud image base | Bootc-generated qcow2 |
| Package updates via apt | Atomic updates via bootc upgrade |

## Key Design Decisions

### Decision 1: Fedora-bootc:43 Base

**Rationale:** Debian lacks official bootc support. Fedora has mature bootc
ecosystem from Red Hat.

**Impact:** Package name changes, DNF instead of APT, Fedora ecosystem.

**Trade-off:** Accepted - ecosystem change for unified image worth it.

### Decision 2: Read-Only Root in Container Mode

**Rationale:** Bootc images designed with immutable root filesystem.

**Impact:** System packages can't be installed in container mode.

**Mitigation:** `/var` and `/etc` remain writable. VM mode allows runtime
package installation.

### Decision 3: Runtime Package Installation in VM Mode

**Rationale:** Development flexibility requires installing packages on-the-fly.

**Implementation:** Bootc VMs support layering packages via dnf. Maintain sudo
access in cloud-init.

**Result:** AI agents can `sudo dnf install` in VMs like current workflow.

### Decision 4: Automated Builds

**Rationale:** Users shouldn't manually build images before running scripts.

**Implementation:** start-work and vm-up.sh detect changes and rebuild
automatically.

**Benefit:** "Just works" experience - scripts handle complexity.

### Decision 5: Hidden Infrastructure (terraform/ subdir)

**Rationale:** Clean top-level with only user-facing scripts.

**Impact:** Scripts must cd into terraform/ for operations.

**Benefit:** Clearer structure, less clutter.

## Benefits

1. **Consistency** - Container and VM guaranteed identical
2. **Faster VM boot** - Pre-installed packages, not cloud-init installs
3. **Atomic VM updates** - `bootc upgrade` for reproducible state
4. **Simpler maintenance** - One Containerfile instead of two build processes
5. **Better testing** - Test once, works both modes

## Trade-offs

1. **Larger image size** - 3-5GB (includes kernel) vs 1-2GB
2. **Ecosystem change** - Fedora instead of Debian
3. **Build complexity** - More sophisticated than simple Dockerfile
4. **New tooling** - bootc-image-builder in workflow

## Testing Strategy

1. **Container mode testing**
   - Build bootc image
   - Run start-work with git worktree
   - Verify isolation (no host access except workspace)
   - Test pre-commit hooks
   - Verify UID/GID mapping

2. **VM mode testing**
   - Build qcow2 from bootc image
   - Launch VM with Terraform
   - Test nested virtualization (run Docker)
   - Test runtime package installation (dnf install)
   - Verify vm-git-* and vm-dir-* scripts work

3. **Change detection testing**
   - Modify Containerfile → verify image rebuilds
   - Update bootc image → verify qcow2 rebuilds
   - Change Terraform → verify VM reprovisioned
   - No changes → verify scripts skip rebuilds

## Implementation Phases

1. **Phase 1:** Build bootc infrastructure
   - Create bootc/Containerfile
   - Port packages to Fedora/DNF
   - Create container entrypoint

2. **Phase 2:** Container mode
   - Build start-work with auto-build
   - Test git worktree workflow
   - Verify isolation

3. **Phase 3:** VM mode
   - Integrate bootc-image-builder
   - Update Terraform for qcow2 base
   - Update cloud-init
   - Test vm-* scripts

4. **Phase 4:** Documentation and cleanup
   - Update CLAUDE.md
   - Remove old container/ and vm/ directories
   - Update pre-commit configs

## Success Criteria

- [ ] Single bootc image builds successfully
- [ ] Container mode works with git worktrees
- [ ] VM mode supports nested virtualization
- [ ] Runtime package installation works in VM
- [ ] vm-git-* and vm-dir-* scripts work unchanged
- [ ] Automated builds detect and propagate changes
- [ ] All pre-commit hooks pass
- [ ] Documentation updated

## References

- [bootc GitHub](https://github.com/bootc-dev/bootc)
- [Fedora bootc documentation](https://docs.fedoraproject.org/en-US/bootc/)
- [bootc-image-builder](https://github.com/osbuild/bootc-image-builder)
- [Red Hat bootc guides](https://developers.redhat.com/articles/2024/09/24/bootc-getting-started-bootable-containers)
