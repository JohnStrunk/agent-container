# Security Policy

## Overview

This document describes the security model, threat considerations, and
best practices for the yolo-vm project. The yolo-vm is designed for
**development and testing environments** with AI coding agents and is
NOT intended for production use without significant security hardening.

## Threat Model

### Intended Use Case

- **Development/testing environment**: Local virtual machines for AI
  agent experimentation
- **Trusted environment assumption**: Host system and network are
  trusted
- **Isolated workloads**: Each VM runs in isolation via KVM/libvirt
- **Service account credentials**: Limited-scope GCP service accounts
  for Vertex AI access

### Out of Scope

This configuration is NOT designed for:

- Production workloads with sensitive data
- Multi-tenant environments
- Internet-facing services
- Untrusted code execution without additional sandboxing
- Environments where VM compromise could affect critical systems

## Security Architecture

### VM Isolation

**Hypervisor-level isolation:**

- KVM provides hardware-assisted virtualization isolation
- Each VM runs in separate memory space
- VMs cannot directly access host filesystem
- Libvirt manages resource allocation and access control

**Network isolation:**

- Default NAT network provides basic isolation
- VMs can access internet but are not directly accessible
- Host firewall rules apply to VM traffic

### Credential Management

**Service account model:**

- Dedicated GCP service account with minimal permissions
- Credentials injected via cloud-init (single-use)
- No runtime credential mounting or rotation
- Credentials stored at `/etc/google/application_default_credentials.json`

**Credential scope limitations:**

- Only Vertex AI API access granted
- No compute instance permissions
- No storage bucket access
- No project-level administrative permissions

**Credential lifecycle:**

1. Service account JSON key created manually via `gcloud`
2. Key file path specified in `terraform.tfvars`
3. Terraform reads file and injects into cloud-init
4. Cloud-init writes to VM filesystem during provisioning
5. File remains until VM destruction (no rotation mechanism)

### Access Control

**Root access:**

- Console auto-login enabled for convenience (serial console)
- Root SSH access enabled with key-based authentication only
- No password authentication for any user
- Root access assumes physical/hypervisor access is already trusted

**Default user access:**

- Limited-privilege user (default: `debian`) for normal operations
- SSH key-based authentication only
- Access to all development tools and AI agents
- Can read service account credentials (world-readable file)
- Constrained sudo access for development tasks:
  - Package management: `apt-get`, `apt`, `dpkg`
  - Service management: `systemctl`
  - No sudo required for docker/libvirt/kvm (group membership)

**SSH key management:**

- All `.pub` files in `ssh-keys/` directory are authorized
- Keys applied to both root and default user
- Removing a key file and re-applying Terraform revokes access
- Keys managed via Terraform state

## Security Features

### Authentication

- **SSH key-based only**: No password authentication
- **Multiple key support**: All keys in `ssh-keys/` directory
- **No default passwords**: System has no password-based login

### Encryption

- **SSH transport encryption**: All remote access via encrypted SSH
- **VM disk**: Not encrypted by default (can be enabled via libvirt)
- **Credentials in transit**: Injected via cloud-init (local process)

### Least Privilege

**Service account permissions:**

Recommended minimal IAM role:

```text
roles/aiplatform.user
```

This provides:

- `aiplatform.endpoints.predict` - Vertex AI inference
- `aiplatform.models.get` - Model access
- No administrative permissions

**User separation:**

- AI agents run as limited-privilege default user with constrained sudo
- Sudo access restricted to package management and service control
- Root access available via console/SSH but not required for agent operation
- Docker operations available via group membership (no sudo required)

## Known Security Limitations

### Development Environment Assumptions

1. **Console auto-login as root**
   - Risk: Physical/hypervisor access = root access
   - Mitigation: Only use in trusted environments
   - Production: Remove auto-login configuration

2. **Root SSH access enabled**
   - Risk: Root compromise if SSH key is stolen
   - Mitigation: Key-based only, no passwords
   - Production: Disable root SSH, use sudo

3. **World-readable service account credentials**
   - Risk: Any user can read Vertex AI credentials
   - Mitigation: Limited-scope service account
   - Production: Use workload identity or instance metadata

4. **No credential rotation**
   - Risk: Credentials valid until manually revoked
   - Mitigation: Short-lived deployments, manual key rotation
   - Production: Implement automated credential rotation

