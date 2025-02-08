#!/bin/bash

# WireGuard configuration
VPN_INTERFACE="wg0"
VPN_IP_HOME="10.0.0.2"
VPN_IP_VPS="10.0.0.1"
TABLE_ID=200
VPN_PORT=51820

echo "This script will set up a WireGuard VPN and route only selected ports through it."

# Ask if this is the VPS or the Home Server
echo "Are you running this on the VPS or Home Server? (Enter 'vps' or 'home')"
read SERVER_TYPE

if [[ "$SERVER_TYPE" != "vps" && "$SERVER_TYPE" != "home" ]]; then
    echo "Invalid input. Please enter 'vps' or 'home'."
    exit 1
fi

# Install WireGuard
echo "Installing WireGuard..."
sudo apt update && sudo apt install -y wireguard iptables-persistent

# Generate WireGuard Keys
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

if [[ "$SERVER_TYPE" == "vps" ]]; then
    echo "Setting up WireGuard on the VPS..."

    # Save Private Key
    echo "$PRIVATE_KEY" > /etc/wireguard/privatekey
    chmod 600 /etc/wireguard/privatekey

    # Create WireGuard Config
    cat > /etc/wireguard/$VPN_INTERFACE.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $VPN_IP_VPS/24
ListenPort = $VPN_PORT
PostUp = iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <HOME_SERVER_PUBLIC_KEY>
AllowedIPs = $VPN_IP_HOME/32
PersistentKeepalive = 25
EOF

    echo "WireGuard configuration completed. Share the following public key with your home server:"
    echo "VPS Public Key: $PUBLIC_KEY"

    sudo systemctl enable wg-quick@$VPN_INTERFACE
    sudo systemctl start wg-quick@$VPN_INTERFACE

    exit 0
fi

if [[ "$SERVER_TYPE" == "home" ]]; then
    echo "Setting up WireGuard on the Home Server..."

    # Ask for VPS public key
    echo "Enter the public key from the VPS:"
    read VPS_PUBLIC_KEY

    # Ask for VPS IP
    echo "Enter the VPS public IP:"
    read VPS_IP

    # Save Private Key
    echo "$PRIVATE_KEY" > /etc/wireguard/privatekey
    chmod 600 /etc/wireguard/privatekey

    # Create WireGuard Config
    cat > /etc/wireguard/$VPN_INTERFACE.conf <<EOF
[Interface]
PrivateKey = $(cat /etc/wireguard/privatekey)
Address = $VPN_IP_HOME/24

[Peer]
PublicKey = $VPS_PUBLIC_KEY
Endpoint = $VPS_IP:$VPN_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    sudo systemctl enable wg-quick@$VPN_INTERFACE
    sudo systemctl start wg-quick@$VPN_INTERFACE

    # Ask for the ports to route
    echo "Enter the ports you want to route through the VPN (separated by spaces, e.g., '28967 7777'):"
    read PORTS

    # Set up routing rules
    echo "Setting up routing rules..."
    ip rule add from $VPN_IP_HOME table $TABLE_ID
    ip route add default via $VPN_IP_VPS table $TABLE_ID

    # Apply iptables rules for selected ports
    for PORT in $PORTS; do
        iptables -t mangle -A OUTPUT -p tcp --dport $PORT -j MARK --set-mark 2
        iptables -t mangle -A OUTPUT -p udp --dport $PORT -j MARK --set-mark 2
    done

    ip rule add fwmark 2 table $TABLE_ID

    # Make settings persistent
    echo "Making settings persistent..."

    echo "200 storjvpn" >> /etc/iproute2/rt_tables

    cat >> /etc/network/interfaces <<EOF

# Storj VPN Routing
post-up ip rule add from $VPN_IP_HOME table $TABLE_ID
post-up ip route add default via $VPN_IP_VPS table $TABLE_ID
EOF

    sudo iptables-save > /etc/iptables/rules.v4

    echo "Setup complete! Your Storj traffic on ports ($PORTS) will now be routed through the VPS."

    exit 0
fi
