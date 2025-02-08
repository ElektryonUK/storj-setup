#WireGuard VPN Setup for Storj Nodes
This guide explains how to automatically set up WireGuard on both:

VPN Server (VPS)
Storj Node Clients
The script automates installation, configuration, and routing but requires a manual step to finalize the setup.

##1. Installation
Run this script on both the VPN server and each Storj Node.

###Download the script
```
wget https://your-repo-url.com/wireguard-setup.sh
chmod +x wireguard-setup.sh
```

###Run the script
```
./wireguard-setup.sh
```

###Choose Setup Type
VPN-VPS: Select "server"
Storj Node: Select "client"

##2. Manual Step (Required)
After setting up a Storj Node (client), you must manually add its public key to the VPN server.

###On the Storj Node, copy the public key
```
cat /etc/wireguard/publickey
```
Example output:
```
abcdefg1234567890xyz=
```

###On the VPN Server, edit /etc/wireguard/wg0.conf
```
sudo nano /etc/wireguard/wg0.conf
```

###Add the client’s public key to the [Peer] section
CHANGEMEini
[Peer]
PublicKey = abcdefg1234567890xyz=
AllowedIPs = 10.0.0.2/32
```
(Replace abcdefg1234567890xyz= with the actual key.)

###Restart WireGuard on the VPN Server
```
sudo systemctl restart wg-quick@wg0
```

##3. Verify VPN is Working
Check VPN Status
```
wg show
```

Check if the Storj Node is using the VPN
```
curl -s ifconfig.me
```
If it returns VPN Server IP, everything is working!