5. **AI agents run with broad filesystem access**
   - Risk: Agent can read/write user-accessible files
   - Mitigation: VM isolation, limited credentials
   - Production: Additional sandboxing via containers/namespaces

6. **No intrusion detection**
   - Risk: Compromises may go undetected
   - Mitigation: VM is disposable, easy to recreate
   - Production: Add logging, monitoring, IDS

7. **Constrained sudo access for default user**
   - Risk: AI agent can install packages and manage services
   - Note: Package installation effectively grants root (post-install
     scripts)
   - Mitigation: Debian repos are trusted, VM is isolated and disposable
   - Production: Remove sudo or use approval-gated package installation

### Terraform State Security

- **State contains sensitive data**: Service account credentials
- **Local state default**: Stored in `terraform.tfstate`
- **Risk**: File contains plaintext credentials

**Mitigations:**

```bash
# Ensure terraform.tfstate is not committed to version control
# (already in .gitignore)

# Set restrictive permissions
chmod 600 terraform.tfstate

# For team environments, use remote state with encryption
terraform {
  backend "gcs" {
    bucket = "your-tf-state-bucket"
    prefix = "yolo-vm"
    encryption_key = "your-kms-key"
  }
}
```

## Security Best Practices

### Service Account Creation

1. **Create dedicated service account:**

   ```bash
   PROJECT="your-project-id"
   SA_NAME="claude-code-agent"

   gcloud iam service-accounts create ${SA_NAME} \
     --display-name="Claude Code Agent (Development)" \
     --project=${PROJECT}
   ```

2. **Grant minimal permissions:**

   ```bash
   SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

   gcloud projects add-iam-policy-binding ${PROJECT} \
     --member="serviceAccount:${SA}" \
     --role="roles/aiplatform.user"
   ```

3. **Create and secure key:**

   ```bash
   gcloud iam service-accounts keys create \
     ~/claude-code-sa-key.json \
     --iam-account=${SA}

   chmod 600 ~/claude-code-sa-key.json
   ```

4. **Set expiration reminder:**

   Service account keys do not expire automatically. Set a calendar
   reminder to rotate keys every 90 days.

### SSH Key Management

