#!/bin/bash

# Ensure the script is run as a non-root user with sudo
if [ "$EUID" -eq 0 ]; then
    echo "Please run this script as a non-root user with sudo."
    exit 1
fi

echo "🚀 Cloudflare DDNS Installer for Storj Servers"

# Ask for user input
read -p "Enter your Cloudflare email: " CF_EMAIL
read -p "Enter your Cloudflare API Token (Zone DNS Edit access): " CF_API_TOKEN
read -p "Enter your Cloudflare domain (e.g., yourdomain.com): " CF_DOMAIN
read -p "Enter the subdomain for this server (e.g., node1, storjnode): " CF_SUBDOMAIN

# Ensure necessary tools are installed
echo "🔄 Updating system and installing ddclient..."
sudo apt update && sudo apt install -y ddclient

# Configure ddclient
echo "🛠 Creating Cloudflare DDNS config..."

sudo tee /etc/ddclient.conf > /dev/null <<EOF
# Cloudflare DynDNS Configuration
daemon=300
ssl=yes
use=web, web=checkip.dyndns.com/, web-skip='Current IP Address: '
server=api.cloudflare.com
protocol=cloudflare
login=${CF_EMAIL}
password=${CF_API_TOKEN}
zone=${CF_DOMAIN}
ttl=120
${CF_SUBDOMAIN}.${CF_DOMAIN}
EOF

# Ensure proper permissions
sudo chmod 600 /etc/ddclient.conf

# Enable and start ddclient
echo "🔄 Restarting ddclient..."
sudo systemctl enable ddclient
sudo systemctl restart ddclient

# Test if Cloudflare DDNS is working
echo "✅ Testing DDNS update..."
sudo ddclient -verbose -force

echo "🎉 Cloudflare DDNS setup complete!"
echo "🌍 Your Storj node will now always resolve to: ${CF_SUBDOMAIN}.${CF_DOMAIN}"
