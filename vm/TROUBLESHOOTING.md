# agent-vm Troubleshooting Guide

## Common Issues and Solutions

### Lima Not Installed

**Symptom**: `limactl: command not found`

**Cause**: Lima is not installed on your system

**Solution**:

```bash
# Linux (Debian/Ubuntu)
sudo apt-get update
sudo apt-get install lima

# macOS
brew install lima

# Verify installation
limactl --version
```

### SSHFS Not Installed

**Symptom**: Warning about SSHFS not being available, or mount failures

**Cause**: SSHFS is not installed on your system

**Solution**:

```bash
# Linux (Debian/Ubuntu)
sudo apt-get install sshfs

# macOS
brew install macfuse
brew install sshfs

# Verify installation
which sshfs
```

### VM Won't Start

**Symptom**: `./agent-vm start` fails or hangs

**Possible Causes and Solutions**:

1. **Insufficient resources**:

   ```bash
   # Check available system resources
   free -h  # Linux
   vm_stat  # macOS

   # Start with lower resources
   ./agent-vm destroy
   ./agent-vm start --memory 4 --vcpu 2
   ```

2. **QEMU not installed**:

   ```bash
   # Linux
   sudo apt-get install qemu-system-x86

   # macOS
   brew install qemu
   ```

3. **Corrupted Lima state**:

   ```bash
   # Complete cleanup and restart
   ./agent-vm destroy
   rm -rf ~/.lima/agent-vm
   ./agent-vm start
   ```

4. **Port conflict**:
   Lima auto-assigns SSH ports, but if other Lima VMs are running:

   ```bash
   # Check running Lima VMs
   limactl list

   # Stop other VMs if needed
   limactl stop <vm-name>
   ```

### VM Starts But Provisioning Fails

**Symptom**: VM starts but `agent-vm status` shows errors or packages missing

**Debugging**:

1. **Check provisioning logs**:

   ```bash
   # SSH into VM
   limactl shell agent-vm

   # Check system provisioning logs
   journalctl -u lima-init | less

   # Check for specific errors
   journalctl -u lima-init | grep -i error
   ```

2. **Verify package installation**:

   ```bash
   limactl shell agent-vm

   # Check Debian packages
   dpkg -l | grep <package-name>

   # Check Node.js packages
   npm list -g

   # Check Python packages
   pip list
   ```

3. **Check provisioning script**:

   ```bash
   # View the provisioning script
   cat vm/lima-provision.sh

   # Validate it with shellcheck
   shellcheck vm/lima-provision.sh
   ```

4. **Retry provisioning**:

   ```bash
   # Destroy and recreate VM
   ./agent-vm destroy
   ./agent-vm start
   ```

### SSHFS Mount Failures

**Symptom**: Cannot access files at `~/.agent-vm-mounts/workspace/`, or
"Transport endpoint is not connected" errors

**Solutions**:

1. **Stale mount** (most common):

   ```bash
   # Linux
   fusermount -u ~/.agent-vm-mounts/workspace

   # macOS
   umount ~/.agent-vm-mounts/workspace

   # Remount by connecting to any workspace
   ./agent-vm connect test-branch
   ```

2. **VM not running**:

   ```bash
   # Check VM status
   ./agent-vm status

   # Start VM if stopped
   ./agent-vm start
   ```

3. **SSH connection issues**:

   ```bash
   # Test SSH connectivity
   limactl shell agent-vm

   # Or using SSH config directly
   ssh -F ~/.lima/agent-vm/ssh.config lima-agent-vm

   # If SSH fails, restart VM
   ./agent-vm destroy
   ./agent-vm start
   ```

4. **Mount directory permissions**:

   ```bash
   # Check mount directory exists and has correct permissions
   ls -ld ~/.agent-vm-mounts/workspace

   # Recreate if needed
   rm -rf ~/.agent-vm-mounts/workspace
   mkdir -p ~/.agent-vm-mounts/workspace
   ```

### Git Push/Fetch Errors

**Symptom**: `./agent-vm push` or `./agent-vm fetch` fails with git errors

**Common Issues**:

1. **Push rejected (non-fast-forward)**:

   ```bash
   # VM workspace has commits not in host branch
   # Fetch first, then push
   ./agent-vm fetch feature-name
   git merge  # or git rebase
   ./agent-vm push feature-name
   ```

