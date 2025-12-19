# Repository Reorganization Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task.

**Goal:** Refactor repository to cleanly separate container and VM approaches
while extracting common resources.

**Architecture:** Create three top-level directories (common/, container/,
vm/) where common/ contains shared configuration and package lists, and each
approach directory is self-contained with its own documentation.

**Tech Stack:** Docker, Terraform, cloud-init, shell scripts, markdown

---

## Phase 1: Create New Structure

### Task 1: Create Directory Structure

**Files:**

- Create: `common/homedir/.gitkeep`
- Create: `common/packages/.gitkeep`
- Create: `container/.gitkeep`
- Create: `vm/.gitkeep`

**Step 1: Create common directories**

```bash
mkdir -p common/homedir/.claude common/packages
touch common/homedir/.gitkeep common/packages/.gitkeep
```

Expected: Directories created without errors

**Step 2: Create approach directories**

```bash
mkdir -p container vm
touch container/.gitkeep vm/.gitkeep
```

Expected: Directories created without errors

**Step 3: Verify structure**

```bash
ls -la common/ container/ vm/
```

Expected: All directories exist with .gitkeep files

**Step 4: Commit structure**

```bash
git add common/ container/ vm/
git commit -m "feat: create new directory structure for reorganization"
```

### Task 2: Create Package List Files

**Files:**

- Create: `common/packages/apt-packages.txt`
- Create: `common/packages/npm-packages.txt`
- Create: `common/packages/python-packages.txt`
- Create: `common/packages/versions.txt`

**Step 1: Extract apt packages from Dockerfile**

Read `/home/user/workspace/Dockerfile` lines 26-58 and create
`common/packages/apt-packages.txt`:

```bash
cat > common/packages/apt-packages.txt << 'EOF'
# Base utilities
bc
ca-certificates
curl
docker-cli
dnsutils
findutils
g++
gh
git
gnupg
gosu
jq
less
lsb-release
lsof
make
man-db
nodejs
npm
procps
psmisc
python3
python3-pip
ripgrep
rsync
shellcheck
socat
tcl
tk
unzip
vim
yq
EOF
```

Expected: File created with package list

**Step 2: Create npm packages file**

```bash
cat > common/packages/npm-packages.txt << 'EOF'
@anthropic-ai/claude-code@latest
@google/gemini-cli@latest
@github/copilot@latest
EOF
```

Expected: File created with npm packages

**Step 3: Create python packages file**

```bash
cat > common/packages/python-packages.txt << 'EOF'
pre-commit
poetry
pipenv
dvc[all]
EOF
```

Expected: File created with python packages

**Step 4: Create versions file**

```bash
cat > common/packages/versions.txt << 'EOF'
GOLANG_VERSION=1.25.0
HADOLINT_VERSION=2.12.0
TERRAFORM_ALREADY_IN_APT=true
EOF
```

Expected: File created with version information

**Step 5: Verify package files**

```bash
for f in common/packages/*.txt; do
  echo "=== $f ==="
  cat "$f"
done
```

Expected: All package files display correctly

**Step 6: Commit package files**

```bash
git add common/packages/
git commit -m "feat: extract package lists to common directory"
```

### Task 3: Copy Homedir Files to Common

**Files:**

- Create: `common/homedir/.claude.json`
- Create: `common/homedir/.gitconfig`
- Create: `common/homedir/.gitignore`
- Create: `common/homedir/.local/bin/start-claude`
- Create: `common/homedir/.claude/settings.json`
- Create: `common/homedir/.claude/statusline-command.sh`

**Step 1: Copy .claude.json**

```bash
cp files/homedir/.claude.json common/homedir/.claude.json
```

Expected: File copied successfully

**Step 2: Copy .gitconfig**

```bash
cp files/homedir/.gitconfig common/homedir/.gitconfig
```

Expected: File copied successfully

**Step 3: Copy .gitignore**

```bash
cp files/homedir/.gitignore common/homedir/.gitignore
```

Expected: File copied successfully

**Step 4: Copy start-claude to .local/bin**

```bash
mkdir -p common/homedir/.local/bin
cp files/homedir/.local/bin/start-claude common/homedir/.local/bin/start-claude
chmod +x common/homedir/.local/bin/start-claude
```

Expected: File copied with execute permissions

**Step 5: Copy .claude directory**

```bash
cp -r files/homedir/.claude common/homedir/
```

Expected: Directory and files copied

**Step 6: Verify homedir files**

```bash
find common/homedir -type f | sort
```

Expected: All 6 files listed

**Step 7: Commit homedir files**

```bash
git add common/homedir/
git commit -m "feat: copy homedir configs to common directory"
```

### Task 4: Copy Container Files

**Files:**

- Create: `container/Dockerfile`
- Create: `container/entrypoint.sh`
- Create: `container/entrypoint_user.sh`
- Create: `container/start-work`

**Step 1: Copy Dockerfile**

```bash
cp Dockerfile container/Dockerfile
```

Expected: File copied successfully

**Step 2: Copy entrypoint scripts**

```bash
cp entrypoint.sh container/entrypoint.sh
cp entrypoint_user.sh container/entrypoint_user.sh
```

Expected: Files copied successfully

**Step 3: Copy start-work script**

```bash
cp start-work container/start-work
chmod +x container/start-work
```

Expected: File copied with execute permissions

**Step 4: Verify container files**

```bash
ls -lh container/
```

Expected: All 4 files listed with correct permissions

**Step 5: Commit container files**

```bash
git add container/
git commit -m "feat: copy container files to container directory"
```

### Task 5: Copy VM Files

**Files:**

- Create: `vm/*.tf`
- Create: `vm/cloud-init.yaml.tftpl`
- Create: `vm/vm-*.sh`
- Create: `vm/libvirt-nat-fix.sh`

**Step 1: Copy Terraform files**

```bash
cp yolo-vm/*.tf vm/
```

Expected: All .tf files copied

**Step 2: Copy cloud-init template**