1. **Use unique keys per VM:**

   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/yolo-vm-key -C "yolo-vm-access"
   cp ~/.ssh/yolo-vm-key.pub ssh-keys/
   ```

2. **Protect private keys:**

   ```bash
   chmod 600 ~/.ssh/yolo-vm-key
   ```

3. **Remove keys when decommissioning:**

   ```bash
   rm ssh-keys/oldkey.pub
   terraform apply
   ```

### VM Lifecycle Security

1. **Destroy when not in use:**

   ```bash
   terraform destroy
   ```

2. **Avoid long-running VMs:**

   Recreate VMs regularly to ensure fresh configurations and
   updated packages.

3. **Update base image:**

   Periodically update the Debian cloud image URL in `variables.tf`
   to use latest security patches.

### Network Security

1. **Use host firewall:**

   ```bash
   # Only allow SSH from specific IPs
   sudo ufw allow from 192.168.1.0/24 to any port 22
   sudo ufw enable
   ```

2. **Limit VM network access:**

   ```bash
   # In VM, restrict outbound connections if needed
   sudo ufw default deny outgoing
   sudo ufw allow out to any port 443  # HTTPS only
   sudo ufw enable
   ```

## Incident Response

### Suspected VM Compromise

1. **Immediate actions:**

   ```bash
   # Destroy VM immediately
   terraform destroy

   # Revoke service account key
   gcloud iam service-accounts keys list \
     --iam-account=${SA}

   gcloud iam service-accounts keys delete ${KEY_ID} \
     --iam-account=${SA}
   ```

2. **Investigation:**

   - Review Terraform state for unauthorized changes
   - Check GCP audit logs for unusual Vertex AI usage
   - Examine SSH access logs on host system
   - Review any persisted data from VM

3. **Recovery:**

   - Create new service account with fresh credentials
   - Rotate all SSH keys
   - Review and update terraform configuration
   - Deploy fresh VM with new credentials

### Credential Leakage

If service account credentials are exposed:

1. **Revoke immediately:**

   ```bash
   gcloud iam service-accounts keys delete ${KEY_ID} \
     --iam-account=${SA}
   ```

2. **Review usage:**

   ```bash
   gcloud logging read \
     "protoPayload.authenticationInfo.principalEmail=${SA}" \
     --limit 100 \
     --format json
   ```

3. **Create new key:**

   Follow service account creation best practices above.

### SSH Key Compromise

1. **Remove from authorized keys:**

   ```bash
   rm ssh-keys/compromised-key.pub
   terraform apply
   ```

2. **For running VMs, also remove manually:**

   ```bash
   ssh root@<VM_IP>
   vi /root/.ssh/authorized_keys
   vi /home/debian/.ssh/authorized_keys
   ```

3. **Generate new key pair:**

   Follow SSH key management best practices above.

## Reporting Security Issues

### Scope

Security issues in this project include:

- Vulnerabilities in configuration that expose unintended access
- Credential leakage via Terraform state or cloud-init
- Privilege escalation within VM
- Issues that contradict documented security model

### Non-Issues (By Design)

The following are by design and not security issues:

- Root console auto-login (documented development feature)
- World-readable service account file (documented limitation)
- No credential rotation (documented limitation)

### Reporting Process

Since this is a personal development project, report security issues via:

1. **GitHub Security Advisories** (preferred):
   Create a private security advisory in the repository

2. **GitHub Issues**:
   For non-sensitive issues, open a public issue

3. **Direct contact**:
   Contact the repository owner directly for sensitive issues

## Hardening for Production Use

If you must use this configuration for production (not recommended),
implement these hardening measures:

### Required Changes

1. **Remove console auto-login:**

   Edit `cloud-init.yaml.tftpl`:

   ```yaml
   # Remove the entire write_files section for getty override
   ```

2. **Disable root SSH:**

   Edit `cloud-init.yaml.tftpl`:

   ```yaml
   disable_root: true
   ```

3. **Implement credential rotation:**

   Use GCP Workload Identity or instance metadata instead of
   static service account keys.

4. **Enable VM disk encryption:**

   Configure libvirt volume encryption.

5. **Add monitoring and logging:**

   Configure centralized logging and alerting.

6. **Restrict service account file permissions:**

   ```yaml
   - path: /etc/google/application_default_credentials.json
     permissions: '0600'
     owner: debian:debian
   ```

7. **Implement network restrictions:**

   Use firewall rules to limit both inbound and outbound traffic.

8. **Add intrusion detection:**

   Install and configure IDS tools like AIDE or Tripwire.

### Additional Recommendations

- Use remote Terraform backend with encryption
- Implement automated security scanning
- Regular vulnerability assessments
- Principle of least privilege for all access
- Multi-factor authentication for SSH (via PAM modules)
- Container-based sandboxing for AI agents

## Compliance Considerations

This configuration does NOT meet requirements for:

- PCI DSS (Payment Card Industry Data Security Standard)
- HIPAA (Health Insurance Portability and Accountability Act)
- SOC 2 (Service Organization Control 2)
- FedRAMP (Federal Risk and Authorization Management Program)
- ISO 27001 (Information Security Management)

Do not use for workloads requiring regulatory compliance without
significant additional security controls.

## Security Update Policy

### VM Base Image

- Monitor Debian security announcements
- Update `debian_image_url` variable periodically
- Recreate VMs to apply security patches

### Installed Packages

Cloud-init installs latest versions of:

- AI agents (claude-code, gemini-cli, copilot)
- Python tools (pre-commit, poetry, pipenv, dvc)
- System packages (nodejs, docker, etc.)

Package versions are not pinned, so recreating VMs gets latest versions.

**Security tradeoff:** Latest packages may include breaking changes
but also include security fixes.

### Terraform Provider

Terraform provider versions are not pinned in this configuration.
Periodically update providers:

```bash
terraform init -upgrade
```

## References

- [Debian Security Information](https://www.debian.org/security/)
- [GCP Service Account Best Practices](https://cloud.google.com/iam/docs/best-practices-service-accounts)
- [libvirt Security](https://libvirt.org/security.html)
- [Cloud-Init Security Considerations](https://cloudinit.readthedocs.io/en/latest/reference/security.html)
- [KVM Security](https://www.linux-kvm.org/page/Security)