2. **SSH authentication failure**:

   ```bash
   # Verify SSH config exists
   cat ~/.lima/agent-vm/ssh.config

   # Test git over SSH
   export GIT_SSH_COMMAND="ssh -F ~/.lima/agent-vm/ssh.config"
   git ls-remote ssh://lima-agent-vm/home/user/workspace/<repo>-<branch>
   unset GIT_SSH_COMMAND

   # If SSH config missing, recreate VM
   ./agent-vm destroy
   ./agent-vm start
   ```

3. **Workspace doesn't exist**:

   ```bash
   # For fetch operations, workspace must exist first
   # Use push or connect to create it
   ./agent-vm connect feature-name
   # Make changes in VM, then:
   ./agent-vm fetch feature-name
   ```

4. **Uncommitted changes in VM**:

   ```bash
   # Fetch warns about uncommitted changes
   # Connect to VM and commit them
   ./agent-vm connect feature-name
   # In VM:
   git add .
   git commit -m "Save work"
   exit

   # Now fetch will work
   ./agent-vm fetch feature-name
   ```

### Performance Issues

**Symptom**: VM is slow or unresponsive

**Platform-Specific Solutions**:

#### Linux

1. **Check if KVM acceleration is available**:

   ```bash
   # Check if KVM is available
   ls /dev/kvm

   # If missing, load KVM module
   sudo modprobe kvm
   sudo modprobe kvm_intel  # or kvm_amd

   # Verify user is in kvm group
   groups | grep kvm
   sudo usermod -aG kvm $USER
   # Log out and back in for group change to take effect
   ```

2. **Enable nested virtualization** (if running in a VM):

   ```bash
   # Check if nested virtualization is enabled
   cat /sys/module/kvm_intel/parameters/nested  # Intel
   cat /sys/module/kvm_amd/parameters/nested    # AMD

   # Enable nested virtualization (requires host configuration)
   # This must be done on the host machine, not in Lima
   ```

3. **Increase VM resources**:

   ```bash
   ./agent-vm destroy
   ./agent-vm start --memory 16 --vcpu 8
   ```

#### macOS

**Note**: macOS uses QEMU emulation (not hardware virtualization), so
performance will be slower than Linux with KVM.

1. **Increase VM resources**:

   ```bash
   ./agent-vm destroy
   ./agent-vm start --memory 16 --vcpu 8
   ```

2. **Close unnecessary applications** to free up system resources

3. **Consider using Rosetta 2** (Apple Silicon only):
   Lima can use Rosetta 2 for better x86 emulation on Apple Silicon, but
   this requires Lima configuration changes beyond agent-vm's scope.

### Resource Changes Not Applied

**Symptom**: Using `--memory` or `--vcpu` with existing VM doesn't change resources

**Cause**: Resource specifications only work at VM creation time

**Solution**:

```bash
# Destroy existing VM
./agent-vm destroy

# Create new VM with desired resources
./agent-vm start --memory 16 --vcpu 8

# Verify resources
./agent-vm status
```

### Credential Injection Problems

**Symptom**: Claude Code fails with authentication errors, or
`GOOGLE_APPLICATION_CREDENTIALS` not set

**Causes and Solutions**:

1. **Credentials not detected during VM creation**:

   ```bash
   # Credentials are injected during provisioning only
   # Check if credentials existed when VM was created

   # On host, verify credentials exist
   echo $GOOGLE_APPLICATION_CREDENTIALS
   cat ~/.config/gcloud/application_default_credentials.json

   # Recreate VM to inject credentials
   ./agent-vm destroy
   export GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/application_default_credentials.json
   ./agent-vm start
   ```

2. **Verify credentials in VM**:

   ```bash
   ./agent-vm connect

   # Check environment variables
   echo $GOOGLE_APPLICATION_CREDENTIALS
   echo $ANTHROPIC_VERTEX_PROJECT_ID
   echo $CLAUDE_CODE_USE_VERTEX

   # Check credentials file
   cat /etc/google/application_default_credentials.json

   # Check profile.d script
   cat /etc/profile.d/ai-agent-env.sh
   ```

3. **Wrong project ID**:

   ```bash
   # Set project ID before creating VM
   export ANTHROPIC_VERTEX_PROJECT_ID="your-project-id"
   ./agent-vm destroy
   ./agent-vm start
   ```

