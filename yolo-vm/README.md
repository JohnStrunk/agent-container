# Debian 13 (Trixie) VM with Libvirt

This directory contains Terraform configuration to deploy a Debian 13
(Trixie) virtual machine using libvirt/KVM with automated provisioning.

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

## Quick Start

### 1. Add Your SSH Key

```bash
cp ~/.ssh/id_ed25519.pub ssh-keys/mykey.pub
```

### 2. Initialize Terraform

```bash
cd yolo-vm
terraform init
```

### 3. Review the Plan

```bash
terraform plan
```

### 4. Deploy the VM

```bash
terraform apply
```

### 5. Access the VM

**Via Console (auto-login as root):**

```bash
virsh console debian-trixie-vm
# Press Enter to see root prompt
# Ctrl+] to exit console
```

**Via SSH (as default user):**

```bash
ssh debian@<VM_IP>
```

**Via SSH (as root):**

```bash
ssh root@<VM_IP>
```

Get VM IP from Terraform outputs:

```bash
terraform output vm_ip
```

## Using AI Coding Agents

The VM comes pre-installed with AI coding agents:

- **claude-code**: Anthropic's Claude Code agent
- **gemini-cli**: Google's Gemini CLI
- **copilot**: GitHub Copilot CLI

### Prerequisites for Claude Code with Vertex AI

1. Create a GCP service account with Vertex AI permissions:

   ```bash
   gcloud iam service-accounts create claude-code-agent \
     --display-name="Claude Code Agent"

   PROJECT="YOUR_PROJECT_ID"
   # Service account email format: <name>@<project>.iam.gserviceaccount.com
   SA="claude-code-agent@${PROJECT}.iam.gserviceaccount.com"

   gcloud projects add-iam-policy-binding ${PROJECT} \
     --member="serviceAccount:${SA}" \
     --role="roles/aiplatform.user"

   gcloud iam service-accounts keys create \
     ~/claude-code-sa-key.json \
     --iam-account=${SA}
   ```

2. Update `terraform.tfvars`:

   ```hcl
   gcp_service_account_key_path = "~/claude-code-sa-key.json"
   vertex_project_id = "your-gcp-project-id"
   vertex_region = "us-central1"
   ```

3. Deploy the VM:

   ```bash
   terraform apply
   ```

### Running Claude Code

SSH into the VM and run:

```bash
ssh debian@<VM_IP>
claude-code --help
```

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

## Helper Scripts

### Connecting to the VM

**Connect via SSH:**

```bash
./vm-connect.sh
```

This script automatically:

- Ensures the VM is running (calls `vm-up.sh`)
- Retrieves the VM IP from Terraform
- Connects via SSH to the VM

**Options:**

- `-r, --root`: Connect as root instead of the default user

**Examples:**

```bash
# Connect as default user
./vm-connect.sh

# Connect as root
./vm-connect.sh -r
./vm-connect.sh --root
```

## Syncing Files with VM Workspace

Four helper scripts enable syncing files and git repositories between the
host and VM workspace:

### Directory Sync

**Push directory to VM:**

```bash
./vm-dir-push <local-directory> [workspace-subpath]

# Examples:
./vm-dir-push ./my-project              # → /home/debian/workspace/
./vm-dir-push ./my-project myapp        # → /home/debian/workspace/myapp/
```

**Pull directory from VM:**

```bash
./vm-dir-pull <local-directory> [workspace-subpath]

# Examples:
./vm-dir-pull ./my-project              # ← /home/debian/workspace/
./vm-dir-pull ./my-project myapp        # ← /home/debian/workspace/myapp/
```

### Git Repository Sync

**Push git branch to VM:**

```bash
./vm-git-push <branch-name> [workspace-subpath]

# Examples:
./vm-git-push feature-auth              # → /home/debian/workspace/
./vm-git-push feature-auth myapp        # → /home/debian/workspace/myapp/
```

**Fetch git branch from VM:**

```bash
./vm-git-fetch <branch-name> [workspace-subpath]

# Examples:
./vm-git-fetch feature-auth             # ← /home/debian/workspace/
./vm-git-fetch feature-auth myapp       # ← /home/debian/workspace/myapp/

# Then review and merge
git checkout feature-auth
git log
git checkout main
git merge feature-auth
```

### Typical Workflow

**For git repositories:**

```bash
# 1. Push your branch to VM
./vm-git-push feature-branch

# 2. SSH into VM and work with AI agent
./vm-connect.sh
claude-code  # Work on the feature

# 3. Back on host, fetch the changes
./vm-git-fetch feature-branch

# 4. Review and merge
git checkout feature-branch
git log
git checkout main
git merge feature-branch
```

**For simple directories:**

```bash
# 1. Push directory to VM
./vm-dir-push ./my-project

# 2. SSH into VM and work
./vm-connect.sh
cd ~/workspace/my-project
# Make changes...

# 3. Pull changes back
./vm-dir-pull ./my-project
```

## Configuration

### Customize VM Settings

Edit `terraform.tfvars` (create if not exists):

