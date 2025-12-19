# Repository Reorganization Design

**Date:** 2025-12-18
**Status:** Approved

## Overview

Refactor the repository to cleanly separate container-based and VM-based
approaches for AI development environments, while extracting common resources
into a shared location.

## Problem Statement

The repository currently supports both Docker container and libvirt VM
approaches, but they're mixed together:

- Container files at repository root
- VM files in yolo-vm/ subdirectory
- Duplicated configuration files (files/homedir/ and yolo-vm/files/homedir/)
- Duplicated package lists in Dockerfile and cloud-init templates
- Documentation doesn't clearly guide users to the right approach

This creates confusion and maintenance burden.

## Design Goals

1. **Clear separation** - Each approach in its own directory
2. **Shared resources** - Extract common configs and package lists
3. **Gateway documentation** - Root docs help users choose the right approach
4. **No duplication** - Single source of truth for shared resources
5. **Maintain functionality** - Both approaches must work exactly as before

## Proposed Structure

```
/home/user/workspace/
├── common/                    # Shared resources
│   ├── homedir/              # Unified config files
│   │   ├── .claude.json
│   │   ├── .gitconfig
│   │   ├── .gitignore
│   │   ├── .local/bin/start-claude
│   │   ├── .claude/settings.json
│   │   └── .claude/statusline-command.sh
│   └── packages/             # Package definition files
│       ├── apt-packages.txt
│       ├── npm-packages.txt
│       ├── python-packages.txt
│       ├── go-version.txt
│       └── versions.txt      # Other tool versions (hadolint, etc.)
│
├── container/                # Docker approach
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── entrypoint_user.sh
│   ├── start-work
│   ├── README.md             # Container-specific documentation
│   └── CLAUDE.md             # Container-specific assistant guide
│
├── vm/                       # Libvirt/KVM approach
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── cloud-init.yaml.tftpl
│   ├── vm-*.sh               # All vm utility scripts
│   ├── libvirt-nat-fix.sh
│   ├── README.md             # VM-specific documentation
│   └── CLAUDE.md             # VM-specific assistant guide
│
├── .github/                  # Stays at root
├── docs/                     # Stays at root
├── README.md                 # Gateway doc with comparison table
├── CLAUDE.md                 # Gateway assistant guide
├── LICENSE
├── .pre-commit-config.yaml
└── .gitignore
```

## Package Management

### Format

Use simple line-based text files that both approaches can consume:

**apt-packages.txt:**
```
# Base utilities
vim
curl
wget
git
# ... (comments and blank lines allowed)
```

**npm-packages.txt:**
```
@anthropic-ai/claude-code@latest
@google/gemini-cli@latest
@github/copilot@latest
```

**python-packages.txt:**
```
pre-commit
poetry
pipenv
dvc[all]
```

**versions.txt:**
```
GOLANG_VERSION=1.25.0
HADOLINT_VERSION=2.12.0
UV_VERSION=latest
```

### Consumption Patterns

**Container (Dockerfile):**
```dockerfile
# Read and install apt packages
COPY ../common/packages/apt-packages.txt /tmp/
RUN grep -v '^#' /tmp/apt-packages.txt | xargs apt-get install -y

# Read and install npm packages
COPY ../common/packages/npm-packages.txt /tmp/
RUN xargs npm install -g < /tmp/npm-packages.txt
```

**VM (Terraform + cloud-init):**
```hcl
# main.tf
locals {
  apt_packages    = split("\n", file("${path.module}/../common/packages/apt-packages.txt"))
  npm_packages    = split("\n", file("${path.module}/../common/packages/npm-packages.txt"))
  python_packages = split("\n", file("${path.module}/../common/packages/python-packages.txt"))
}

# Pass to template
templatefile("cloud-init.yaml.tftpl", {
  apt_packages    = [for p in local.apt_packages : p if p != "" && !startswith(p, "#")]
  npm_packages    = [for p in local.npm_packages : p if p != "" && !startswith(p, "#")]
  python_packages = [for p in local.python_packages : p if p != "" && !startswith(p, "#")]
})
```

**cloud-init.yaml.tftpl:**
```yaml
packages:
%{ for pkg in apt_packages ~}
  - ${pkg}
%{ endfor ~}

runcmd:
  - npm install -g ${join(" ", npm_packages)}
  - pip install --break-system-packages ${join(" ", python_packages)}
```

## Documentation Structure

### Root README.md

1. **Project overview** - Brief explanation of two approaches
2. **Comparison table:**

   | Feature | Container | VM |
   |---------|-----------|-----|
   | Startup time | ~2 seconds | ~30-60 seconds |
   | Isolation | Strong (namespaces) | Strongest (full VM) |
   | Nested virtualization | No | Yes |
   | Resource overhead | Minimal | Moderate |
   | Best for | Quick iterations, most use cases | Testing infrastructure, VM workloads |

