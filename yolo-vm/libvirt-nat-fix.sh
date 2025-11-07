#!/bin/bash
# Fix libvirt NAT forwarding for multi-interface hosts
# This script ensures traffic from libvirt VMs can reach the internet
# via any external interface, not just eth0

set -e -o pipefail

# Get all non-virtual interfaces (exclude lo, virbr*, docker*, br-*)
interfaces=$(ip link show | grep -E "^[0-9]+:" | awk '{print $2}' | tr -d ':' | grep -v -E "^(lo|virbr|docker|br-|vnet)")

for iface in $interfaces; do
    # Skip if interface is down
    if ! ip link show "$iface" | grep -q "state UP"; then
        continue
    fi

    # Add FORWARD rules for this interface if they don't exist
    if ! sudo iptables -C FORWARD -i virbr0 -o "$iface" -j ACCEPT 2>/dev/null; then
        echo "Adding FORWARD rule: virbr0 -> $iface"
        sudo iptables -I FORWARD 1 -i virbr0 -o "$iface" -j ACCEPT
    fi

    if ! sudo iptables -C FORWARD -i "$iface" -o virbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
        echo "Adding FORWARD rule: $iface -> virbr0 (ESTABLISHED,RELATED)"
        sudo iptables -I FORWARD 1 -i "$iface" -o virbr0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    fi
done

echo "Libvirt NAT forwarding rules updated successfully"
