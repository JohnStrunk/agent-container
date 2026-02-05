#!/bin/bash
# Quick verification script to check if PAM group initialization is working
# This should be run AFTER reconnecting via SSH (exit and reconnect)

echo "=== PAM Group Membership Verification ==="
echo ""

echo "1. Checking /etc/group for docker membership:"
getent group docker | grep -q "$(whoami)" && echo "   ✓ User is in docker group in /etc/group" || echo "   ✗ User NOT in docker group"

echo ""
echo "2. Checking active groups in current session:"
groups | grep -q docker && echo "   ✓ docker group is ACTIVE in session" || echo "   ✗ docker group NOT active in session"

echo ""
echo "3. Detailed group information:"
echo "   groups command: $(groups)"
echo "   id command: $(id)"

echo ""
echo "4. Checking docker socket access:"
if [ -w /var/run/docker.sock ]; then
    echo "   ✓ Can write to docker socket"
elif [ -e /var/run/docker.sock ]; then
    echo "   ✗ Docker socket exists but not writable"
else
    echo "   - Docker socket does not exist"
fi

echo ""
echo "5. PAM configuration check:"
if grep -q "^auth.*pam_group.so" /etc/pam.d/sshd; then
    echo "   ✓ pam_group.so is in AUTH section"
elif grep -q "^session.*pam_group.so" /etc/pam.d/sshd; then
    echo "   ✗ pam_group.so is in SESSION section (WRONG - won't work)"
else
    echo "   ✗ pam_group.so NOT configured"
fi

echo ""
if grep -q "^auth.*pam_group.so" /etc/pam.d/sshd && groups | grep -q docker; then
    echo "=== SUCCESS: PAM group initialization is working! ==="
else
    echo "=== FAILURE: PAM group initialization NOT working ==="
    echo ""
    echo "If PAM config is correct but groups aren't active, you need to:"
    echo "  1. Exit this session completely"
    echo "  2. Reconnect via SSH (./agent-vm connect)"
    echo "  3. Re-run this script"
fi