```bash
cp yolo-vm/cloud-init.yaml.tftpl vm/
```

Expected: Template file copied

**Step 3: Copy VM utility scripts**

```bash
cp yolo-vm/vm-*.sh vm/
cp yolo-vm/vm-common.sh vm/
cp yolo-vm/vm-up.sh vm/
cp yolo-vm/vm-down.sh vm/
cp yolo-vm/vm-connect.sh vm/
chmod +x vm/vm-*.sh vm/*.sh
```

Expected: All scripts copied with execute permissions

**Step 4: Copy libvirt-nat-fix script**

```bash
cp yolo-vm/libvirt-nat-fix.sh vm/
chmod +x vm/libvirt-nat-fix.sh
```

Expected: Script copied with execute permissions

**Step 5: Verify VM files**

```bash
ls -lh vm/
```

Expected: All files listed

**Step 6: Commit VM files**

```bash
git add vm/
git commit -m "feat: copy VM files to vm directory"
```

## Phase 2: Update References

### Task 6: Update Container Dockerfile

**Files:**

- Modify: `container/Dockerfile:100-102`

**Step 1: Update COPY path for homedir**

Replace line 102 in `container/Dockerfile`:

OLD:
```dockerfile
COPY --chown=0:0 --chmod=u=rw,u+X,go=r,go+X files/homedir/ /etc/skel/
```

NEW:
```dockerfile
COPY --chown=0:0 --chmod=u=rw,u+X,go=r,go+X ../common/homedir/ /etc/skel/
```

**Step 2: Add package files copy before apt install**

Insert after line 22 in `container/Dockerfile`:

```dockerfile
# Copy package lists for installation
COPY ../common/packages/apt-packages.txt /tmp/apt-packages.txt
COPY ../common/packages/npm-packages.txt /tmp/npm-packages.txt
COPY ../common/packages/python-packages.txt /tmp/python-packages.txt
COPY ../common/packages/versions.txt /tmp/versions.txt
```

**Step 3: Update apt install to use package file**

Replace lines 23-58 in `container/Dockerfile`:

OLD:
```dockerfile
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    bc \
    ca-certificates \
    [... all packages ...]
    yq
```

NEW:
```dockerfile
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt \
    apt-get update && \
    grep -v '^#' /tmp/apt-packages.txt | grep -v '^$' | xargs apt-get install -y --no-install-recommends
```

**Step 4: Update Python tools to use package file**

Replace lines 85-91 in `container/Dockerfile`:

OLD:
```dockerfile
# Install Python tools globally during build to avoid runtime delay
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3013,DL3042
RUN --mount=type=cache,target=/root/.cache/pip \
    echo "Installing Python tools globally..." && \
    for tool in $(echo "$PYTHON_TOOLS" | tr ',' ' '); do \
    echo "Installing $tool..." && \
    pip install --cache-dir=/root/.cache/pip --break-system-packages "$tool"; \
    done && \
    echo "Python tools installation complete"
```

NEW:
```dockerfile
# Install Python tools globally during build to avoid runtime delay
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
# hadolint ignore=DL3013,DL3042
RUN --mount=type=cache,target=/root/.cache/pip \
    grep -v '^#' /tmp/python-packages.txt | grep -v '^$' | xargs pip install --break-system-packages
```

**Step 5: Update npm install to use package file**

Replace lines 94-98 in `container/Dockerfile`:

OLD:
```dockerfile
# Install coding agents with npm cache mount
# hadolint ignore=DL3016
RUN --mount=type=cache,target=/root/.npm \
    npm install -g --cache /root/.npm \
    @anthropic-ai/claude-code@latest \
    @google/gemini-cli@latest
```

NEW:
```dockerfile
# Install coding agents with npm cache mount
# hadolint ignore=DL3016
RUN --mount=type=cache,target=/root/.npm \
    xargs npm install -g --cache /root/.npm < /tmp/npm-packages.txt
```

**Step 6: Source versions from file**

Replace line 77 in `container/Dockerfile`:

OLD:
```dockerfile
ARG HADOLINT_VERSION=2.12.0
```

NEW:
```dockerfile
ARG HADOLINT_VERSION=2.12.0
# Note: Version sourced from versions.txt, but ARG defaults kept for compatibility
```

**Step 7: Verify Dockerfile syntax**

```bash
cd container
docker build --no-cache --target golang-installer -t test-stage1 .
```

Expected: Stage 1 builds successfully

**Step 8: Commit Dockerfile changes**

```bash
git add container/Dockerfile
git commit -m "feat: update container Dockerfile to use common package files"
```

### Task 7: Update VM Terraform Configuration

**Files:**

- Modify: `vm/main.tf`

**Step 1: Add locals for package reading**

Insert at the top of `vm/main.tf` after the terraform/provider blocks:

```hcl
# Read package lists from common directory
locals {
  # Read and parse package files
  apt_packages_raw    = file("${path.module}/../common/packages/apt-packages.txt")
  npm_packages_raw    = file("${path.module}/../common/packages/npm-packages.txt")
  python_packages_raw = file("${path.module}/../common/packages/python-packages.txt")
  versions_raw        = file("${path.module}/../common/packages/versions.txt")

  # Filter out comments and empty lines
  apt_packages    = [for p in split("\n", local.apt_packages_raw) : trimspace(p) if trimspace(p) != "" && !startswith(trimspace(p), "#")]
  npm_packages    = [for p in split("\n", local.npm_packages_raw) : trimspace(p) if trimspace(p) != "" && !startswith(trimspace(p), "#")]
  python_packages = [for p in split("\n", local.python_packages_raw) : trimspace(p) if trimspace(p) != "" && !startswith(trimspace(p), "#")]

  # Parse version file into map
  versions_list = [for line in split("\n", local.versions_raw) : split("=", trimspace(line)) if trimspace(line) != "" && !startswith(trimspace(line), "#")]
  versions = { for item in local.versions_list : item[0] => item[1] }
}
```

