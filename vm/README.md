# VM Approach - Debian AI Development VM

Terraform configuration for deploying a Debian 13 virtual machine with AI
coding agents using libvirt/KVM.

**[← Back to main documentation](../README.md)**

## Features

- **Infrastructure as Code**: Declarative VM configuration with Terraform
- **Console Auto-Login**: Serial console automatically logs in as root
- **SSH Key Management**: Centralized SSH key directory for access control
- **Cloud-Init Provisioning**: Automated system configuration
- **Dual User Access**: SSH access for both default user and root
- **Constrained Sudo Access**: Default user can install packages and
  manage services
- **AI Coding Agents**: Pre-installed claude-code, gemini-cli, and
  copilot
- **Vertex AI Integration**: Optional Google Cloud Vertex AI
  authentication

## Package Management

This VM uses shared package lists from `../common/packages/`:

- `apt-packages.txt` - Debian packages installed via cloud-init
- `npm-packages.txt` - Global npm packages (AI agents)
- `python-packages.txt` - Python tools (pre-commit, poetry, etc.)
- `versions.txt` - Version pins for Go, hadolint, etc.

Packages are automatically installed during VM provisioning via cloud-init.

## Prerequisites

- libvirt/KVM installed and running
- Terraform >= 1.0
- Access to qemu:///system libvirt URI
- Network connectivity to download Debian cloud images
- **Multi-interface hosts**: Run `./libvirt-nat-fix.sh` after each host
  reboot (see Troubleshooting)

### Install Prerequisites (Debian/Ubuntu)

```bash
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils
sudo systemctl enable --now libvirtd
sudo usermod -aG libvirt $USER
```

### Install Terraform

Follow instructions at: <https://www.terraform.io/downloads>

## Getting Started

### Quick Start

```bash
# Create VM and connect
cd vm/
./agent-vm -b feature-auth

# Inside VM
claude  # Start Claude Code
```

The VM persists after exit. Reconnect anytime with the same command.

## Usage

### Basic Workflow

```bash
# Create/connect to VM for a branch
./agent-vm -b feature-name

# Run command in VM
./agent-vm -b feature-name -- claude

# Create VM with custom resources
./agent-vm -b big-build --memory 16384 --vcpu 8
```

### Managing VMs

```bash
# List all VMs
./agent-vm --list

# Stop VM (keeps workspace)
./agent-vm -b feature-name --stop

# Destroy VM completely
./agent-vm -b feature-name --destroy

# Clean up all stopped VMs
./agent-vm --cleanup
```

### Multi-VM Workflow

```bash
# Terminal 1
./agent-vm -b feature-auth

# Terminal 2 (parallel work)
./agent-vm -b feature-payments

# Terminal 3 (reconnect to first VM)
./agent-vm -b feature-auth
```

Each branch gets its own VM, worktree, and IP address.

### Filesystem Sharing

Files are shared between host and VM via virtio-9p:

- `/worktree` - Your branch's worktree (edit on host, build in VM)
- `/mainrepo` - Main git repository (for commits)

Changes on host appear immediately in VM and vice versa.

## Using AI Coding Agents

The VM comes pre-installed with AI coding agents:

- **claude-code**: Anthropic's Claude Code agent
- **gemini-cli**: Google's Gemini CLI
- **copilot**: GitHub Copilot CLI

### Using Claude Code with Vertex AI

**GCP credentials are auto-detected** from your default location:

```bash
# Ensure you have GCP credentials set up
gcloud auth application-default login

# Set environment variables for Vertex AI
export ANTHROPIC_VERTEX_PROJECT_ID="your-gcp-project-id"
export CLOUD_ML_REGION="us-central1"  # Optional, defaults to us-central1

# Create VM (credentials will be auto-detected)
./agent-vm -b feature-name
```

The `agent-vm` script will:

- Automatically detect GCP credentials from
  `~/.config/gcloud/application_default_credentials.json`
- Pass credentials and environment variables to the VM
- Configure Claude Code for Vertex AI authentication

#### Alternative: Custom credentials path

```bash
export GOOGLE_APPLICATION_CREDENTIALS="~/my-service-account.json"
export ANTHROPIC_VERTEX_PROJECT_ID="your-gcp-project-id"
./agent-vm -b feature-name
```

### Running Claude Code

Connect to the VM and run:

```bash
./agent-vm -b feature-name
start-claude  # Recommended - includes MCP servers and plugins
```

The `start-claude` helper script automatically sets up MCP servers (context7,
docling, playwright) and plugins (superpowers) on first run.

Environment variables are automatically configured:

- `GOOGLE_APPLICATION_CREDENTIALS`
- `ANTHROPIC_VERTEX_PROJECT_ID`
- `CLOUD_ML_REGION`
- `CLAUDE_CODE_USE_VERTEX`

### Installed Tools

All agents have access to:

- **Languages**: Python 3, Go 1.25.0, Node.js
- **Package Managers**: npm, pip, uv, poetry, pipenv
- **Development Tools**: git, docker, jq, ripgrep
- **Python Tools**: pre-commit, dvc

## Configuration

### VM Resource Options

Customize VM resources at creation time:

```bash
# Default: 4 vCPU, 4096 MB RAM
./agent-vm -b feature-name

# High-resource build
./agent-vm -b big-build --vcpu 8 --memory 16384

# Custom configuration
./agent-vm -b custom --vcpu 6 --memory 8192
```

**Note:** Resource settings only apply at VM creation time and cannot be
changed after.

## Nested Virtualization

The VM supports nested virtualization, allowing you to run a VM inside a VM.
This is useful for testing VM provisioning or isolating AI agent work.

### Prerequisites for Nested Virtualization

