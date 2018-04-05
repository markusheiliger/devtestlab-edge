#!/bin/bash

PARAM_STORAGE_ACCOUNT=${1}
PARAM_STORAGE_KEY=${2}

GW_LOCATION=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/location?api-version=2017-08-01&format=text")
GW_VMNAME=$(curl -s -H Metadata:true "http://169.254.169.254/metadata/instance/compute/name?api-version=2017-08-01&format=text")
GW_CNNAME="$GW_VMNAME.$GW_LOCATION.cloudapp.azure.com"
GW_LOCALIP=$(hostname --ip-address)
GW_NETMASK=$(ifconfig eth0 | awk -F: '/Mask:/{print $4}')
GW_GATEWAY=$(ip route | awk '/default/ { print $3 }')

# Register Azure CLI apt-get repo
AZ_REPO=$(lsb_release -cs)
echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" | sudo tee /etc/apt/sources.list.d/azure-cli.list
sudo apt-key adv --keyserver packages.microsoft.com --recv-keys 52E16F86FEE04B979B07E28DB02C46DF417A0893

# Updating server packages
sudo apt-get update && sudo apt-get upgrade -y

# Installing OpenVPN packages
sudo apt-get install -y bridge-utils openvpn libssl-dev openssl apt-transport-https azure-cli

# Installing Bridge device
sudo sed -i.backup "s/^\([^#]\)/#\1/g" "/etc/network/interfaces"
sudo tee -a /etc/network/interfaces << END

# ############################################
# OpenVPN Bridge Configuration
# ############################################

auto lo br0
iface lo inet loopback

iface br0 inet static
  address $GW_LOCALIP
  netmask $GW_NETMASK
  gateway $GW_GATEWAY
  bridge_ports eth0

iface eth0 inet manual
  up ip link set \$IFACE up promisc on
  down ip link set \$IFACE down promisc off
  bridge_fd 9      ## from the libvirt docs (forward delay time)
  bridge_hello 2   ## from the libvirt docs (hello time)
  bridge_maxage 12 ## from the libvirt docs (maximum message age)
  bridge_stp off   ## from the libvirt docs (spanning tree protocol)
END

# Enable IP forwarding
sudo sed -i.bak s/\#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g /etc/sysctl.conf

# Activate IP forwarding
sudo /etc/init.d/procps restart

# Restart Networking
sudo /etc/init.d/networking restart