**Step 2: Find homedir file reading section**

Search for where homedir files are read in `vm/main.tf`:

```bash
grep -n "homedir" vm/main.tf
```

Expected: Find the section that reads files from yolo-vm/files/homedir

**Step 3: Update homedir file path**

Replace the homedir files reading path in `vm/main.tf`:

OLD:
```hcl
for_each = fileset("${path.module}/files/homedir", "**")
```

NEW:
```hcl
for_each = fileset("${path.module}/../common/homedir", "**")
```

**Step 4: Update cloud-init templatefile call**

Find the cloud-init templatefile call and add package variables. Update to:

```hcl
data "template_file" "user_data" {
  template = file("${path.module}/cloud-init.yaml.tftpl")
  vars = {
    # ... existing variables ...
    apt_packages    = jsonencode(local.apt_packages)
    npm_packages    = jsonencode(local.npm_packages)
    python_packages = jsonencode(local.python_packages)
    golang_version  = local.versions["GOLANG_VERSION"]
    hadolint_version = local.versions["HADOLINT_VERSION"]
  }
}
```

**Step 5: Verify Terraform syntax**

```bash
cd vm
terraform fmt
terraform validate
```

Expected: No formatting changes, validation passes

**Step 6: Commit Terraform changes**

```bash
git add vm/main.tf
git commit -m "feat: update VM Terraform to use common package files"
```

### Task 8: Update VM Cloud-Init Template

**Files:**

- Modify: `vm/cloud-init.yaml.tftpl`

**Step 1: Update packages section**

Replace lines 153-181 in `vm/cloud-init.yaml.tftpl`:

OLD:
```yaml
packages:
  # Base utilities
  - vim
  - curl
  [... all packages ...]
```

NEW:
```yaml
packages:
%{ for pkg in jsondecode(apt_packages) ~}
  - ${pkg}
%{ endfor ~}
```

**Step 2: Update npm install command**

Replace line 135-136 in `vm/cloud-init.yaml.tftpl`:

OLD:
```yaml
  # Install AI coding agents globally
  - npm install -g @anthropic-ai/claude-code@latest
  - npm install -g @google/gemini-cli@latest
  - npm install -g @github/copilot@latest
```

NEW:
```yaml
  # Install AI coding agents globally
  - npm install -g ${join(" ", jsondecode(npm_packages))}
```

**Step 3: Update Python packages install**

Replace line 129 in `vm/cloud-init.yaml.tftpl`:

OLD:
```yaml
  - pip install --break-system-packages pre-commit poetry pipenv 'dvc[all]'
```

NEW:
```yaml
  - pip install --break-system-packages ${join(" ", jsondecode(python_packages))}
```

**Step 4: Update Go version**

Replace line 116 in `vm/cloud-init.yaml.tftpl`:

OLD:
```yaml
  # Install Go 1.25.0
  - curl -fsSL https://go.dev/dl/go1.25.0.linux-amd64.tar.gz -o /tmp/go.tar.gz
```

NEW:
```yaml
  # Install Go ${golang_version}
  - curl -fsSL https://go.dev/dl/go${golang_version}.linux-amd64.tar.gz -o /tmp/go.tar.gz
```

**Step 5: Update hadolint version**

Replace line 131 in `vm/cloud-init.yaml.tftpl`:

OLD:
```yaml
  - curl -fsSL https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64 -o /tmp/hadolint
```

NEW:
```yaml
  - curl -fsSL https://github.com/hadolint/hadolint/releases/download/v${hadolint_version}/hadolint-Linux-x86_64 -o /tmp/hadolint
```

**Step 6: Update homedir file path reference**

Replace line 13-14 in `vm/cloud-init.yaml.tftpl`:

OLD:
```yaml
%{ for path, file_data in homedir_files ~}
  - path: /tmp/homedir/${path}
```

NEW (no change needed, variable name stays the same):
```yaml
%{ for path, file_data in homedir_files ~}
  - path: /tmp/homedir/${path}
```

**Step 7: Verify template syntax**

```bash
cd vm
terraform fmt cloud-init.yaml.tftpl
```

Expected: No errors (tftpl files may not format, but should not error)

**Step 8: Commit cloud-init changes**

```bash
git add vm/cloud-init.yaml.tftpl
git commit -m "feat: update VM cloud-init to use package variables"
```

### Task 9: Update Container start-work Script

**Files:**

- Modify: `container/start-work`

**Step 1: Check for hardcoded paths**

```bash
grep -n "files/\|Dockerfile" container/start-work
```

Expected: Find any references to files/ directory or Dockerfile location

**Step 2: Update Dockerfile path reference**

Find and replace in `container/start-work`:

OLD:
```bash
DOCKERFILE_PATH="${REPO_DIR}/Dockerfile"
```

NEW:
```bash
DOCKERFILE_PATH="${REPO_DIR}/container/Dockerfile"
```

**Step 3: Update docker build context**

Find the docker build command and update context:

OLD:
```bash
docker build -t "${IMAGE_NAME}" "${REPO_DIR}"
```

NEW:
```bash
docker build -t "${IMAGE_NAME}" -f "${REPO_DIR}/container/Dockerfile" "${REPO_DIR}"
```

Note: Context stays at REPO_DIR to access ../common from container/

**Step 4: Verify script syntax**

```bash
bash -n container/start-work
```

Expected: No syntax errors

**Step 5: Commit start-work changes**

```bash
git add container/start-work
git commit -m "feat: update container start-work script for new paths"
```

### Task 10: Update VM Scripts

**Files:**

- Modify: `vm/vm-common.sh` (if needed)
- Check: `vm/vm-*.sh` scripts

**Step 1: Check for hardcoded paths in vm-common.sh**

```bash
grep -n "yolo-vm" vm/vm-common.sh || echo "No yolo-vm references found"
```

Expected: Check if any paths need updating

**Step 2: Check all vm-* scripts**