### Environment Variable Issues

**Symptom**: Environment variables from host not available in VM

**Cause**: Only variables listed in `common/packages/envvars.txt` are
passed through

**Solution**:

1. **Add variable to envvars.txt**:

   ```bash
   # Edit common/packages/envvars.txt
   echo "MY_VARIABLE" >> common/packages/envvars.txt

   # Commit the change
   git add common/packages/envvars.txt
   git commit -m "Add MY_VARIABLE to envvars.txt"
   ```

2. **Set variable on host**:

   ```bash
   export MY_VARIABLE="value"
   ```

3. **Connect to workspace** (variable will be passed through):

   ```bash
   ./agent-vm connect feature-name
   echo $MY_VARIABLE  # Should show "value"
   ```

**Note**: For system-wide variables (like GCP credentials), use the
provisioning script and `/etc/profile.d/` instead.

### VM State Corruption Recovery

**Symptom**: VM behaves erratically, commands fail randomly, or data
appears corrupted

**Solution**:

1. **Save important work**:

   ```bash
   # Commit work in all active workspaces
   ./agent-vm connect workspace-1
   git add .
   git commit -m "Save work before VM rebuild"
   exit

   # Fetch to host
   ./agent-vm fetch workspace-1
   ```

2. **Complete VM rebuild**:

   ```bash
   # Destroy VM completely
   ./agent-vm destroy

   # Clean up Lima state
   rm -rf ~/.lima/agent-vm

   # Create fresh VM
   ./agent-vm start

   # Recreate workspaces
   ./agent-vm connect workspace-1
   ```

### Nested Virtualization Limitations

**Symptom**: Cannot run Docker, Podman, or Lima inside the VM

**Causes**:

1. **KVM not available** (Linux):

   ```bash
   # In VM, check for KVM
   ./agent-vm connect
   ls /dev/kvm

   # If missing, nested virtualization is not enabled
   # This requires host machine configuration
   ```

2. **No nested support** (macOS):
   macOS using QEMU emulation doesn't support nested virtualization well.

**Workarounds**:

1. **Use Docker/Podman without KVM**:

   ```bash
   # Docker and Podman should work even without KVM
   # Performance will be slower
   docker run hello-world
   podman run hello-world
   ```

2. **Lima nested VMs** (limited):
   Lima can run inside Lima, but performance will be poor:

   ```bash
   ./agent-vm connect
   limactl start --vm-type=qemu template.yaml
   # Expect very slow performance
   ```

3. **Use container approach instead**:
   If you need fast nested containerization, consider using the container
   approach instead of VM approach.

### Platform-Specific Issues

#### Linux-Specific

1. **Permission denied for /dev/kvm**:

   ```bash
   sudo usermod -aG kvm $USER
   # Log out and back in
   ```

2. **fusermount not found**:

   ```bash
   sudo apt-get install fuse
   ```

3. **Network conflicts**:

   ```bash
   # Lima uses user-mode networking by default
   # If network issues, check firewall
   sudo ufw status
   ```

#### macOS-Specific

1. **macFUSE installation required for SSHFS**:

   ```bash
   brew install macfuse
   brew install sshfs

   # May require system reboot for macFUSE kernel extension
   sudo reboot
   ```

2. **umount vs fusermount**:
   macOS only supports `umount`, not `fusermount -u`:

   ```bash
   # Always use umount on macOS
   umount ~/.agent-vm-mounts/workspace
   ```

3. **Slower performance expected**:
   macOS uses QEMU emulation without KVM acceleration, so VMs will be
   slower than on Linux. This is expected behavior.

### Mount Directories Accumulating

**Symptom**: Old empty directories in `~/.agent-vm-mounts/`

**Cause**: Mount point directories created but not cleaned up when
workspaces deleted

**Solution**:

```bash
# Safe cleanup (only removes empty directories)
find ~/.agent-vm-mounts -type d -empty -delete
```

### Lima Version Compatibility

**Symptom**: `agent-vm.yaml` template fails validation or VM creation fails

**Cause**: Lima version too old or too new

**Solution**:

```bash
# Check Lima version
limactl --version

# Update Lima
# Linux
sudo apt-get update
sudo apt-get install lima

# macOS
brew upgrade lima

# Verify template validates
limactl validate vm/agent-vm.yaml
```

## Diagnostic Commands

### Check VM Status

