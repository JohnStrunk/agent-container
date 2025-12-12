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

### 1. Test Constrained Sudo Access (Default User)

Test allowed commands:

```bash
# Test package management sudo access
ssh debian@<VM_IP> sudo apt-get update
ssh debian@<VM_IP> sudo apt-get install -y tree

# Test service management sudo access
ssh debian@<VM_IP> sudo systemctl status ssh

# Verify tree was installed
ssh debian@<VM_IP> which tree
```

Expected: All commands succeed, tree binary is installed

Test that unauthorized sudo commands are blocked:

```bash
# Should fail - not in allowed list
ssh debian@<VM_IP> sudo cat /etc/shadow
```

Expected: Permission denied or sudo error

### 2. Test Package Installation as Root

```bash
ssh root@<VM_IP> apt-get update
ssh root@<VM_IP> apt-get install -y htop
ssh root@<VM_IP> which htop
```

Expected: Shows path to htop binary

### 3. Test Serial Console Login

```bash
virsh console debian-trixie-vm
# Should auto-login as root
whoami
```

Expected: `root`

## AI Agent Testing

### 1. Verify Agent Installation

```bash
ssh debian@<VM_IP> which claude-code
ssh debian@<VM_IP> which gemini
ssh debian@<VM_IP> which github-copilot
```

Expected: Paths to all three agents

### 2. Verify Development Tools

```bash
ssh debian@<VM_IP> which uv
ssh debian@<VM_IP> which go
ssh debian@<VM_IP> which pre-commit
ssh debian@<VM_IP> which poetry
```

Expected: All tools available in PATH

### 3. Check Environment Variables (if GCP credentials configured)

```bash
ssh debian@<VM_IP> 'echo $GOOGLE_APPLICATION_CREDENTIALS'
ssh debian@<VM_IP> 'echo $ANTHROPIC_VERTEX_PROJECT_ID'
ssh debian@<VM_IP> 'echo $CLAUDE_CODE_USE_VERTEX'
```

Expected: Variables set to configured values

### 4. Verify GCP Credentials File (if configured)

```bash
ssh debian@<VM_IP> cat /etc/google/application_default_credentials.json
```

Expected: Valid JSON service account key

### 5. Test Claude Code Version

```bash
ssh debian@<VM_IP> claude-code --version
```

Expected: Version number displayed

### 6. Test Python Tools

```bash
ssh debian@<VM_IP> pre-commit --version
ssh debian@<VM_IP> poetry --version
```

Expected: Version numbers displayed

### 7. Test Go Installation

```bash
ssh debian@<VM_IP> go version
```

Expected: go version go1.25.0 linux/amd64

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
- [ ] claude-code installed and accessible
- [ ] gemini-cli installed and accessible
- [ ] github-copilot installed and accessible
- [ ] uv available in PATH
- [ ] go version 1.25.0 installed
- [ ] pre-commit installed
- [ ] poetry installed
- [ ] Environment variables configured (if GCP creds provided)
- [ ] GCP credentials file exists (if configured)
