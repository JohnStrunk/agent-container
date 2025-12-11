# Testing Notes for Nested VM Network Autodetection

## Branch: fix-nested-vm-initialization

## What Was Implemented

Added automatic network subnet detection to avoid conflicts when running
yolo-vm inside yolo-vm (nested virtualization).

### Key Changes

1. **variables.tf**: Added `network_subnet_third_octet` variable (default:
   123)
2. **main.tf**: Network configuration uses variable for dynamic subnet
3. **vm-up.sh**: Autodetection logic that:
   - Detects current VM's IP on 192.168.x.x network
   - If on 192.168.122.x or 192.168.123.x → uses 192.168.200.0/24
   - Otherwise → uses 192.168.(current+1).0/24
   - Falls back to 192.168.123.0/24 if not on 192.168.x.x
4. **README.md**: Documentation for nested virtualization with autodetection
5. **cloud-init.yaml.tftpl**: Initializes libvirt storage pool and removes
   pre-existing network

## Testing Status

### ✅ Validated

- **Autodetection logic works correctly**:
  ```
  Detected outer VM network: 192.168.123.0/24
  Using subnet 192.168.200.0/24 for nested VM
  ```
- Terraform configuration validates successfully
- Network resource shows correct subnet in terraform plan

### ❌ Blocked During Testing

Encountered permission issue when trying to create nested VM:

```
Could not open '/var/lib/libvirt/images/debian-13-base.qcow2':
Permission denied
```

**Root cause**: The outer VM (192.168.123.247) was created BEFORE the
cloud-init changes that initialize the libvirt storage pool. This outer
VM lacks proper storage pool setup.

**Expected behavior**: New VMs created with updated cloud-init will
have storage pool properly initialized (see cloud-init.yaml.tftpl:48-54).

### 🔄 Needs Testing

1. **Create fresh outer VM** with updated cloud-init
2. **SSH into outer VM**
3. **Run nested VM creation**:
   ```bash
   cd ~/workspace/yolo-vm
   ./vm-up.sh
   ```
4. **Verify**:
   - Autodetection message appears
   - Nested VM uses 192.168.200.0/24 network
   - VM starts successfully
   - No network conflicts
   - Can SSH into nested VM

## How to Resume Testing

### Step 1: Recreate Outer VM

From the host system:

```bash
cd /path/to/yolo-vm
git checkout fix-nested-vm-initialization
./vm-down.sh  # Clean up old VM
./vm-up.sh    # Create new VM with updated cloud-init
```

### Step 2: Setup Nested VM Repository

SSH into the outer VM and set up the yolo-vm repository:

```bash
ssh user@<OUTER_VM_IP>
cd ~/workspace
git clone <yolo-vm-repo-url>
cd yolo-vm
git checkout fix-nested-vm-initialization
cp -r ~/path/to/ssh-keys ./ssh-keys/  # Copy SSH keys
```

### Step 3: Test Nested VM Creation

```bash
# Still in outer VM at ~/workspace/yolo-vm
./vm-up.sh
```

**Expected output**:
```
Detected outer VM network: 192.168.123.0/24
Using subnet 192.168.200.0/24 for nested VM
...
[Terraform output showing 192.168.200.0/24 network]
...
[VM creation succeeds]
```

### Step 4: Verify Network Configuration

```bash
# Check nested VM's network
virsh net-dumpxml default

# Should show:
# <ip address='192.168.200.1' netmask='255.255.255.0'>
#   <dhcp>
#     <range start='192.168.200.2' end='192.168.200.254'/>
```

### Step 5: Verify VM Connectivity

```bash
# Get nested VM IP
terraform output vm_ip

# SSH into nested VM
ssh user@<NESTED_VM_IP>

# Verify no network conflicts
ping -c 3 8.8.8.8
```

### Step 6: Test Cleanup

```bash
# In outer VM
./vm-down.sh

# Verify network is removed
virsh net-list --all
```

## Expected Test Results

- ✅ Autodetection correctly identifies outer VM network
- ✅ Nested VM uses 192.168.200.0/24 (different from outer VM's
  192.168.123.0/24)
- ✅ Both VMs can access internet
- ✅ No routing conflicts
- ✅ Can SSH into both VMs simultaneously

## Known Limitations

1. **Manual override**: Users can still override with `export
   NETWORK_SUBNET=150`
2. **Subnet collision**: If outer VM uses 192.168.200.x, autodetection
   would use 192.168.201.x (current+1)
3. **No multi-level nesting check**: Doesn't detect if already nested
   multiple levels

## Files Modified

- `yolo-vm/main.tf`
- `yolo-vm/variables.tf`
- `yolo-vm/vm-up.sh`
- `yolo-vm/README.md`
- `yolo-vm/cloud-init.yaml.tftpl`

## Git Log

```
d42a196 fix: make VM network subnet configurable with autodetection
06f94d2 Merge pull request #640 from JohnStrunk/update-libvirt
9adb4de feat: add nested virtualization support to yolo-vm
```

## Additional Context

The autodetection works by checking the current system's IP address and
intelligently selecting a non-conflicting subnet. This allows seamless
nested VM creation without requiring users to manually configure network
settings.

The cloud-init configuration ensures that new VMs have libvirt properly
initialized with:
- Default storage pool created and started
- Proper permissions on /var/lib/libvirt/images (755)
- Pre-existing default network removed to avoid conflicts

This makes yolo-vm fully self-contained for nested virtualization use
cases.
