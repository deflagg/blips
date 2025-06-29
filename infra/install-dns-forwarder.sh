#!/usr/bin/env bash
# install-dns-forwarder.sh  (no ssh commands here!)

set -euo pipefail

echo "Updating apt..."
sudo apt update -y

echo "Installing dnsmasq..."
sudo apt install -y dnsmasq

echo "Purging resolvconf..."
sudo apt purge -y resolvconf

echo "Configuring dnsmasq..."
sudo tee /etc/dnsmasq.conf >/dev/null <<'CONF'
no-resolv
server=168.63.129.16
interface=eth0
CONF

echo "Updating resolv.conf..."
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf
sudo sed -i 's/127\.0\.0\.1 localhost/127.0.0.1 localhost dnsforwarder/' /etc/hosts

echo "Enabling & starting dnsmasq..."
sudo systemctl enable --now dnsmasq


#sudo chattr +i /etc/resolv.conf
#sudo chattr -i /etc/resolv.conf

# enable system to resolve its own hostname


# update dnsmasq config to forward to Azure DNS 168.63.129.16
#sudo systemctl restart dnsmasq


# options edns0 trust-ad

# sudo apt purge resolvconf


# listen-address=127.0.0.1,172.16.201.2