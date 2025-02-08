#!/bin/bash

# Ensure the script is run as a non-root user with sudo
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a non-root user with sudo."
    exit 1
fi

echo "🚀 WireGuard Auto-Installer for Storj VPN"

# Detect if the system is VPN-VPS or StorjNode based on user input
read -p "Are you setting up the VPN-VPS (server) or a Storj Node (client)? Type 'server' or 'client': " NODE_TYPE

# Install WireGuard
echo "🔄 Installing WireGuard..."
sudo apt update && sudo apt install -y wireguard

# Generate keys
echo "🔑 Generating WireGuard keys..."
PRIVATE_KEY=$(wg genkey)
PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

if [ "$NODE_TYPE" == "server" ]; then
    echo "🖥 Setting up WireGuard VPN Server..."

    # Ask for VPN subnet details
    read -p "Enter the VPN network range (default: 10.0.0.0/24): " VPN_SUBNET
    VPN_SUBNET=${VPN_SUBNET:-10.0.0.0/24}

    read -p "Enter the VPN IP for this server (default: 10.0.0.1): " VPN_IP
    VPN_IP=${VPN_IP:-10.0.0.1}

    # Create WireGuard config for the server
    sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $VPN_IP/24
ListenPort = 51820
SaveConfig = true
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

EOF

    echo "✅ WireGuard Server configuration completed!"
    echo "Server Public Key: $PUBLIC_KEY"
    echo "Save this to use in client configuration."

elif [ "$NODE_TYPE" == "client" ]; then
    echo "🖥 Setting up WireGuard Client (Storj Node)..."

    # Ask for details
    read -p "Enter VPN Server Public Key: " SERVER_PUBLIC_KEY
    read -p "Enter VPN Server IP (e.g., 8.208.45.156): " VPN_SERVER_IP
    read -p "Enter Client VPN IP (default: 10.0.0.2): " CLIENT_VPN_IP
    CLIENT_VPN_IP=${CLIENT_VPN_IP:-10.0.0.2}

    # Get default gateway
    GATEWAY_IP=$(ip route | grep default | awk '{print $3}')

    # Create WireGuard config for the client
    sudo tee /etc/wireguard/wg0.conf > /dev/null <<EOF
[Interface]
PrivateKey = $PRIVATE_KEY
Address = $CLIENT_VPN_IP/24
DNS = 8.8.8.8
PostUp = ip rule add from $(hostname -I | awk '{print $1}') table 200
PostUp = ip route add default via 10.0.0.1 dev wg0 table 200
PostUp = ip route add $(hostname -I | awk '{print $1}')/24 via $GATEWAY_IP dev eth0
PostDown = ip rule delete from $(hostname -I | awk '{print $1}') table 200
PostDown = ip route delete default via 10.0.0.1 dev wg0 table 200
PostDown = ip route delete $(hostname -I | awk '{print $1}')/24 via $GATEWAY_IP dev eth0

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $VPN_SERVER_IP:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

    echo "✅ WireGuard Client configuration completed!"
    echo "Client Public Key: $PUBLIC_KEY"
    echo "Add this public key to the VPN server configuration."

else
    echo "❌ Invalid input. Please run the script again and enter 'server' or 'client'."
    exit 1
fi

# Set permissions
sudo chmod 600 /etc/wireguard/wg0.conf

# Enable WireGuard
echo "🔄 Enabling WireGuard..."
sudo systemctl enable wg-quick@wg0
sudo systemctl restart wg-quick@wg0

# Verify setup
echo "✅ WireGuard setup completed!"
sudo systemctl status wg-quick@wg0
wg show