```hcl
vm_name     = "my-custom-vm"
vm_memory   = 4096
vm_vcpu     = 4
vm_hostname = "my-hostname"
```

### Available Variables

See `variables.tf` for all configurable options:

- `vm_name`: Virtual machine name
- `vm_memory`: RAM in MB (default: 4096)
- `vm_vcpu`: Number of CPUs (default: 4)
- `vm_disk_size`: Disk size in bytes (default: 40GB)
- `vm_hostname`: VM hostname
- `default_user`: Default username (default: user)
- `ssh_keys_dir`: SSH keys directory (default: ./ssh-keys)
- `debian_image_url`: Debian cloud image URL
- `gcp_service_account_key_path`: Path to GCP service account JSON
  key
- `vertex_project_id`: Google Cloud project ID for Vertex AI
- `vertex_region`: Google Cloud region for Vertex AI (default:
  us-central1)
- `network_subnet_third_octet`: Third octet of VM network subnet
  (192.168.X.0/24) (default: 123)

## Nested Virtualization

The VM supports nested virtualization, allowing you to run yolo-vm
inside a yolo-vm. This is useful for testing VM provisioning or
isolating AI agent work.

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

**Network subnets are automatically configured!** The `vm-up.sh`
script detects if you're running inside a VM and automatically selects
a different network subnet to avoid conflicts.

```bash
# Inside the outer VM, just run vm-up.sh normally
./vm-up.sh
# Script will detect you're on 192.168.123.x and use 192.168.200.0/24
```

**How Autodetection Works:**

- Detects if running on `192.168.x.x` network
- If on `192.168.122.x` or `192.168.123.x` → uses `192.168.200.0/24`
- Otherwise → uses `192.168.(current+1).0/24`
- Not on `192.168.x.x` → uses default `192.168.123.0/24`

**Manual Override (Optional):**

You can still manually specify a subnet if needed:

```bash
export NETWORK_SUBNET=150
./vm-up.sh

# Or use Terraform directly
terraform apply -var="network_subnet_third_octet=150"
```

**Example Nested Setup:**

```bash
# 1. On host: Create outer VM (uses 192.168.123.0/24 by default)
cd yolo-vm
./vm-up.sh
ssh user@<OUTER_VM_IP>

# 2. Inside outer VM: Create inner VM (automatically uses different
# subnet)
cd ~/workspace
git clone <your-repo-with-yolo-vm>
cd yolo-vm
./vm-up.sh  # Autodetects outer VM on 192.168.123.x, uses
192.168.200.0/24
ssh user@<INNER_VM_IP>
```

### Features Available for Nested VMs

The VM is configured with:

- **CPU passthrough** (`host-passthrough`) for nested virtualization
- **Virtualization packages**: qemu-system-x86, libvirt, virtinst
- **Pre-initialized libvirt**: Default storage pool and network setup
- **Increased resources**: 4 vCPUs, 4GB RAM, 40GB disk (vs 2/2GB/20GB
  previously)

## Managing SSH Keys

### Add a New Key

```bash
cp /path/to/newkey.pub ssh-keys/newkey.pub
terraform apply
```

### Remove a Key

```bash
rm ssh-keys/oldkey.pub
terraform apply
```

### Key Format

- Must have `.pub` extension
- Standard SSH public key format
- One key per file

## Maintenance

### Update VM Configuration

```bash
# Modify variables or configuration
terraform plan
terraform apply
```

### Destroy VM

```bash
terraform destroy
```

### View VM Status

```bash
virsh list --all
virsh dominfo debian-trixie-vm
```

## Troubleshooting

### VM Not Getting IP Address

```bash
# Check DHCP leases
virsh net-dhcp-leases default

# Check VM network interface
virsh domiflist debian-trixie-vm
```

### Console Not Auto-Logging In

1. Connect to console: `virsh console debian-trixie-vm`
2. If you see login prompt, cloud-init may not have completed
3. Wait 1-2 minutes for cloud-init to finish
4. Check cloud-init status: `cloud-init status`

### SSH Connection Refused

1. Verify VM is running: `virsh list`
2. Check VM has IP: `terraform output vm_ip`
3. Verify SSH keys: `ls ssh-keys/*.pub`
4. Check cloud-init logs: `virsh console debian-trixie-vm` then
   `journalctl -u cloud-init`

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
yolo-vm/
├── README.md              # This file
├── design-vm.md           # Design document
├── main.tf                # Terraform resources
├── variables.tf           # Input variables
├── outputs.tf             # Output values
├── cloud-init.yaml.tftpl  # Cloud-init template
├── .gitignore             # Git ignore rules
└── ssh-keys/              # SSH public keys
    ├── README.md          # SSH keys documentation
    └── *.pub              # Your public keys
```

## References

- [Terraform libvirt Provider](https://github.com/dmacvicar/terraform-provider-libvirt)
- [Debian Cloud Images](https://cloud.debian.org/images/cloud/)
- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [libvirt Documentation](https://libvirt.org/docs.html)