1. **Host CPU must support nested virtualization**:

   ```bash
   # Check if nested virtualization is enabled
   cat /sys/module/kvm_intel/parameters/nested  # Intel
   cat /sys/module/kvm_amd/parameters/nested    # AMD
   # Should output: Y or 1
   ```

2. **Enable nested KVM** (if not already enabled):

   ```bash
   # Intel
   echo "options kvm_intel nested=1" | sudo tee /etc/modprobe.d/kvm.conf
   # AMD
   echo "options kvm_amd nested=1" | sudo tee /etc/modprobe.d/kvm.conf

   # Reload module
   sudo modprobe -r kvm_intel && sudo modprobe kvm_intel  # Intel
   sudo modprobe -r kvm_amd && sudo modprobe kvm_amd      # AMD
   ```

### Running Nested VMs

**Network subnets are automatically configured!** The `agent-vm`
script detects if you're running inside a VM and automatically selects
a different network subnet to avoid conflicts.

```bash
# Inside the outer VM, create a nested VM normally
./agent-vm -b nested-feature
# Script will detect you're on 192.168.123.x and use 192.168.200.0/24
```

**Example Nested Setup:**

```bash
# 1. On host: Create outer VM
cd vm
./agent-vm -b outer-feature

# 2. Inside outer VM: Create inner VM (automatically uses different subnet)
cd /worktree
./vm/agent-vm -b inner-feature
# Autodetects outer VM on 192.168.123.x, uses 192.168.200.0/24
```

### Features Available for Nested VMs

The VM is configured with:

- **CPU passthrough** (`host-passthrough`) for nested virtualization
- **Virtualization packages**: qemu-system-x86, libvirt, virtinst
- **Pre-initialized libvirt**: Default storage pool and network setup
- **Increased resources**: 4 vCPUs, 4GB RAM, 40GB disk (vs 2/2GB/20GB
  previously)

## SSH Key Management

**SSH keys are automatically generated** per-VM when you first create each VM.
The keys are stored in the `vm/.ssh/` directory, organized by branch:

- `.ssh/<branch>-key` - Private key
- `.ssh/<branch>-key.pub` - Public key

The `agent-vm` script automatically manages these keys. You don't need to handle
SSH keys manually.

**Security Notes:**

- Private keys have restrictive permissions (0600)
- Each VM has its own unique SSH key
- Keys are regenerated if you destroy and recreate a VM
- Keys are not committed to git (listed in `.gitignore`)

## Maintenance

### View VM Status

```bash
# List all VMs
./agent-vm --list

# View detailed VM info with virsh
virsh list --all
```

### Destroy VM

```bash
# Destroy specific VM
./agent-vm -b feature-name --destroy

# Clean up all stopped VMs
./agent-vm --cleanup
```

## Troubleshooting

### VM Not Getting IP Address

```bash
# List VMs and their status
./agent-vm --list

# Check DHCP leases
virsh net-dhcp-leases default
```

### Cannot Connect to VM

1. Verify VM is running: `./agent-vm --list`
2. Check if VM is in the running state
3. Try reconnecting: `./agent-vm -b branch-name`
4. Check cloud-init logs: Connect via console and run `journalctl -u cloud-init`

### VM Cannot Reach Internet (Multi-Interface Hosts)

**Problem**: VMs can ping gateway (192.168.122.1) but cannot reach
internet. Common on hosts with multiple network interfaces (eth0,
eth1, wlan0, etc).

**Root Cause**: libvirt creates iptables FORWARD rules for only one
interface (typically eth0), but traffic may route through a different
interface (e.g., eth1 with lower metric).

**Solution**: Run the NAT fix script after each host reboot:

```bash
./libvirt-nat-fix.sh
```

This script adds FORWARD rules for all active external interfaces,
allowing VM traffic to reach the internet regardless of which
interface is used for the default route.

**Verify Fix**:

```bash
# From host
./libvirt-nat-fix.sh

# From VM (after terraform apply)
ssh root@<VM_IP> ping -c 3 8.8.8.8
```

**Permanent Solution**: Add the script to your system startup (e.g.,
as a systemd service) or run it manually after each reboot and before
`terraform apply`.

## Architecture

- **Hypervisor**: libvirt/KVM (qemu:///system)
- **Base Image**: Debian 13 (Trixie) cloud image
- **Provisioning**: cloud-init
- **Networking**: Default libvirt network (NAT)
- **Storage**: qcow2 disk image in default pool
- **Console**: Serial console with auto-login

## Security Notes

This configuration is designed for **development/testing environments**:

- Console auto-login as root (assumes trusted environment)
- Root SSH access enabled (key-based only)
- No password authentication
- Assumes local libvirt instance (not exposed to network)

For production use, consider:

- Disabling root SSH access
- Removing console auto-login
- Implementing firewall rules
- Using restricted user accounts
- Regular security updates

## File Structure

```text
vm/
├── README.md              # This file
├── main.tf                # Terraform resources
├── variables.tf           # Input variables
├── outputs.tf             # Output values
├── cloud-init.yaml.tftpl  # Cloud-init template
├── agent-vm               # Unified VM management script
├── vm-common.sh           # Helper functions
├── libvirt-nat-fix.sh     # Network fix script
└── .ssh/                  # Per-VM SSH keys (not in git)

../common/
├── homedir/               # Shared configs (deployed to VM)
└── packages/              # Package lists (used in cloud-init)
```

## References

- [Terraform libvirt Provider](https://github.com/dmacvicar/terraform-provider-libvirt)
- [Debian Cloud Images](https://cloud.debian.org/images/cloud/)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [libvirt Documentation](https://libvirt.org/docs.html)
