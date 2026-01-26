# Update Claude Code Installation Method

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task.

**Goal:** Replace npm-based Claude Code installation with official curl-based
installer in both container and VM approaches using a shared installation
script.

**Architecture:** Both approaches currently install Claude Code via
`npm install -g @anthropic-ai/claude-code@latest`. The new official method
uses `curl -fsSL https://claude.ai/install.sh | bash`. To avoid duplication
and provide a single source of truth, we'll create a common installation
script at `common/scripts/install-tools.sh` that both environments will
execute.

**Tech Stack:** Docker (container), Terraform/cloud-init (VM), Bash, npm

---

## Task 1: Create Common Installation Script

**Files:**

- Create: `common/scripts/install-tools.sh`
- Modify: `common/packages/npm-packages.txt`

**Step 1: Create scripts directory**

Run: `mkdir -p common/scripts`

Expected: Directory created

**Step 2: Create install-tools.sh script**

Create `common/scripts/install-tools.sh`:

```bash
#!/bin/bash
# Common tool installation script for both container and VM environments
# This script installs tools that are not available via package managers
# or require custom installation procedures.

set -e -o pipefail

echo "Installing Claude Code using official installer..."
curl -fsSL https://claude.ai/install.sh | bash

# Verify installation succeeded
if ! command -v claude &> /dev/null; then
    echo "ERROR: Claude Code installation failed - claude command not found"
    exit 1
fi

echo "Claude Code installed successfully:"
claude --version
```

**Step 3: Make script executable**

Run: `chmod +x common/scripts/install-tools.sh`

Expected: Script is executable

**Step 4: Update npm-packages.txt to remove Claude Code**

Edit `common/packages/npm-packages.txt`:

```text
@github/copilot@latest
@google/gemini-cli@latest
opencode-ai
prettier

```

Remove the line: `@anthropic-ai/claude-code@latest`

**Step 5: Commit changes**

```bash
git add common/scripts/install-tools.sh common/packages/npm-packages.txt
git commit -m "feat: create common tool installation script

Add install-tools.sh for tools requiring custom installation.
Remove Claude Code from npm packages - will use official installer.

This provides a single source of truth for custom tool installations
shared between container and VM environments.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Update Container Dockerfile

**Files:**

- Modify: `container/Dockerfile`
- Copy: `common/scripts/install-tools.sh` (to container)

**Step 1: Read current Dockerfile structure**

Run: Read tool on `container/Dockerfile` focusing on the section after
npm install (around line 68)

Expected: npm install command, then copy of homedir configs

**Step 2: Add COPY and RUN for install-tools.sh**

Add after npm install (after line 68):

```dockerfile
# Copy and run common tool installation script
COPY ../common/scripts/install-tools.sh /tmp/install-tools.sh
RUN chmod +x /tmp/install-tools.sh && \
    /tmp/install-tools.sh && \
    rm /tmp/install-tools.sh
```

**Step 3: Verify Dockerfile syntax**

Check hadolint will be happy (no syntax issues)

Expected: Clean Dockerfile structure

**Step 4: Commit container changes**

```bash
git add container/Dockerfile
git commit -m "feat: use common install script in container

Execute common/scripts/install-tools.sh during container build.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Update VM Cloud-Init Template

**Files:**

- Modify: `vm/cloud-init.yaml.tftpl`
- Modify: `vm/main.tf` (to include install-tools.sh in write_files)

**Step 1: Update main.tf to include install-tools.sh**

Add to locals section in `vm/main.tf` after homedir_files (around line 60):

```hcl
  # Read install-tools.sh script
  install_tools_script = file("${path.module}/../common/scripts/install-tools.sh")
```

**Step 2: Update cloud-init template to write install-tools.sh**

Add to write_files section in `vm/cloud-init.yaml.tftpl` (after line 24):

```yaml
  - path: /tmp/install-tools.sh
    permissions: '0755'
    content: |
      ${indent(6, install_tools_script)}
```

**Step 3: Update cloud-init to execute install-tools.sh**

Add to runcmd section after npm install (after line 160):

```yaml
  # Install custom tools using common script
  - /tmp/install-tools.sh
  - rm /tmp/install-tools.sh
```

**Step 4: Validate and format Terraform**

Run: `terraform fmt && terraform validate` from `vm/` directory

Expected: Files formatted, validation succeeds

**Step 5: Commit VM changes**