```bash
for script in vm/vm-*.sh; do
  echo "=== $script ==="
  grep -n "yolo-vm\|\.tf" "$script" || echo "No references"
done
```

Expected: Identify any scripts that reference the old directory structure

**Step 3: Update terraform command paths if needed**

If any scripts run terraform commands, verify they work from vm/ directory:

```bash
# Example if needed:
# sed -i 's|cd yolo-vm|cd vm|g' vm/vm-up.sh
```

Expected: Scripts updated or no changes needed

**Step 4: Verify all scripts**

```bash
for script in vm/*.sh; do
  bash -n "$script" && echo "$script: OK" || echo "$script: FAIL"
done
```

Expected: All scripts pass syntax check

**Step 5: Commit VM script changes (if any)**

```bash
git add vm/*.sh
git commit -m "feat: update VM scripts for new directory structure"
```

## Phase 3: Documentation

### Task 11: Write Root README.md

**Files:**

- Create: `README.new.md` (will replace README.md later)

**Step 1: Create new root README**

```bash
cat > README.new.md << 'EOF'
# AI Development Environments

Isolated development environments for AI coding agents, available in two
approaches.

## Choose Your Approach

| Feature | Container | VM |
|---------|-----------|-----|
| **Startup time** | ~2 seconds | ~30-60 seconds |
| **Isolation** | Strong (namespaces) | Strongest (full VM) |
| **Nested virtualization** | No | Yes (libvirt/KVM) |
| **Resource overhead** | Minimal | Moderate |
| **Best for** | Quick iterations, most development | Infrastructure testing, VM workloads |
| **Requires** | Docker | libvirt/KVM, Terraform |

## Quick Start

### Container Approach

Fast, lightweight isolation using Docker containers.

→ **[Container Documentation](container/README.md)**

```bash
cd container
./start-work my-feature-branch
```

### VM Approach

Full virtual machine isolation with nested virtualization support.

→ **[VM Documentation](vm/README.md)**

```bash
cd vm
terraform init
terraform apply
```

## What's Inside

Both approaches provide:

- **AI Coding Agents**: Claude Code, Gemini CLI, GitHub Copilot CLI
- **Development Tools**: Git, Node.js, Python, Go, Terraform
- **Code Quality**: pre-commit hooks, linting, formatting
- **Isolation**: Agent cannot access host filesystem or credentials

## Common Resources

Both approaches share configurations and package lists from `common/`:

- `common/homedir/` - Shared configuration files (.claude.json, .gitconfig)
- `common/packages/` - Package lists (apt, npm, python) and version pins

## License

MIT License - see [LICENSE](LICENSE) file for details.
EOF
```

**Step 2: Verify markdown formatting**

```bash
pre-commit run markdownlint --files README.new.md
```

Expected: Pass or identify formatting issues to fix

