# Libvirt VM Deployment Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to
> implement this plan task-by-task.

**Goal:** Deploy a Debian 13 (Trixie) VM using Terraform and libvirt with
auto-login console and SSH key management

**Architecture:** Use Terraform's libvirt provider to declaratively define
VM configuration, cloud-init for provisioning (console auto-login, SSH
keys), and local directory for SSH key management

**Tech Stack:** Terraform, libvirt provider, cloud-init, QEMU/KVM, Debian
13 (Trixie)

---

## Task 1: Create SSH Keys Directory Structure

**Files:**

- Create: `yolo-vm/ssh-keys/.gitkeep`
- Create: `yolo-vm/ssh-keys/README.md`

### Step 1: Create ssh-keys directory with .gitkeep

```bash
mkdir -p yolo-vm/ssh-keys
touch yolo-vm/ssh-keys/.gitkeep
```

### Step 2: Write README.md for ssh-keys directory

File: `yolo-vm/ssh-keys/README.md`

```markdown
# SSH Public Keys

Place SSH public key files (`.pub`) in this directory. These keys will be
provisioned to the VM for both the default user and root.

## Usage

1. Copy your SSH public key file to this directory:
   `cp ~/.ssh/id_ed25519.pub ssh-keys/mykey.pub`

2. Run Terraform to provision the VM with updated keys:
   `terraform apply`

## Format

- Files must have `.pub` extension
- Standard SSH public key format (ssh-rsa, ssh-ed25519, etc.)
- One key per file
- Filenames are for organization only (not used in VM)

## Example

```text
ssh-keys/
├── alice.pub
├── bob.pub
└── ci-system.pub
```

```text
(end of embedded markdown example)
```

### Step 3: Verify directory structure

Run: `ls -la yolo-vm/ssh-keys/`

Expected output:

```text
drwxr-xr-x  .
drwxr-xr-x  ..
-rw-r--r--  .gitkeep
-rw-r--r--  README.md
```

### Step 4: Commit

```bash
git add yolo-vm/ssh-keys/
git commit -m "feat: add ssh-keys directory for VM access management"
```

---

## Task 2: Create Terraform Variables Configuration

**Files:**

- Create: `yolo-vm/variables.tf`

### Step 1: Write variables.tf with VM configuration options

File: `yolo-vm/variables.tf`

```hcl
variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "debian-trixie-vm"
}

variable "vm_memory" {
  description = "Memory allocation for VM in MB"
  type        = number
  default     = 2048
}

variable "vm_vcpu" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 2
}

variable "vm_disk_size" {
  description = "Disk size in bytes (20GB default)"
  type        = number
  default     = 21474836480
}

variable "vm_hostname" {
  description = "Hostname for the VM"
  type        = string
  default     = "debian-trixie"
}

variable "default_user" {
  description = "Default non-root user to create"
  type        = string
  default     = "debian"
}

variable "ssh_keys_dir" {
  description = "Directory containing SSH public keys"
  type        = string
  default     = "./ssh-keys"
}

variable "debian_image_url" {
  description = "URL to Debian cloud image"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}
```

### Step 2: Validate Terraform syntax

Run: `cd yolo-vm && terraform fmt -check variables.tf`

Expected: File already formatted (no changes needed) or formatting applied

### Step 3: Commit variables

```bash
git add yolo-vm/variables.tf
git commit -m "feat: add Terraform variables for VM configuration"
```

---

## Task 3: Create Cloud-Init Template for Auto-Login and SSH

**Files:**

- Create: `yolo-vm/cloud-init.yaml.tftpl`

### Step 1: Write cloud-init template

File: `yolo-vm/cloud-init.yaml.tftpl`

```yaml
#cloud-config
hostname: ${hostname}
fqdn: ${hostname}.local
manage_etc_hosts: true

users:
  - name: ${default_user}
    groups: sudo
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - ${key}
%{ endfor ~}
  - name: root
    ssh_authorized_keys:
%{ for key in ssh_keys ~}
      - ${key}
%{ endfor ~}

# Enable root login via SSH
ssh_pwauth: false
disable_root: false

# Configure serial console auto-login as root
runcmd:
  - mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
  - |
    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf <<EOF
    [Service]
    ExecStart=
    ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
    EOF
  - systemctl daemon-reload
  - systemctl restart serial-getty@ttyS0.service
  - |
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
  - systemctl restart sshd

package_update: true
package_upgrade: true

packages:
  - vim
  - curl
  - wget
  - git
  - htop

final_message: "System boot complete. Console auto-login enabled for root."
```

### Step 2: Verify YAML syntax

Run: `cd yolo-vm && yamllint cloud-init.yaml.tftpl || echo "Template file, skip lint"`

Expected: Skip lint (template has Terraform interpolation) or passes

### Step 3: Commit cloud-init template

```bash
git add yolo-vm/cloud-init.yaml.tftpl
git commit -m "feat: add cloud-init template for auto-login and SSH keys"
```

---

## Task 4: Create Main Terraform Configuration

**Files:**

- Create: `yolo-vm/main.tf`

### Step 1: Write main.tf with provider and resources

File: `yolo-vm/main.tf`

```hcl
terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Read all SSH public keys from directory
locals {
  ssh_key_files = fileset(var.ssh_keys_dir, "*.pub")
  ssh_keys = [
    for f in local.ssh_key_files :
    trimspace(file("${var.ssh_keys_dir}/${f}"))
  ]
}

# Download Debian cloud image
resource "libvirt_volume" "debian_base" {
  name   = "debian-13-base.qcow2"
  pool   = "default"
  source = var.debian_image_url
  format = "qcow2"
}

# Create VM disk from base image
resource "libvirt_volume" "debian_disk" {
  name           = "${var.vm_name}-disk.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.debian_base.id
  size           = var.vm_disk_size
  format         = "qcow2"
}

# Cloud-init configuration
data "template_file" "cloud_init" {
  template = file("${path.module}/cloud-init.yaml.tftpl")
  vars = {
    hostname     = var.vm_hostname
    default_user = var.default_user
    ssh_keys     = jsonencode(local.ssh_keys)
  }
}

resource "libvirt_cloudinit_disk" "cloud_init" {
  name      = "${var.vm_name}-cloud-init.iso"
  pool      = "default"
  user_data = data.template_file.cloud_init.rendered
}