3. **Quick start links** - Direct to container/README.md and vm/README.md
4. **Common resources note** - Mention shared configs in common/

### Root CLAUDE.md

1. **Brief overview** - Two approaches available
2. **Approach selection** - Guide to determine which approach is in use
3. **Links to specific guides** - Point to container/CLAUDE.md or vm/CLAUDE.md
4. **Common resources note** - Explain common/ directory purpose

### Approach-Specific Documentation

Each approach gets complete standalone documentation:

- **README.md** - Full user guide (quick start, configuration, troubleshooting)
- **CLAUDE.md** - Detailed assistant instructions specific to that approach

## Homedir Standardization

Both approaches will use identical structure:

```
.claude.json
.gitconfig
.gitignore
.local/bin/start-claude
.claude/settings.json
.claude/statusline-command.sh
```

**Changes required:**
- VM currently has start-claude at root, needs to move to .local/bin/
- Container already has correct structure
- Remove .gitignore from VM's homedir (not needed there)

## Migration Strategy

### Phase 1: Create New Structure
1. Create common/, container/, vm/ directories
2. Copy files to new locations (keep originals)
3. Create package list files in common/packages/

### Phase 2: Update References
4. Update Dockerfile COPY paths to ../common/
5. Update Terraform to read package files and pass to template
6. Update cloud-init template to use package variables
7. Standardize homedir structure (move VM's start-claude)
8. Update all script paths and references

### Phase 3: Documentation
9. Write new root README.md (gateway)
10. Write new root CLAUDE.md (gateway)
11. Write container/README.md (current README content, adapted)
12. Write container/CLAUDE.md (current CLAUDE.md content, adapted)
13. Write vm/README.md (current yolo-vm/README.md content, adapted)
14. Write vm/CLAUDE.md (new, based on yolo-vm context)

### Phase 4: Initial Testing
15. Build container from container/Dockerfile
16. Test container start-work script
17. Test VM terraform plan
18. Test VM terraform apply
19. Verify homedir files deployed correctly in both
20. Run pre-commit on all changed files

### Phase 5: Cleanup
21. Remove old files:
    - Root: Dockerfile, start-work, entrypoint*.sh, files/
    - yolo-vm/ directory entirely
22. Update .gitignore if needed

### Phase 6: Final Verification
23. Re-test container build and execution (catch missed references)
24. Re-test VM deployment (catch missed references)
25. Verify all documentation links work
26. Run pre-commit on entire repository
27. Final git status check

## Testing Checklist

Run twice - once before cleanup (step 15-20), once after (step 23-26):

- [ ] Container builds successfully from container/Dockerfile
- [ ] Container start-work creates worktree and launches
- [ ] VM terraform plan succeeds from vm/ directory
- [ ] VM terraform apply creates working VM
- [ ] Both approaches deploy correct homedir files
- [ ] All pre-commit hooks pass on all files
- [ ] Documentation renders correctly
- [ ] All internal documentation links work
- [ ] Git status shows only intended changes

## Critical Path References

### Container Files to Update
- `Dockerfile`: Change all COPY paths from `files/` to `../common/`
- `Dockerfile`: Add package file reading logic
- `start-work`: Verify no hardcoded paths need updating
- Any script that references file locations

### VM Files to Update
- `main.tf`: Add locals to read package files
- `main.tf`: Update templatefile() call with package variables
- `main.tf`: Update homedir files reading path
- `cloud-init.yaml.tftpl`: Replace hardcoded packages with variables
- `cloud-init.yaml.tftpl`: Update homedir template path
- All `vm-*.sh` scripts: Check for hardcoded paths

## Success Criteria

1. ✅ Both approaches work identically to before
2. ✅ No duplicated configuration files
3. ✅ No duplicated package lists
4. ✅ Clear directory structure
5. ✅ Gateway documentation guides users
6. ✅ All pre-commit checks pass
7. ✅ All documentation links work
8. ✅ Git history shows clean refactoring

## Risks & Mitigations

**Risk:** Missing path references break functionality
**Mitigation:** Two-phase testing (before and after cleanup)

**Risk:** Package file format parsing issues
**Mitigation:** Simple line-based format, well-tested consumption patterns

**Risk:** Documentation links break
**Mitigation:** Explicit verification step for all links

**Risk:** Pre-commit hook failures on reorganized files
**Mitigation:** Run pre-commit throughout process, not just at end

## Future Considerations

- Could add CI/CD tests for both approaches
- Could add automated link checking for documentation
- Could extract more shared resources if patterns emerge
- Package version updates could be automated with Renovate
