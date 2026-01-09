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

### Using agent-vm

The unified `agent-vm` command handles all VM and workspace operations:

```bash
# Create/connect to workspace (creates VM if needed)
./agent-vm -b feature-name

# Create VM with custom resources (creation-time only)
./agent-vm -b feature-name --memory 16384 --vcpu 8

# List all workspaces
./agent-vm --list

# Force push branch from host to VM
./agent-vm -b feature-name --push

# Fetch changes from VM to host
./agent-vm -b feature-name --fetch

# Clean specific workspace
./agent-vm -b feature-name --clean

# Clean all workspaces (VM stays running)
./agent-vm --clean-all

# Destroy entire VM
./agent-vm --destroy
```

### Single-VM Architecture

One persistent VM hosts multiple workspace directories:

- VM name: `agent-vm`
- Workspaces: `~/workspace/<repo>-<branch>/`
- Each workspace is a full git clone
- All workspaces share the same VM

### Filesystem Sharing

Host files are mounted via SSHFS:

- Host mount: `~/.agent-vm-mounts/workspace/`
- VM directory: `~/workspace/`
- See all workspaces in one mount point

Edit files on host with your IDE, run builds/tests in VM.

### Multi-Workspace Support

Multiple branches work in the same VM:

- Workspaces: `~/workspace/<repo>-<branch>/`
- Each workspace is isolated (separate git clone)
- Open multiple terminals to different workspaces
- VM resources shared across all workspaces

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

2. **Test with new VM**:

   ```bash
   ./agent-vm -b test-changes
   # Verify everything works
   ./agent-vm -b test-changes --destroy
   ```

3. **Run integration tests**:

   ```bash
   cd ..
   ./test-integration.sh --vm
   ```

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
4. **Test**: Create new VM with `./agent-vm -b test-pkg` and verify package
   installs
5. Commit changes

### Modifying VM Configuration

1. **Plan**: Create todos for configuration changes
2. Edit `main.tf` or `variables.tf`
3. Run `terraform fmt` and `terraform validate`
4. **Test**: Run `terraform plan` to preview
5. Create new VM with `./agent-vm -b test-config` to test
6. Commit changes

### Updating Cloud-Init

1. **Plan**: Create todos for cloud-init changes
2. Edit `cloud-init.yaml.tftpl`
3. Run `terraform validate`
4. **Test**: Create new VM with `./agent-vm -b test-init` to apply changes
5. Verify with SSH and check installed software
6. Commit changes

## Testing Strategy

1. **Terraform validation**: `terraform fmt && terraform validate`
2. **Plan review**: Always run `terraform plan` before apply
3. **Incremental testing**: Test small changes before large refactors
4. **VM verification**: SSH in and verify expected state
5. **Pre-commit checks**: Run on all modified files

### Integration Tests

Run end-to-end tests to validate VM environment:

```bash
# From repository root
./test-integration.sh --vm
```

This tests:

- Terraform provisions VM successfully
- cloud-init completes without errors
- Multi-VM workflow (parallel VMs, reconnection)
- Filesystem mounts (worktree, mainrepo)
- VM lifecycle (create, list, destroy)

**When to run:**

- Before committing Terraform configuration changes
- Before committing cloud-init template changes
- Before committing changes to `common/homedir/` configs
- After updating package lists in `common/packages/`

## Security Considerations

- SSH keys auto-generated per-VM by Terraform (not in repo, stored in `.ssh/`)
- GCP credentials auto-detected and injected via `agent-vm`:
  - Checks `GOOGLE_APPLICATION_CREDENTIALS` env var first
  - Falls back to `~/.config/gcloud/application_default_credentials.json`
  - Never stored in repo
- Constrained sudo access for AI agents
- Root access via SSH key only (no password)

## Environment Identification

The VM includes an environment marker file at `/etc/agent-environment`
containing `agent-vm`. This identifies the execution context and allows
integration tests to run from the VM environment.

## Maintenance Notes

- Pre-commit hooks ensure code quality
- Terraform state managed locally (consider remote backend for teams)
- VM lifecycle managed by Terraform (create/destroy)
- Cloud-init runs once at VM creation

## Recent Bug Fixes (2026-01-07)

Six critical bugs were fixed to improve safety and robustness:

1. **Data Loss Prevention**: `--fetch` now checks for uncommitted
   changes BEFORE unmounting SSHFS, preventing editor buffer loss
2. **Race Condition Fix**: IP allocation uses file locking to prevent
   concurrent processes from allocating the same IP
3. **Resource Leak Prevention**: Workspace deletion only occurs after
   successful `terraform destroy`
4. **Orphan Recovery**: Workspace orphan recovery verifies destroy
   success before recreation
5. **Cleanup Accuracy**: `--cleanup` now correctly counts cleaned VMs
   (fixed subshell issue)
6. **Mount Cleanup**: Mount directories are cleaned up when VMs are destroyed

See `docs/plans/2026-01-07-agent-vm-critical-bug-fixes.md` for full details.

## Architecture Evolution

**2026-01-08:** Redesigned to use single-VM with multiple workspaces

The multi-VM architecture (one VM per branch via Terraform workspaces) was
replaced with a simpler single-VM design. Multiple branches now work as
workspace directories within one VM, reducing resource consumption and
simplifying management.

Previous multi-VM bug fixes (2026-01-07) are preserved in git history but
no longer relevant to current architecture.
