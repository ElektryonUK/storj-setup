#!/bin/bash

# This script sets up a WireGuard VPN and configures selective port routing.
# It ensures only Storj node traffic is routed through the VPN.

# Configuration Variables
VPN_INTERFACE="wg0"          # Name of the WireGuard interface
VPN_IP_HOME="10.0.0.2"       # Private VPN IP for the home server
VPN_IP_VPS="10.0.0.1"        # Private VPN IP for the VPS
TABLE_ID=200                 # Custom routing table ID for selective traffic
VPN_PORT=51820               # WireGuard VPN listening port on the VPS

echo "This script will set up a WireGuard VPN and configure selective port routing."

# Ensure the script is run as a user with sudo privileges
if [[ $(id -u) -ne 0 ]]; then
    echo "Please run this script with sudo or as root."
    exit 1
fi

# Ask if this setup is for the VPS or the Home Server
echo "Are you setting up this script on the VPS or Home Server? (Enter 'vps' or 'home')"
read SERVER_TYPE

# Validate input
if [[ "$SERVER_TYPE" != "vps" && "$SERVER_TYPE" != "home" ]]; then
    echo "Invalid input. Please enter 'vps' or 'home'."
    exit 1
fi

# Install required packages (WireGuard and iptables-persistent for firewall rules)
echo "Installing required packages..."
sudo apt update && sudo apt install -y wireguard iptables-persistent

# Generate WireGuard private and public keys
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

# VPS Configuration
if [[ "$SERVER_TYPE" == "vps" ]]; then
    echo "Setting up WireGuard on the VPS..."

    # Save the private key securely
    echo "$PRIVATE_KEY" | sudo tee /etc/wireguard/privatekey > /dev/null
    sudo chmod 600 /etc/wireguard/privatekey

    # Create WireGuard configuration file for the VPS
    sudo tee /etc/wireguard/$VPN_INTERFACE.conf > /dev/null <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $VPN_IP_VPS/24
ListenPort = $VPN_PORT

# NAT to allow forwarding traffic to the internet
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <HOME_SERVER_PUBLIC_KEY>  # Replace with the home server's public key
AllowedIPs = $VPN_IP_HOME/32
PersistentKeepalive = 25
EOF

    # Start WireGuard and enable it to run at boot
    sudo systemctl enable wg-quick@$VPN_INTERFACE
    sudo systemctl start wg-quick@$VPN_INTERFACE

    # Display the VPS public key to be shared with the home server
    echo "WireGuard VPN setup is complete on the VPS."
    echo "Share the following details with your home server:"
    echo "VPS Public Key: $PUBLIC_KEY"
    echo "VPS IP Address: $(curl -s ifconfig.me)"
    echo "Private VPN IP (VPS): $VPN_IP_VPS"
    echo "VPN Port: $VPN_PORT"

    exit 0
fi

# Home Server Configuration
if [[ "$SERVER_TYPE" == "home" ]]; then
    echo "Setting up WireGuard on the Home Server..."

    # Ask for the VPS's public key and IP address
    echo "Enter the public key from the VPS:"
    read VPS_PUBLIC_KEY

    echo "Enter the public IP of the VPS:"
    read VPS_IP

    # Save the private key securely
    echo "$PRIVATE_KEY" | sudo tee /etc/wireguard/privatekey > /dev/null
    sudo chmod 600 /etc/wireguard/privatekey

    # Create WireGuard configuration file for the Home Server
    sudo tee /etc/wireguard/$VPN_INTERFACE.conf > /dev/null <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $VPN_IP_HOME/24

[Peer]
PublicKey = $VPS_PUBLIC_KEY
Endpoint = $VPS_IP:$VPN_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    # Start WireGuard and enable it to run at boot
    sudo systemctl enable wg-quick@$VPN_INTERFACE
    sudo systemctl start wg-quick@$VPN_INTERFACE

    # Ask for the ports to route through the VPN (defaults to Storj 32000, 32001)
    echo "Enter the ports you want to route through the VPN (default: 32000 32001):"
    read PORTS
    PORTS=${PORTS:-"32000 32001"}

    # Set up routing rules to ensure only selected traffic goes through the VPN
    echo "Configuring routing rules..."

    # Add a custom routing rule for VPN traffic
    sudo ip rule add from $VPN_IP_HOME table $TABLE_ID
    sudo ip route add default via $VPN_IP_VPS table $TABLE_ID

    # Use iptables to mark packets going to the selected ports
    for PORT in $PORTS; do
        sudo iptables -t mangle -A OUTPUT -p tcp --dport $PORT -j MARK --set-mark 2
        sudo iptables -t mangle -A OUTPUT -p udp --dport $PORT -j MARK --set-mark 2
    done

    # Apply the marked packets to our custom routing table
    sudo ip rule add fwmark 2 table $TABLE_ID

    # Make the configuration persistent across reboots
    echo "Saving configuration to persist after reboot..."

    # Add custom routing table if it doesn't already exist
    if ! grep -q "200 storjvpn" /etc/iproute2/rt_tables; then
        echo "200 storjvpn" | sudo tee -a /etc/iproute2/rt_tables > /dev/null
    fi

    # Ensure that the routing rules are applied at boot
    sudo tee -a /etc/network/interfaces > /dev/null <<EOF

# Custom routing rules for Storj VPN
post-up ip rule add from $VPN_IP_HOME table $TABLE_ID
post-up ip route add default via $VPN_IP_VPS table $TABLE_ID
EOF

    # Save iptables rules persistently
    sudo iptables-save | sudo tee /etc/iptables/rules.v4 > /dev/null

    echo "Setup complete! The following ports ($PORTS) are now routed through the VPS VPN."

    exit 0
fi
