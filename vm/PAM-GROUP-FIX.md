# PAM Group Initialization Fix

## Problem

Users connecting to Lima VMs via SSH were not getting their supplementary
group memberships (docker, kvm, podman) activated in their session, even
though they were listed in `/etc/group`.

## Root Cause

The `pam_group.so` PAM module was incorrectly configured in the
**session** section of `/etc/pam.d/sshd`. According to the
`pam_group(8)` man page:

> MODULE TYPES PROVIDED
> Only the **auth** module type is provided.

The module must be placed in the **auth** section, not the session
section, to function properly. This is confirmed by the working example
in `/etc/pam.d/login` which has:

```text
auth       optional   pam_group.so
```

## Fix

Changed `lima-provision.sh` to add `pam_group.so` to the **auth** section
instead of the session section:

**Before:**

```bash
sed -i '/^session.*required.*pam_loginuid.so/a session    optional \
  pam_group.so' /etc/pam.d/sshd
```

**After:**

```bash
sed -i '/^@include common-auth/a auth       optional   pam_group.so' \
  /etc/pam.d/sshd
```

## Testing

### Manual Verification

1. Create a fresh VM with the fix applied:

   ```bash
   cd vm
   ./agent-vm destroy
   ./agent-vm start
   ./agent-vm connect
   ```

2. Run the verification script:

   ```bash
   ./verify-groups.sh
   ```

3. Expected output:

   ```text
   ✓ User is in docker group in /etc/group
   ✓ docker group is ACTIVE in session
   ✓ Can write to docker socket
   ✓ pam_group.so is in AUTH section
   === SUCCESS: PAM group initialization is working! ===
   ```

### Integration Test

The integration test suite should be updated to verify group membership:

```bash
./test-integration.sh --vm
```

## Why Previous Fixes Didn't Work

Previous commits attempted to fix this issue but placed `pam_group.so` in
the session section:

- Commit `2498312`: "move pam_group.so from auth to session section" -
  This was the wrong direction
- Commit `2800265`: Added `group.conf` rules (correct) but kept it in
  auth section
- Commit `ff976bf`: Initial attempt at PAM configuration

The confusion arose because PAM has both "auth" and "session" phases, and
it seemed logical that group membership would be a "session" concern.
However, `pam_group.so` specifically implements the auth module type
only, as documented in its man page.

## References

- `man pam_group` - Documents that only auth module type is provided
- `/etc/pam.d/login` - Working reference implementation using auth
  section
- `/etc/security/group.conf` - Group rules configuration (already
  correct)
