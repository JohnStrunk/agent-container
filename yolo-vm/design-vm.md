# VM Deployment Design for Debian 13 (Trixie)

## Overview

This design document describes the approach for deploying a Debian 13
(Trixie) virtual machine using libvirt and infrastructure-as-code
principles. The solution prioritizes maintainability of both the code
and the underlying libraries.

## Infrastructure-as-Code Tool Selection

### Research Findings

Two primary options were evaluated for managing libvirt VMs with IaC:

1. **Vagrant with libvirt provider**
2. **Terraform with libvirt provider**

### Vagrant-libvirt Analysis

**Repository**: vagrant-libvirt/vagrant-libvirt

**Latest Release**: v0.12.2 (June 2023)

**Pros**:

- Mature plugin with established user base
- Purpose-built for development VM management
- Simple declarative syntax via Vagrantfile
- Good documentation and community support
- Native integration with Vagrant ecosystem

**Cons**:

- Latest release over 18 months old (as of March 2025)
- Ruby-based, requires Ruby ecosystem knowledge
- Primarily focused on development workflows
- Less suitable for production-like deployments

### Terraform-libvirt Analysis

**Repository**: dmacvicar/terraform-provider-libvirt

**Latest Release**: v0.8.3 (March 2025)

**Stars**: 1,724 GitHub stars

**Pros**:

- Very recent release activity (March 2025)
- Active maintenance demonstrated by recent updates
- Go-based, aligns with modern IaC tooling
- Integrates with broader Terraform ecosystem
- Supports complex infrastructure scenarios
- Better suited for production-style deployments
- Strong community adoption (1.7k+ stars)

**Cons**:

- Slightly more complex syntax than Vagrant
- Requires Terraform knowledge
- May be overkill for simple development VMs

### Maintainability Comparison

| Criterion | Vagrant-libvirt | Terraform-libvirt |
|-----------|-----------------|-------------------|
| Latest Release | June 2023 | March 2025 |
| Release Cadence | Slowing | Active |
| Community Stars | ~420 repos | 1,724 stars |
| Language | Ruby | Go |
| Ecosystem | Vagrant | Terraform |
| Production Ready | Limited | Yes |

### Recommendation

**Use Terraform with the libvirt provider** for the following reasons:

1. **Active Maintenance**: March 2025 release demonstrates ongoing
   support and bug fixes
2. **Modern Tooling**: Go-based provider aligns with industry trends
3. **Scalability**: Can grow from single VM to complex infrastructure
4. **Broader Ecosystem**: Terraform knowledge transfers across clouds
5. **Production Readiness**: Better suited for long-term deployments

While Vagrant is excellent for quick development VMs, Terraform offers
better long-term maintainability and alignment with modern IaC practices.

## VM Design Specification

### Target Platform

- **OS**: Debian 13 (Trixie)
- **Hypervisor**: libvirt/KVM
- **Architecture**: x86_64 (amd64)

### Infrastructure Components

#### VM Configuration

```hcl
resource "libvirt_domain" "debian_trixie" {
  name   = "debian-trixie-vm"
  memory = "2048"  # 2GB RAM
  vcpu   = 2

  disk {
    volume_id = libvirt_volume.debian_trixie.id
  }

  network_interface {
    network_name = "default"
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  # Console will auto-login as root without password prompt
}
```

#### Storage

- **Base Image**: Official Debian 13 (Trixie) cloud image
- **Disk Size**: 20GB (configurable)
- **Format**: qcow2 for space efficiency

#### Networking

- **Default libvirt network**: NAT-based connectivity
- **Static IP**: Optional, via DHCP reservation or cloud-init
- **Hostname**: Configurable via cloud-init

### Provisioning Strategy

Use **cloud-init** for initial VM configuration:

- User creation and SSH key injection
- Package installation
- Network configuration
- Hostname setup
- System configuration
- Console auto-login as root
- SSH access for both default user and root

#### Console Auto-login

The VM console will be configured to automatically log in as root
without requiring password authentication. This is achieved through:

- systemd override for getty service on serial console
- Automatic login configuration in cloud-init

#### SSH Key Management

SSH authorized keys will be managed through a dedicated directory:

- **Location**: `ssh-keys/` directory in the yolo-vm repository
- **Format**: `.pub` files containing public SSH keys
- **Provisioning**: Keys are read by Terraform and injected via cloud-init
- **Access**: Keys grant SSH access to both the default user and root

This approach allows:

- Version control of authorized keys
- Easy addition/removal of keys by updating files
- Consistent access across VM rebuilds

### Directory Structure

```text
yolo-vm/
├── design-vm.md           # This document
├── main.tf                # Primary Terraform configuration
├── variables.tf           # Input variables
├── outputs.tf             # Output values
├── terraform.tfvars       # Variable values (gitignored)
├── cloud-init.yaml        # Cloud-init configuration
├── ssh-keys/              # SSH public keys for VM access
│   └── *.pub              # Public key files
└── README.md              # Usage instructions
```

### Key Features

1. **Reproducible**: Infrastructure defined as code
2. **Version Controlled**: All configuration in git
3. **Declarative**: Desired state specification
4. **Maintainable**: Clear structure and documentation
5. **Secure**: SSH key-based access, no passwords

## Implementation Considerations

### Prerequisites

- libvirt/KVM installed and running
- Terraform >= 1.0
- terraform-provider-libvirt plugin
- Network connectivity for downloading Debian images

### Security

- No password authentication (console auto-login, SSH keys only)
- SSH key-only authentication for both default user and root
- Console auto-login as root (physical/virtual console access)
- Root SSH access enabled with key-based authentication
- Firewall configuration via cloud-init
- Regular updates via Debian security repos
- SSH keys version-controlled in ssh-keys/ directory

**Note**: This configuration prioritizes convenience for development/testing
environments. The console auto-login and root SSH access assume the VM
is running in a trusted environment (local libvirt instance).

### Maintenance

- Pin Terraform provider versions
- Document provider version in code
- Use Renovate or similar for dependency updates
- Test upgrades in isolated environment

## Next Steps

When implementation begins:

1. Create Terraform configuration files
2. Define cloud-init user-data
3. Configure variables for customization
4. Test deployment with clean libvirt environment
5. Document usage in README.md
6. Add pre-commit hooks for Terraform validation