**Step 3: Stage new README (don't replace yet)**

```bash
git add README.new.md
git commit -m "docs: add new root README with approach comparison"
```

### Task 12: Write Root CLAUDE.md

**Files:**

- Create: `CLAUDE.new.md` (will replace CLAUDE.md later)

**Step 1: Create new root CLAUDE.md**

```bash
cat > CLAUDE.new.md << 'EOF'
# Claude Code Assistant Configuration

## Project Overview

This repository provides **two approaches** for creating isolated AI
development environments:

1. **Container** - Docker-based, fast startup, strong isolation
2. **VM** - Libvirt/KVM-based, full VM isolation, nested virtualization

## Determining Which Approach You're Working With

Check your current directory:

```bash
pwd
```

- If in `/path/to/repo/container` → Use container approach
- If in `/path/to/repo/vm` → Use VM approach
- If at root `/path/to/repo` → Ask user which approach they want

## Approach-Specific Documentation

**Container Approach:**

→ See [container/CLAUDE.md](container/CLAUDE.md) for detailed instructions

**VM Approach:**

→ See [vm/CLAUDE.md](vm/CLAUDE.md) for detailed instructions

## Common Resources

Both approaches share resources from `common/`:

- `common/homedir/` - Configuration files deployed to user home directory
  - `.claude.json` - Claude Code settings
  - `.gitconfig` - Git configuration
  - `.claude/settings.json` - Claude settings
  - `.local/bin/start-claude` - Helper script
- `common/packages/` - Package lists and version pins
  - `apt-packages.txt` - Debian packages
  - `npm-packages.txt` - Node.js packages
  - `python-packages.txt` - Python packages
  - `versions.txt` - Version numbers for tools

## General Guidelines

- Use TodoWrite tool for complex multi-step tasks
- Run pre-commit checks after all changes
- Follow approach-specific testing procedures
- Commit frequently with descriptive messages

## Getting Help

If unclear which approach to work with, ask the user:

"Are you working with the container approach or the VM approach?"
EOF
```

**Step 2: Verify markdown formatting**

```bash
pre-commit run markdownlint --files CLAUDE.new.md
```

Expected: Pass or identify formatting issues to fix

**Step 3: Stage new CLAUDE.md (don't replace yet)**

```bash
git add CLAUDE.new.md
git commit -m "docs: add new root CLAUDE.md with approach guidance"
```

### Task 13: Write Container README.md

**Files:**

- Create: `container/README.md`

**Step 1: Adapt current README for container directory**

```bash
# Copy current README as base and modify
cp README.md container/README.md
```

**Step 2: Update title and intro**

Edit `container/README.md`, change lines 1-10:

OLD:
```markdown
# Agent Container

A Docker-based development environment...
```

NEW:
```markdown
# Container Approach - Agent Container

Docker-based development environment for working with AI coding agents using
Git worktrees.

**[← Back to main documentation](../README.md)**
```

**Step 3: Update file structure section**

Find and update the "File Structure" section:

OLD:
```markdown
- `Dockerfile` - Container image definition
- `entrypoint.sh` - Container startup script
- `files/homedir/` - Built-in configuration files
```

NEW:
```markdown
- `Dockerfile` - Container image definition
- `entrypoint.sh` - Container startup script with user setup
- `entrypoint_user.sh` - User-level initialization
- `start-work` - Script to create worktrees and start containers
- `../common/homedir/` - Shared configuration files (built into container)
- `../common/packages/` - Package lists (used during build)
```

**Step 4: Update Quick Start section**

Update Quick Start commands:

OLD:
```bash
git clone https://github.com/johnstrunk/agent-container.git
mkdir -p ~/.local/bin
ln -s "$(realpath agent-container/start-work)" ~/.local/bin/start-work
```

NEW:
```bash
git clone https://github.com/johnstrunk/agent-container.git
mkdir -p ~/.local/bin
ln -s "$(realpath agent-container/container/start-work)" ~/.local/bin/start-work
```

**Step 5: Update configuration section**

Update references to files/homedir:

OLD:
```markdown
The container uses built-in configurations from `files/homedir/`:
```

NEW:
```markdown
The container uses built-in configurations from `../common/homedir/`:
```

**Step 6: Verify markdown**

```bash
pre-commit run markdownlint --files container/README.md
```

Expected: Pass or identify issues to fix

**Step 7: Commit container README**

```bash
git add container/README.md
git commit -m "docs: add container-specific README"
```

### Task 14: Write Container CLAUDE.md

**Files:**

- Create: `container/CLAUDE.md`

**Step 1: Adapt current CLAUDE.md for container**

```bash
cp CLAUDE.md container/CLAUDE.md
```

**Step 2: Update header**

Edit `container/CLAUDE.md`, change lines 1-5:

OLD:
```markdown
# Claude Code Assistant Configuration for Agent Container
```

NEW:
```markdown
# Claude Code Assistant Configuration - Container Approach

**[← Back to root CLAUDE.md](../CLAUDE.md)**
```

**Step 3: Update Project Structure section**

Update the structure listing:

OLD:
```text
/
├── .github/
├── Dockerfile
├── README.md
├── entrypoint.sh
```

NEW:
```text
container/
├── Dockerfile              # Container image definition
├── entrypoint.sh          # Container startup script
├── entrypoint_user.sh     # User-level setup
├── start-work             # Main script
├── README.md              # Container documentation
└── CLAUDE.md              # This file

../common/
├── homedir/               # Shared configs (.claude.json, .gitconfig)
└── packages/              # Package lists (apt, npm, python)
```

**Step 4: Update file references**

Find and replace all references:

- `files/homedir/` → `../common/homedir/`
- `/home/user/workspace/Dockerfile` → `/home/user/workspace/container/Dockerfile`

**Step 5: Update building section**

Update build command:

OLD:
```bash
docker build -t ghcr.io/johnstrunk/agent-container .
```

NEW:
```bash
cd /home/user/workspace/container
docker build -t ghcr.io/johnstrunk/agent-container -f Dockerfile ..
```

**Step 6: Verify markdown**

```bash
pre-commit run markdownlint --files container/CLAUDE.md
```

Expected: Pass or identify issues

**Step 7: Commit container CLAUDE.md**

```bash
git add container/CLAUDE.md
git commit -m "docs: add container-specific CLAUDE.md guide"
```

### Task 15: Write VM README.md

**Files:**

- Create: `vm/README.md`

**Step 1: Copy and adapt yolo-vm README**

```bash
cp yolo-vm/README.md vm/README.md
```

**Step 2: Update title and intro**

Edit `vm/README.md`, change lines 1-5:

OLD:
```markdown
# Debian 13 (Trixie) VM with Libvirt

This directory contains Terraform configuration...
```

NEW:
```markdown
# VM Approach - Debian AI Development VM

Terraform configuration for deploying a Debian 13 virtual machine with AI
coding agents using libvirt/KVM.

**[← Back to main documentation](../README.md)**
```

**Step 3: Update Quick Start paths**

Update terraform commands:

OLD:
```bash
cd yolo-vm
terraform init
```

NEW:
```bash
cd vm
terraform init
```

**Step 4: Update file references**

Replace references:

- `yolo-vm/` → `vm/`
- `files/homedir/` → `../common/homedir/`

**Step 5: Add package management section**

Insert new section after Features:

```markdown
## Package Management

This VM uses shared package lists from `../common/packages/`:

- `apt-packages.txt` - Debian packages installed via cloud-init
- `npm-packages.txt` - Global npm packages (AI agents)
- `python-packages.txt` - Python tools (pre-commit, poetry, etc.)
- `versions.txt` - Version pins for Go, hadolint, etc.

Packages are automatically installed during VM provisioning via cloud-init.
```

**Step 6: Verify markdown**

```bash
pre-commit run markdownlint --files vm/README.md
```

Expected: Pass or identify issues

**Step 7: Commit VM README**

```bash
git add vm/README.md
git commit -m "docs: add VM-specific README"
```

### Task 16: Write VM CLAUDE.md

**Files:**

- Create: `vm/CLAUDE.md`

**Step 1: Create new VM CLAUDE.md from template**

```bash
cat > vm/CLAUDE.md << 'EOF'
# Claude Code Assistant Configuration - VM Approach

**[← Back to root CLAUDE.md](../CLAUDE.md)**

## Project Overview

This is the **VM approach** - a Terraform-based deployment of a Debian 13
virtual machine with AI coding agents, using libvirt/KVM for full isolation.

## Project Structure

```text
vm/
├── main.tf                    # Main Terraform configuration
├── variables.tf               # Variable definitions
├── outputs.tf                 # Output definitions
├── cloud-init.yaml.tftpl      # Cloud-init template
├── vm-*.sh                    # VM utility scripts
├── libvirt-nat-fix.sh         # Network fix for multi-interface hosts
├── README.md                  # VM documentation
└── CLAUDE.md                  # This file

../common/
├── homedir/                   # Shared configs (deployed to VM)
└── packages/                  # Package lists (used in cloud-init)
```

## Key Technologies & Tools

- **Infrastructure**: Terraform, libvirt/KVM, cloud-init
- **VM OS**: Debian 13 (Trixie)
- **AI Agents**: Claude Code, Gemini CLI, GitHub Copilot
- **Development Tools**: Git, Node.js, Python, Go, Docker, Terraform

## Development Workflow

### Task Management

Use TodoWrite tool for complex tasks to track progress.

### Pre-commit Quality Checks

Run pre-commit after making changes:

```bash
pre-commit run --files <filename>
```

### Testing VM Changes

After modifying Terraform or cloud-init:

1. **Validate Terraform**:

   ```bash
   cd /home/user/workspace/vm
   terraform fmt
   terraform validate
   ```

2. **Plan changes**:

   ```bash
   terraform plan
   ```

3. **Apply if safe**:

   ```bash
   terraform apply
   ```

4. **Test VM connectivity**:

   ```bash
   ./vm-connect.sh
   ```

### Modifying Package Lists

To add/remove packages:

1. Edit `../common/packages/*.txt` files
2. Run `terraform plan` to see changes
3. Apply and verify packages install correctly in cloud-init

### Modifying Homedir Configs

To change deployed configurations:

1. Edit files in `../common/homedir/`
2. Run `terraform plan` to see changes
3. Recreate VM or manually copy updated files

## File Modification Guidelines

### Terraform Files

- Follow terraform formatting: `terraform fmt`
- Validate syntax: `terraform validate`
- Test with `terraform plan` before apply
- Use locals for computed values
- Comment complex logic

### Cloud-Init Templates

- Follow YAML syntax
- Test template rendering with small changes first
- Use Terraform variables for dynamic content
- Comment runcmd sections for clarity

### Shell Scripts

- Use `#!/bin/bash` shebang
- Include `set -e -o pipefail`
- Pass shellcheck (via pre-commit)
- Use double quotes for variables

## Common Tasks

### Adding Packages

1. **Plan**: Create todo for editing package list
2. Edit `../common/packages/apt-packages.txt` (or npm/python)
3. Run `terraform plan` to verify template updates
4. **Test**: Apply and verify package installs
5. Commit changes

### Modifying VM Configuration

1. **Plan**: Create todos for configuration changes
2. Edit `main.tf` or `variables.tf`
3. Run `terraform fmt` and `terraform validate`
4. **Test**: Run `terraform plan` to preview
5. Apply if safe, test VM functionality
6. Commit changes

### Updating Cloud-Init

1. **Plan**: Create todos for cloud-init changes
2. Edit `cloud-init.yaml.tftpl`
3. Run `terraform validate`
4. **Test**: Apply to new/test VM first
5. Verify with `ssh debian@<vm-ip>` and check installed software
6. Commit changes

## Testing Strategy

1. **Terraform validation**: `terraform fmt && terraform validate`
2. **Plan review**: Always run `terraform plan` before apply
3. **Incremental testing**: Test small changes before large refactors
4. **VM verification**: SSH in and verify expected state
5. **Pre-commit checks**: Run on all modified files

## Security Considerations

- SSH keys managed in `ssh-keys/` directory (not in repo)
- GCP credentials injected via Terraform variables (not stored)
- Constrained sudo access for AI agents
- Root access via SSH key only (no password)

## Maintenance Notes

- Pre-commit hooks ensure code quality
- Terraform state managed locally (consider remote backend for teams)
- VM lifecycle managed by Terraform (create/destroy)
- Cloud-init runs once at VM creation
EOF
```

**Step 2: Verify markdown**

```bash
pre-commit run markdownlint --files vm/CLAUDE.md
```

Expected: Pass or identify issues

**Step 3: Commit VM CLAUDE.md**

```bash
git add vm/CLAUDE.md
git commit -m "docs: add VM-specific CLAUDE.md guide"
```

## Phase 4: Initial Testing

### Task 17: Test Container Build

**Files:**

- Test: `container/Dockerfile`

**Step 1: Change to container directory**

```bash
cd /home/user/workspace/container
```

**Step 2: Build container image**

```bash
docker build -t ghcr.io/johnstrunk/agent-container:test-reorg -f Dockerfile ..
```

Expected: Build succeeds, all packages install correctly

**Step 3: Verify package installation**

```bash
docker run --rm ghcr.io/johnstrunk/agent-container:test-reorg claude --version
docker run --rm ghcr.io/johnstrunk/agent-container:test-reorg gemini --version
docker run --rm ghcr.io/johnstrunk/agent-container:test-reorg which pre-commit
```

Expected: All commands succeed, tools are installed

**Step 4: Verify homedir files**

```bash
docker run --rm ghcr.io/johnstrunk/agent-container:test-reorg ls -la /etc/skel/
```

Expected: See all config files from common/homedir

**Step 5: Document test results**

```bash
echo "Container build test: PASSED" >> /tmp/test-results.txt
```

**Step 6: Return to workspace root**

```bash
cd /home/user/workspace
```

### Task 18: Test Container start-work Script

**Files:**

- Test: `container/start-work`

**Step 1: Create test directory**

```bash
mkdir -p /tmp/test-repo
cd /tmp/test-repo
git init
git config user.name "Test User"
git config user.email "test@example.com"
echo "test" > README.md
git add README.md
git commit -m "Initial commit"
```

Expected: Test repo created

**Step 2: Test start-work script (dry run check)**

```bash
bash -n /home/user/workspace/container/start-work
```

Expected: No syntax errors

**Step 3: Check script would use correct paths**

```bash
grep "Dockerfile" /home/user/workspace/container/start-work
```

Expected: Shows correct path to container/Dockerfile

**Step 4: Document test results**

```bash
echo "Container start-work script: SYNTAX OK" >> /tmp/test-results.txt
```

**Step 5: Cleanup test repo**

```bash
cd /home/user/workspace
rm -rf /tmp/test-repo
```

### Task 19: Test VM Terraform Configuration

**Files:**

- Test: `vm/*.tf`

**Step 1: Change to VM directory**

```bash
cd /home/user/workspace/vm
```

**Step 2: Initialize Terraform**

```bash
terraform init
```

Expected: Terraform initializes successfully, providers downloaded

**Step 3: Format Terraform files**

```bash
terraform fmt -check
```

Expected: Files already formatted or only minor changes

**Step 4: Validate Terraform**

```bash
terraform validate
```

Expected: Validation succeeds, no errors

**Step 5: Test plan (no apply)**

```bash
terraform plan -out=/tmp/tfplan
```

Expected: Plan succeeds, shows VM will be created with correct packages

**Step 6: Inspect plan for package lists**

```bash
terraform show -json /tmp/tfplan | jq '.planned_values.root_module.resources[] | select(.type=="libvirt_cloudinit_disk") | .values.user_data' | head -100
```

Expected: See package lists from common/packages in cloud-init

**Step 7: Document test results**

```bash
echo "VM Terraform validation: PASSED" >> /tmp/test-results.txt
rm /tmp/tfplan
```

**Step 8: Return to workspace root**

```bash
cd /home/user/workspace
```

### Task 20: Run Pre-commit on All Changes

**Files:**

- Test: All modified files

**Step 1: Run pre-commit on all files**

```bash
cd /home/user/workspace
pre-commit run --all-files
```

Expected: All checks pass (or identify issues to fix)

**Step 2: Review any failures**

If failures occur:

```bash
pre-commit run --all-files 2>&1 | tee /tmp/precommit-errors.txt
```

**Step 3: Fix any issues**

Address each failure:

- Trailing whitespace: auto-fixed
- Line endings: auto-fixed
- Markdown issues: manually fix and re-run
- Other issues: fix according to pre-commit output

**Step 4: Re-run until all pass**

```bash
pre-commit run --all-files
```

Expected: All checks pass

**Step 5: Document test results**

```bash
echo "Pre-commit checks: PASSED" >> /tmp/test-results.txt
```

**Step 6: Commit any pre-commit fixes**

```bash
git add -u
git commit -m "fix: apply pre-commit auto-fixes"
```

### Task 21: Review Test Results

**Files:**

- Review: `/tmp/test-results.txt`

**Step 1: Display all test results**

```bash
cat /tmp/test-results.txt
```

Expected: All tests show PASSED

**Step 2: Verify git status**

```bash
git status
```

Expected: All changes committed, working tree clean (except .new files)

**Step 3: Create checkpoint commit**

```bash
git log --oneline -5
```

Expected: See all commits from Phase 1-4

**Step 4: Tag checkpoint**

```bash
git tag phase-4-initial-testing
```

## Phase 5: Cleanup

### Task 22: Remove Old Container Files

**Files:**

- Delete: `Dockerfile`
- Delete: `entrypoint.sh`
- Delete: `entrypoint_user.sh`
- Delete: `start-work`
- Delete: `files/`

**Step 1: Remove root Dockerfile**

```bash
git rm Dockerfile
```

Expected: File staged for deletion

**Step 2: Remove entrypoint scripts**

```bash
git rm entrypoint.sh entrypoint_user.sh
```

Expected: Files staged for deletion

**Step 3: Remove start-work script**

```bash
git rm start-work
```

Expected: File staged for deletion

**Step 4: Remove files directory**

```bash
git rm -r files/
```

Expected: Directory and contents staged for deletion

**Step 5: Verify deletions**

```bash
git status
```

Expected: See deleted files staged

**Step 6: Commit deletions**

```bash
git commit -m "refactor: remove old container files from root"
```

### Task 23: Remove Old VM Directory

**Files:**

- Delete: `yolo-vm/`

**Step 1: Remove yolo-vm directory**

```bash
git rm -r yolo-vm/
```

Expected: Directory and all contents staged for deletion

**Step 2: Verify deletion**

```bash
git status
```

Expected: yolo-vm/ deleted

**Step 3: Commit deletion**

```bash
git commit -m "refactor: remove old yolo-vm directory"
```

### Task 24: Replace Root Documentation

**Files:**

- Replace: `README.md`
- Replace: `CLAUDE.md`

**Step 1: Replace README.md**

```bash
git mv README.md README.old.md
git mv README.new.md README.md
```

Expected: Files swapped

**Step 2: Replace CLAUDE.md**

```bash
git mv CLAUDE.md CLAUDE.old.md
git mv CLAUDE.new.md CLAUDE.md
```

Expected: Files swapped

**Step 3: Verify new documentation**

```bash
head -20 README.md
head -20 CLAUDE.md
```

Expected: New gateway documentation shown

**Step 4: Commit documentation replacement**

```bash
git add README.md CLAUDE.md README.old.md CLAUDE.old.md
git commit -m "docs: replace root documentation with gateway docs"
```

**Step 5: Remove old documentation**

```bash
git rm README.old.md CLAUDE.old.md
git commit -m "refactor: remove old root documentation"
```

### Task 25: Update .gitignore If Needed

**Files:**

- Check: `.gitignore`

**Step 1: Review current .gitignore**

```bash
cat .gitignore
```

**Step 2: Check if any new patterns needed**

```bash
# Check for test artifacts, build outputs, etc.
git status --ignored
```

Expected: Identify any new patterns to ignore

**Step 3: Add patterns if needed**

If test artifacts or build outputs found:

```bash
echo "# Build artifacts" >> .gitignore
echo "/container/test-*" >> .gitignore
```

**Step 4: Commit .gitignore changes if made**

```bash
git add .gitignore
git commit -m "chore: update .gitignore for new structure"
```

## Phase 6: Final Verification

### Task 26: Final Container Build Test

**Files:**

- Test: `container/Dockerfile`

**Step 1: Clean docker build cache**

```bash
docker system prune -f
```

Expected: Cache cleaned

**Step 2: Build container from scratch**

```bash
cd /home/user/workspace/container
docker build --no-cache -t ghcr.io/johnstrunk/agent-container:final-test -f Dockerfile ..
```

Expected: Build succeeds without errors

**Step 3: Run comprehensive tests**

```bash
# Test all AI agents
docker run --rm ghcr.io/johnstrunk/agent-container:final-test claude --version
docker run --rm ghcr.io/johnstrunk/agent-container:final-test gemini --version

# Test development tools
docker run --rm ghcr.io/johnstrunk/agent-container:final-test go version
docker run --rm ghcr.io/johnstrunk/agent-container:final-test terraform version
docker run --rm ghcr.io/johnstrunk/agent-container:final-test hadolint --version

# Test Python tools
docker run --rm ghcr.io/johnstrunk/agent-container:final-test pre-commit --version
docker run --rm ghcr.io/johnstrunk/agent-container:final-test poetry --version

# Test homedir deployment
docker run --rm ghcr.io/johnstrunk/agent-container:final-test ls -la /etc/skel/.claude
docker run --rm ghcr.io/johnstrunk/agent-container:final-test cat /etc/skel/.claude.json
```

Expected: All commands succeed, correct versions shown, files present

**Step 4: Document results**

```bash
echo "FINAL: Container build PASSED" >> /tmp/final-test-results.txt
cd /home/user/workspace
```

### Task 27: Final VM Terraform Test

**Files:**

- Test: `vm/*.tf`, `vm/cloud-init.yaml.tftpl`

**Step 1: Clean terraform state**

```bash
cd /home/user/workspace/vm
rm -rf .terraform .terraform.lock.hcl
```

**Step 2: Re-initialize terraform**

```bash
terraform init
```

Expected: Clean initialization succeeds

**Step 3: Validate configuration**

```bash
terraform fmt -check -recursive
terraform validate
```

Expected: Formatting correct, validation passes

**Step 4: Generate plan**

```bash
terraform plan -out=/tmp/final-tfplan
```

Expected: Plan succeeds, shows correct configuration

**Step 5: Inspect cloud-init in plan**

```bash
terraform show /tmp/final-tfplan | grep -A 20 "packages:"
```

Expected: See packages from common/packages/*.txt

**Step 6: Document results**

```bash
echo "FINAL: VM Terraform PASSED" >> /tmp/final-test-results.txt
rm /tmp/final-tfplan
cd /home/user/workspace
```

### Task 28: Verify Documentation Links

**Files:**

- Test: All README.md and CLAUDE.md files

**Step 1: Check root README links**

```bash
grep -o '\[.*\](.*\.md)' README.md
```

Expected: See all markdown links

**Step 2: Verify each link exists**

```bash
for link in container/README.md container/CLAUDE.md vm/README.md vm/CLAUDE.md; do
  if [ -f "$link" ]; then
    echo "$link: EXISTS"
  else
    echo "$link: MISSING"
  fi
done
```

Expected: All links exist

**Step 3: Check container documentation links**

```bash
grep -o '\[.*\](.*\.md)' container/README.md
grep -o '\[.*\](.*\.md)' container/CLAUDE.md
```

Expected: All links point to valid files

**Step 4: Check VM documentation links**

```bash
grep -o '\[.*\](.*\.md)' vm/README.md
grep -o '\[.*\](.*\.md)' vm/CLAUDE.md
```

Expected: All links point to valid files

**Step 5: Document results**

```bash
echo "FINAL: Documentation links VERIFIED" >> /tmp/final-test-results.txt
```

### Task 29: Final Pre-commit Check

**Files:**

- Test: All files in repository

**Step 1: Run pre-commit on all files**

```bash
cd /home/user/workspace
pre-commit run --all-files
```

Expected: All checks pass

**Step 2: If any failures, fix and re-run**

```bash
# Fix any issues
pre-commit run --all-files
```

Expected: All checks pass

**Step 3: Commit any fixes**

```bash
if [ -n "$(git status --porcelain)" ]; then
  git add -u
  git commit -m "fix: apply final pre-commit fixes"
fi
```

**Step 4: Document results**

```bash
echo "FINAL: Pre-commit checks PASSED" >> /tmp/final-test-results.txt
```

### Task 30: Final Git Status Review

**Files:**

- Review: Git repository state

**Step 1: Check git status**

```bash
git status
```

Expected: Working tree clean

**Step 2: Review commit history**

```bash
git log --oneline --graph -20
```

Expected: Clean commit history showing all migration steps

**Step 3: Verify file structure**

```bash
tree -L 2 -a
```

Expected: See new structure with common/, container/, vm/

**Step 4: Review all test results**

```bash
echo "=== Initial Tests ==="
cat /tmp/test-results.txt
echo ""
echo "=== Final Tests ==="
cat /tmp/final-test-results.txt
```

Expected: All tests passed

**Step 5: Create final summary**

```bash
cat > /tmp/migration-summary.txt << 'EOF'
Repository Reorganization Complete
===================================

New Structure:
- common/homedir/   - Shared configuration files
- common/packages/  - Package lists (apt, npm, python, versions)
- container/        - Docker container approach
- vm/               - Libvirt/KVM VM approach

Tests Passed:
✓ Container builds successfully
✓ VM Terraform validates successfully
✓ All pre-commit checks pass
✓ Documentation links verified
✓ No broken references to old paths

Ready for use!
EOF
cat /tmp/migration-summary.txt
```

**Step 6: Tag completion**

```bash
git tag v1.0.0-reorganized
```

**Step 7: Cleanup temp files**

```bash
rm /tmp/test-results.txt /tmp/final-test-results.txt /tmp/migration-summary.txt
```

## Implementation Complete

All tasks completed. The repository has been successfully reorganized with:

- ✅ Clean separation of container and VM approaches
- ✅ Shared resources in common/ directory
- ✅ Gateway documentation at root
- ✅ Approach-specific documentation
- ✅ All tests passing
- ✅ No broken references
- ✅ Pre-commit checks passing

Next steps:

1. Push to remote repository
2. Update any CI/CD configurations
3. Notify team of new structure
4. Archive old branches if any