# Define the VM
resource "libvirt_domain" "debian_vm" {
  name   = var.vm_name
  memory = var.vm_memory
  vcpu   = var.vm_vcpu

  cloudinit = libvirt_cloudinit_disk.cloud_init.id

  disk {
    volume_id = libvirt_volume.debian_disk.id
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_port = "1"
    target_type = "virtio"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
```

### Step 2: Format Terraform configuration

Run: `cd yolo-vm && terraform fmt main.tf`

Expected: File formatted successfully

### Step 3: Commit main configuration

```bash
git add yolo-vm/main.tf
git commit -m "feat: add main Terraform configuration for VM"
```

---

## Task 5: Create Terraform Outputs

**Files:**

- Create: `yolo-vm/outputs.tf`

### Step 1: Write outputs.tf

File: `yolo-vm/outputs.tf`

```hcl
output "vm_name" {
  description = "Name of the created VM"
  value       = libvirt_domain.debian_vm.name
}

output "vm_ip" {
  description = "IP address of the VM"
  value = try(
    libvirt_domain.debian_vm.network_interface[0].addresses[0],
    "IP not yet assigned"
  )
}

output "ssh_command_default_user" {
  description = "SSH command to connect as default user"
  value = try(
    "ssh ${var.default_user}@${libvirt_domain.debian_vm.network_interface[0].addresses[0]}",
    "Waiting for IP address..."
  )
}

output "ssh_command_root" {
  description = "SSH command to connect as root"
  value = try(
    "ssh root@${libvirt_domain.debian_vm.network_interface[0].addresses[0]}",
    "Waiting for IP address..."
  )
}

output "console_command" {
  description = "Command to access VM console (auto-login as root)"
  value       = "virsh console ${libvirt_domain.debian_vm.name}"
}
```

### Step 2: Format outputs

Run: `cd yolo-vm && terraform fmt outputs.tf`

Expected: File formatted successfully

### Step 3: Commit outputs

```bash
git add yolo-vm/outputs.tf
git commit -m "feat: add Terraform outputs for VM access"
```

---

## Task 6: Create .gitignore for Terraform

**Files:**

- Create: `yolo-vm/.gitignore`

### Step 1: Write .gitignore

File: `yolo-vm/.gitignore`

```text
# Terraform state files
*.tfstate
*.tfstate.*

# Terraform directory
.terraform/
.terraform.lock.hcl

# Override files
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Variable files (may contain sensitive data)
terraform.tfvars
*.auto.tfvars

# Crash log files
crash.log

# Exclude SSH private keys (only .pub files should be here)
ssh-keys/*
!ssh-keys/*.pub
!ssh-keys/.gitkeep
!ssh-keys/README.md
```

### Step 2: Verify .gitignore works

Run: `cd yolo-vm && git status`

Expected: Should not show .terraform/ or *.tfstate files if they exist

### Step 3: Commit gitignore

```bash
git add yolo-vm/.gitignore
git commit -m "feat: add .gitignore for Terraform artifacts"
```

---

## Task 7: Create README for yolo-vm

**Files:**

- Create: `yolo-vm/README.md`

### Step 1: Write comprehensive README

File: `yolo-vm/README.md`

```markdown
# Debian 13 (Trixie) VM with Libvirt

This directory contains Terraform configuration to deploy a Debian 13
(Trixie) virtual machine using libvirt/KVM with automated provisioning.

## Features

- **Infrastructure as Code**: Declarative VM configuration with Terraform
- **Console Auto-Login**: Serial console automatically logs in as root
- **SSH Key Management**: Centralized SSH key directory for access control
- **Cloud-Init Provisioning**: Automated system configuration
- **Dual User Access**: SSH access for both default user and root

## Prerequisites

- libvirt/KVM installed and running
- Terraform >= 1.0
- Access to qemu:///system libvirt URI
- Network connectivity to download Debian cloud images

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
- `vm_memory`: RAM in MB (default: 2048)
- `vm_vcpu`: Number of CPUs (default: 2)
- `vm_disk_size`: Disk size in bytes (default: 20GB)
- `vm_hostname`: VM hostname
- `default_user`: Default username (default: debian)
- `ssh_keys_dir`: SSH keys directory (default: ./ssh-keys)
- `debian_image_url`: Debian cloud image URL

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

```text
(end of embedded markdown example)
```

### Step 2: Run pre-commit on README

Run: `pre-commit run --files yolo-vm/README.md`

Expected: All checks pass

### Step 3: Commit README

```bash
git add yolo-vm/README.md
git commit -m "docs: add comprehensive README for VM deployment"
```

---

## Task 8: Update Pre-commit Configuration for Terraform

**Files:**

- Modify: `.pre-commit-config.yaml`

### Step 1: Check if terraform hooks exist

Run: `grep -i terraform .pre-commit-config.yaml || echo "Not found"`

Expected: Either shows existing terraform config or "Not found"

### Step 2: Add terraform hooks if not present

If terraform hooks don't exist, add this to `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.96.2
    hooks:
      - id: terraform_fmt
      - id: terraform_validate
```

### Step 3: Update pre-commit hooks

Run: `pre-commit install`

Expected: Hooks installed successfully

### Step 4: Test terraform hooks

Run:

```bash
pre-commit run terraform_fmt --all-files || \
  echo "No terraform files or hook not installed"
```

Expected: Pass or "No terraform files" message

### Step 5: Commit if modified

```bash
git add .pre-commit-config.yaml
git commit -m "feat: add Terraform pre-commit hooks"
```

---

## Task 9: Create Example terraform.tfvars

**Files:**

- Create: `yolo-vm/terraform.tfvars.example`

### Step 1: Write example configuration

File: `yolo-vm/terraform.tfvars.example`

```hcl
# Example Terraform variables configuration
# Copy to terraform.tfvars and customize

vm_name     = "debian-trixie-vm"
vm_memory   = 2048
vm_vcpu     = 2
vm_hostname = "debian-trixie"
vm_disk_size = 21474836480  # 20GB

default_user = "debian"
ssh_keys_dir = "./ssh-keys"

# Override Debian image URL if needed
# debian_image_url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
```

### Step 2: Verify file is not ignored

Run: `git check-ignore yolo-vm/terraform.tfvars.example || echo "Not ignored - correct"`

Expected: "Not ignored - correct"

### Step 3: Commit example file

```bash
git add yolo-vm/terraform.tfvars.example
git commit -m "docs: add example terraform.tfvars configuration"
```

---

## Task 10: Create Testing Documentation

**Files:**

- Create: `yolo-vm/TESTING.md`

### Step 1: Write testing guide

File: `yolo-vm/TESTING.md`

```markdown
# Testing Guide for Debian VM Deployment

This document describes how to test the VM deployment configuration.

## Pre-Deployment Testing

### 1. Validate Terraform Configuration

```bash
cd yolo-vm
terraform init
terraform validate
```

Expected output: `Success! The configuration is valid.`

### 2. Check Terraform Formatting

```bash
terraform fmt -check
```

Expected: No output (all files properly formatted)

### 3. Verify SSH Keys Present

```bash
ls -l ssh-keys/*.pub
```

Expected: At least one `.pub` file exists

### 4. Review Terraform Plan

```bash
terraform plan
```

Expected: Shows resources to be created (no errors)

## Deployment Testing

### 1. Deploy VM

```bash
terraform apply
```

Expected: Successful creation of all resources

### 2. Verify VM is Running

```bash
virsh list
```

Expected: VM shows as "running"

### 3. Test Console Auto-Login

```bash
virsh console debian-trixie-vm
# Press Enter
```

Expected: Root prompt without login prompt

### 4. Verify Cloud-Init Completed

In console:

```bash
cloud-init status
```

Expected: `status: done`

### 5. Check Network Configuration

In console:

```bash
ip addr show
```

Expected: Shows IP address on network interface

## SSH Testing

### 1. Get VM IP Address

```bash
terraform output vm_ip
```

### 2. Test SSH as Default User

```bash
ssh debian@<VM_IP>
```

Expected: Successful login without password

### 3. Test SSH as Root

```bash
ssh root@<VM_IP>
```

Expected: Successful login without password

### 4. Verify SSH Keys Installed

On VM (via SSH):

```bash
cat ~/.ssh/authorized_keys
```

Expected: Shows keys from ssh-keys/ directory

## Functional Testing

### 1. Test Sudo Access (Default User)

```bash
ssh debian@<VM_IP> sudo whoami
```

Expected: `root`

### 2. Test Package Installation

```bash
ssh root@<VM_IP> apt-get update
ssh root@<VM_IP> apt-get install -y tree
ssh root@<VM_IP> which tree
```

Expected: Shows path to tree binary

### 3. Test Serial Console Login

```bash
virsh console debian-trixie-vm
# Should auto-login as root
whoami
```

Expected: `root`

## Update Testing

### 1. Add New SSH Key

```bash
ssh-keygen -t ed25519 -f test_key -N ""
cp test_key.pub ssh-keys/test_key.pub
terraform apply
```

Expected: VM updated with new key

### 2. Verify New Key Works

```bash
ssh -i test_key root@<VM_IP>
```

Expected: Successful login

### 3. Remove Test Key

```bash
rm ssh-keys/test_key.pub
terraform apply
```

## Cleanup Testing

### 1. Destroy VM

```bash
terraform destroy
```

Expected: All resources removed

### 2. Verify VM Removed

```bash
virsh list --all | grep debian-trixie
```

Expected: No output (VM removed)

### 3. Verify Volumes Removed

```bash
virsh vol-list default | grep debian-trixie
```

Expected: No output (volumes removed)

## Troubleshooting Tests

### Check Cloud-Init Logs

```bash
virsh console debian-trixie-vm
journalctl -u cloud-init-local
journalctl -u cloud-init
journalctl -u cloud-final
```

### Check Serial Console Configuration

```bash
systemctl status serial-getty@ttyS0
```

### Check SSH Configuration

```bash
ssh root@<VM_IP> cat /etc/ssh/sshd_config | grep PermitRootLogin
```

Expected: `PermitRootLogin prohibit-password`

## Automated Testing Checklist

- [ ] Terraform validate passes
- [ ] Terraform fmt check passes
- [ ] At least one SSH key in ssh-keys/
- [ ] Terraform plan shows no errors
- [ ] Terraform apply succeeds
- [ ] VM appears in virsh list
- [ ] Console auto-login works
- [ ] Cloud-init status shows done
- [ ] VM has IP address
- [ ] SSH as default user works
- [ ] SSH as root works
- [ ] Default user has sudo access
- [ ] Package installation works
- [ ] Adding SSH key updates VM
- [ ] Terraform destroy completes
- [ ] All resources cleaned up

```text
(end of embedded markdown example)
```

### Step 2: Run pre-commit

Run: `pre-commit run --files yolo-vm/TESTING.md`

Expected: All checks pass

### Step 3: Commit testing guide

```bash
git add yolo-vm/TESTING.md
git commit -m "docs: add comprehensive testing guide"
```

---

## Task 11: Final Integration Test

**Files:**

- None (testing only)

### Step 1: Validate all Terraform files

Run: `cd yolo-vm && terraform init && terraform validate`

Expected: "Success! The configuration is valid."

### Step 2: Check formatting

Run: `cd yolo-vm && terraform fmt -check -recursive`

Expected: No output (all formatted) or lists formatted files

### Step 3: Run all pre-commit hooks

Run: `pre-commit run --all-files`

Expected: All hooks pass

### Step 4: Verify directory structure

Run: `tree yolo-vm/ -L 2`

Expected output:

```text
yolo-vm/
├── .gitignore
├── README.md
├── TESTING.md
├── cloud-init.yaml.tftpl
├── design-vm.md
├── main.tf
├── outputs.tf
├── ssh-keys
│   ├── .gitkeep
│   └── README.md
├── terraform.tfvars.example
└── variables.tf
```

### Step 5: Commit any remaining changes

```bash
git add -A
git status
# Review changes
git commit -m "feat: complete libvirt VM deployment configuration"
```

---

## Summary

This plan implements a complete Terraform-based VM deployment system:

- **11 tasks** covering infrastructure, documentation, and testing
- **SSH key management** via local directory
- **Console auto-login** for easy access
- **Cloud-init provisioning** for automation
- **Comprehensive documentation** for users
- **Testing guide** for validation

**Key Deliverables:**

- Terraform configuration (main.tf, variables.tf, outputs.tf)
- Cloud-init template with auto-login and SSH key injection
- SSH keys directory structure
- Comprehensive README and testing documentation
- Pre-commit integration
- Example configuration files

**Testing Strategy:**

- Terraform validation at each step
- Pre-commit hooks for code quality
- Manual testing guide in TESTING.md
- Integration testing in Task 11

**Maintenance:**

- All configuration in version control
- SSH keys managed through git
- Terraform state (gitignored) for infrastructure tracking
- Regular updates via Renovate (if configured)
