#!/bin/bash
# Fix libvirt NAT forwarding for multi-interface hosts
# This script ensures traffic from libvirt VMs can reach the internet
# via any active external interface (WiFi, Ethernet, VPN, etc.)

set -e -o pipefail

# Get all active libvirt network bridges
libvirt_bridges=$(virsh --connect qemu:///system net-list --all 2>/dev/null | \
    awk 'NR>2 && $1 != "" {print $1}' | \
    while read -r net; do
        virsh --connect qemu:///system net-dumpxml "$net" 2>/dev/null | \
            grep -oP "bridge name='\K[^']+" || true
    done)

if [ -z "$libvirt_bridges" ]; then
    echo "No libvirt bridges found. Skipping NAT fix."
    exit 0
fi

# Get all non-virtual interfaces (exclude lo, virbr*, docker*, br-*, vnet*)
external_interfaces=$(ip link show | \
    grep -E "^[0-9]+:" | \
    awk '{print $2}' | \
    tr -d ':' | \
    grep -v -E "^(lo|virbr|docker|br-|vnet)")

if [ -z "$external_interfaces" ]; then
    echo "No external interfaces found. Skipping NAT fix."
    exit 0
fi

# For each libvirt bridge and each active external interface, add FORWARD rules
for bridge in $libvirt_bridges; do
    for iface in $external_interfaces; do
        # Skip if interface is down
        if ! ip link show "$iface" 2>/dev/null | grep -q "state UP"; then
            continue
        fi

        # Add FORWARD rules if they don't exist
        if ! sudo iptables -C FORWARD -i "$bridge" -o "$iface" -j ACCEPT 2>/dev/null; then
            echo "Adding FORWARD rule: $bridge -> $iface"
            sudo iptables -I FORWARD 1 -i "$bridge" -o "$iface" -j ACCEPT
        fi

        if ! sudo iptables -C FORWARD -i "$iface" -o "$bridge" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
            echo "Adding FORWARD rule: $iface -> $bridge (ESTABLISHED,RELATED)"
            sudo iptables -I FORWARD 1 -i "$iface" -o "$bridge" -m state --state RELATED,ESTABLISHED -j ACCEPT
        fi
    done
done

echo "Libvirt NAT forwarding rules updated successfully"