```bash
git add vm/main.tf vm/cloud-init.yaml.tftpl
git commit -m "feat: use common install script in VM

Execute common/scripts/install-tools.sh during VM provisioning.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Run Container Integration Tests

**Files:**

- Execute: `test-integration.sh --container`

**Step 1: Build container image**

Run: `docker build -t ghcr.io/johnstrunk/agent-container -f
container/Dockerfile .` from repo root

Expected: Build completes successfully

**Step 2: Run container integration tests**

Run: `./test-integration.sh --container` from repo root

Expected: Tests pass, verifying:

- Container builds successfully
- Claude Code is available
- Claude Code responds to prompts
- Config files deploy correctly

**Step 3: Verify Claude Code installation**

Run container manually to check Claude installation:

```bash
docker run --rm ghcr.io/johnstrunk/agent-container claude --version
```

Expected: Claude Code version displayed (confirms installation)

**Step 4: Verify installation location**

Check where Claude Code is installed:

```bash
docker run --rm ghcr.io/johnstrunk/agent-container which claude
```

Expected: Path shown (likely ~/.local/bin/claude in PATH)

**Step 5: Document test results**

If tests pass, proceed to next task. If tests fail, debug and fix issues
before continuing.

---

## Task 5: Run VM Integration Tests

**Files:**

- Execute: `test-integration.sh --vm`

**Step 1: Clean up any existing test VMs**

Run: `./vm/agent-vm --destroy` from repo root (if VM exists)

Expected: Existing VM destroyed or reports none exists

**Step 2: Run VM integration tests**

Run: `./test-integration.sh --vm` from repo root

Expected: Tests pass, verifying:

- Terraform provisions VM successfully
- cloud-init completes without errors
- Claude Code is installed and functional
- Multi-workspace workflow works
- Filesystem mounts work correctly

**Step 3: Verify Claude Code in VM**

SSH into VM and check:

```bash
ssh -i vm/vm-ssh-key root@<vm-ip> "claude --version"
```

Expected: Claude Code version displayed

**Step 4: Document test results**

If tests pass, proceed to next task. If tests fail, debug and fix issues
before continuing.

---

## Task 6: Run All Integration Tests

**Files:**

- Execute: `test-integration.sh --all`

**Step 1: Run comprehensive test suite**

Run: `./test-integration.sh --all` from repo root

Expected: Both container and VM tests pass completely

**Step 2: Verify no regressions**

Check that all previous functionality still works:

- Container builds and runs
- VM provisions and boots
- Claude Code works in both environments
- Credentials inject correctly
- Config files deploy from common/homedir/

**Step 3: Clean up test artifacts**

Run: `./vm/agent-vm --destroy` to remove test VMs

Expected: Test VMs cleaned up

**Step 4: Document completion**

All integration tests pass - changes are ready for final commit.

---

## Task 7: Run Pre-Commit Checks

**Files:**

- All modified files

**Step 1: Run pre-commit on all changed files**

Run: `pre-commit run --files common/scripts/install-tools.sh
common/packages/npm-packages.txt container/Dockerfile vm/main.tf
vm/cloud-init.yaml.tftpl
docs/plans/2026-01-26-update-claude-code-installation.md`

Expected: All checks pass

**Step 2: Fix any pre-commit issues**

If pre-commit finds issues, fix them:

- Markdown line length
- Trailing whitespace
- Final newline
- YAML formatting
- Shell script issues

**Step 3: Re-run pre-commit until clean**

Run: `pre-commit run --files <files>` again

Expected: All checks pass with no errors

**Step 4: Commit this plan**

```bash
git add docs/plans/2026-01-26-update-claude-code-installation.md
git commit -m "docs: add plan for Claude Code installation update

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Completion Checklist

- [ ] Common installation script created
- [ ] Container Dockerfile updated to use common script
- [ ] VM cloud-init updated to use common script
- [ ] npm-packages.txt updated (Claude Code removed)
- [ ] Container integration tests pass
- [ ] VM integration tests pass
- [ ] Full integration test suite passes
- [ ] Pre-commit checks pass
- [ ] All changes committed

## Notes

- The official installer installs to `~/.local/bin/claude` by default
- The installer handles PATH configuration automatically
- Both approaches now use the same installation script from `common/scripts/`
- Future tool installations can be added to `install-tools.sh`
- Integration tests are CRITICAL to verify Claude Code works after changes
- The install script includes verification with `claude --version`
