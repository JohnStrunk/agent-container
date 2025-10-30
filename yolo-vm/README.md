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