# Install easy-rsa packages
sudo apt-get install -y easy-rsa
sudo mkdir /etc/openvpn/easy-rsa/
sudo cp -r /usr/share/easy-rsa/* /etc/openvpn/easy-rsa/
sudo make-cadir /etc/openvpn/easy-rsa

# Initialize RSA vars
sudo tee -a /etc/openvpn/easy-rsa/vars << END

# ###############################
# custom overrides
# ###############################

export KEY_COUNTRY="US"
export KEY_PROVINCE="WA"
export KEY_CITY="Redmond"
export KEY_ORG="Azure"
export KEY_EMAIL="unknown@azure.com"
# export KEY_CN=$GW_VMNAME
# export KEY_NAME=$GW_VMNAME
# export KEY_ALTNAMES="DNS:$GW_CNNAME"
# export KEY_OU=DTL
END

# Create server keys configuration script
sudo tee /etc/openvpn/easy-rsa/create_server_keys.sh << END
LOG="\$(pwd)/create_server_keys.log"
rm -f $LOG
source ./vars
./clean-all
./build-dh 2>&1 | tee -a \$LOG
./pkitool --initca 2>&1 | tee -a \$LOG
./pkitool --server server 2>&1 | tee -a \$LOG
END

# Generate server keys
cd /etc/openvpn/easy-rsa
sudo bash create_server_keys.sh
cd /etc/openvpn/easy-rsa/keys
sudo openvpn --genkey --secret ta.key
sudo cp -rf server.crt server.key ca.crt dh2048.pem ta.key ../../

# Create client keys configuration script
sudo tee /etc/openvpn/easy-rsa/create_client_keys.sh << END
LOG="\$(pwd)/create_client_keys.log"
rm -f $LOG
source ./vars

## Note: if you get a 'TXT_DB error number 2' error you may need to specify
## a unique KEY_CN, for example: KEY_CN=client ./pkitool client
KEY_CN=client 

./pkitool client 2>&1 | tee -a \$LOG
END

# Generate client keys
cd /etc/openvpn/easy-rsa
sudo bash create_client_keys.sh

# Create client OpenVPN config file
sudo tee /etc/openvpn/easy-rsa/keys/client.ovpn << END
### Client configuration file for OpenVPN

# Specify that this is a client
client

# Bridge device setting
dev tap

# Host name and port for the server (default port is 1194)
# note: replace with the correct values your server set up
remote $GW_CNNAME 1194

# Client does not need to bind to a specific local port
nobind

# Keep trying to resolve the host name of OpenVPN server.
## The windows GUI seems to dislike the following rule. 
##You may need to comment it out.
resolv-retry infinite

# Preserve state across restarts
persist-key
persist-tun

# SSL/TLS parameters - files created previously
ca ca.crt
cert client.crt
key client.key

# Since we specified the tls-auth for server, we need it for the client
# note: 0 = server, 1 = client
tls-auth ta.key 1

# Specify same cipher as server
cipher BF-CBC

# Use compression
# comp-lzo

# Log verbosity (to help if there are problems)
verb 3
END

# Upload client config to storage account
CONTAINER_NAME="client"
sudo az storage container create --account-name $PARAM_STORAGE_ACCOUNT --account-key $PARAM_STORAGE_KEY --name $CONTAINER_NAME
sudo az storage blob upload --account-name $PARAM_STORAGE_ACCOUNT --account-key $PARAM_STORAGE_KEY --container-name $CONTAINER_NAME --file /etc/openvpn/easy-rsa/keys/client.ovpn --name client.ovpn
sudo az storage blob upload --account-name $PARAM_STORAGE_ACCOUNT --account-key $PARAM_STORAGE_KEY --container-name $CONTAINER_NAME --file /etc/openvpn/easy-rsa/keys/ca.crt --name ca.crt
sudo az storage blob upload --account-name $PARAM_STORAGE_ACCOUNT --account-key $PARAM_STORAGE_KEY --container-name $CONTAINER_NAME --file /etc/openvpn/easy-rsa/keys/client.crt --name client.crt
sudo az storage blob upload --account-name $PARAM_STORAGE_ACCOUNT --account-key $PARAM_STORAGE_KEY --container-name $CONTAINER_NAME --file /etc/openvpn/easy-rsa/keys/client.key --name client.key
sudo az storage blob upload --account-name $PARAM_STORAGE_ACCOUNT --account-key $PARAM_STORAGE_KEY --container-name $CONTAINER_NAME --file /etc/openvpn/easy-rsa/keys/ta.key --name ta.key

# Create server UP script
sudo tee /etc/openvpn/up.sh << END
#!/bin/sh
BR=\$1
DEV=\$2
MTU=\$3
/sbin/ip link set "\$DEV" up promisc on mtu "\$MTU"
/sbin/brctl addif \$BR \$DEV
END
sudo chmod +x /etc/openvpn/up.sh

# Create server DOWN script
sudo tee /etc/openvpn/down.sh << END
#!/bin/sh
BR=\$1
DEV=\$2
/sbin/brctl delif \$BR \$DEV
/sbin/ip link set "\$DEV" down
END
sudo chmod +x /etc/openvpn/down.sh

# Create OpenVPN server configuration
sudo tee /etc/openvpn/server.conf << END
mode server
tls-server

local $GW_LOCALIP ## ip/hostname of server
port 1194 ## default openvpn port
proto tcp ## udp

#bridging directive
dev tap0 ## If you need multiple tap devices, add them here
script-security 2 ## allow calling up.sh and down.sh
up "/etc/openvpn/up.sh br0 tap0 1500"
down "/etc/openvpn/down.sh br0 tap0"

persist-key
persist-tun

#certificates and encryption
ca ca.crt
cert server.crt
key server.key  # This file should be kept secret
dh dh2048.pem
tls-auth ta.key 0 # This file is secret

cipher BF-CBC        # Blowfish (default)
## comp-lzo

#DHCP Information
ifconfig-pool-persist ipp.txt
server-bridge 192.168.1.10 255.255.255.0 192.168.1.100 192.168.1.110
push "dhcp-option DNS your.dns.ip.here"
push "dhcp-option DOMAIN yourdomain.com"
max-clients 10 ## set this to the max number of clients that should be connected at a time

#log and security
user nobody
group nogroup
keepalive 10 120
status openvpn-status.log
verb 3
END

# Configure SystemCtl for OpenVPN
sudo systemctl start openvpn@server
sudo systemctl enable openvpn@server