```bash
# Using agent-vm script
./agent-vm status

# Using Lima directly
limactl list

# Detailed VM info (JSON)
limactl list --format json | jq

# Check if VM is running
limactl list | grep agent-vm
```

### Check Lima State

```bash
# Lima state directory
ls -la ~/.lima/agent-vm/

# SSH configuration
cat ~/.lima/agent-vm/ssh.config

# Lima metadata
cat ~/.lima/agent-vm/lima.yaml

# VM disk image
ls -lh ~/.lima/agent-vm/*.qcow2
```

### Check Workspaces

```bash
# List workspaces in VM
./agent-vm status

# Or via SSH
limactl shell agent-vm
ls -la ~/workspace/

# Check specific workspace
limactl shell agent-vm
cd ~/workspace/<repo>-<branch>
git status
```

### Check SSHFS Mounts

```bash
# Check if mounted
mountpoint ~/.agent-vm-mounts/workspace

# List mount options
mount | grep agent-vm-mounts

# Test read/write
ls ~/.agent-vm-mounts/workspace/
touch ~/.agent-vm-mounts/workspace/test-file
rm ~/.agent-vm-mounts/workspace/test-file
```

### Check Network Configuration

```bash
# Lima handles networking automatically
# Check VM network info
limactl shell agent-vm
ip addr show
ip route

# Test internet connectivity from VM
limactl shell agent-vm
ping -c 3 google.com
curl -I https://www.google.com
```

### Check Provisioning

```bash
# SSH into VM
limactl shell agent-vm

# Check provisioning logs
journalctl -u lima-init | less
journalctl -u lima-init | grep -i error

# Check environment marker
cat /etc/agent-environment

# Check installed packages
dpkg -l | grep -E 'claude|git|nodejs'
npm list -g --depth=0
pip list

# Check homedir files
ls -la ~/.claude.json
ls -la ~/.gitconfig
ls -la ~/.claude/settings.json
ls -la ~/.local/bin/start-claude

# Check GCP credentials
cat /etc/google/application_default_credentials.json
cat /etc/profile.d/ai-agent-env.sh
```

### Check Git Configuration

```bash
# Verify SSH config exists
cat ~/.lima/agent-vm/ssh.config

# Test SSH connection
ssh -F ~/.lima/agent-vm/ssh.config lima-agent-vm echo "SSH works"

# Test git over SSH
export GIT_SSH_COMMAND="ssh -F ~/.lima/agent-vm/ssh.config"
git ls-remote ssh://lima-agent-vm/home/user/workspace/<repo>-<branch>
unset GIT_SSH_COMMAND
```

### Check Resource Usage

```bash
# In VM
limactl shell agent-vm

# CPU and memory usage
top
htop  # if installed

# Disk usage
df -h
du -sh ~/workspace/*

# Check VM resource allocation
limactl list --format json | jq '.[0] | {cpus, memory, disk}'
```

## Getting Help

If you encounter issues not covered here:

1. **Check Lima documentation**: <https://lima-vm.io/docs/>
2. **Check provisioning logs**:

   ```bash
   limactl shell agent-vm
   journalctl -u lima-init | less
   ```

3. **Review recent commits**: `git log --oneline -- vm/`
4. **Validate template**: `limactl validate vm/agent-vm.yaml`
5. **Report issue** with:
   - Output of `./agent-vm status`
   - Output of `limactl list`
   - Platform (`uname -a`)
   - Lima version (`limactl --version`)
   - Error messages from agent-vm
   - Relevant logs from `journalctl -u lima-init`

## Clean Start Procedure

If everything is broken and you want to start completely fresh:

```bash
# 1. Save any important work
./agent-vm connect workspace-name
git add .
git commit -m "Save work before cleanup"
./agent-vm fetch workspace-name

# 2. Destroy VM
./agent-vm destroy

# 3. Clean up all Lima state
rm -rf ~/.lima/agent-vm

# 4. Clean up mount directories
rm -rf ~/.agent-vm-mounts

# 5. Verify Lima is installed
limactl --version

# 6. Verify SSHFS is installed
which sshfs

# 7. Create fresh VM
./agent-vm start

# 8. Verify provisioning
./agent-vm status
./agent-vm connect
# Check packages, configs, etc.
exit

# 9. Recreate workspaces
./agent-vm connect workspace-name
```
