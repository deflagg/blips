#!/usr/bin/env bash

set -euo pipefail

echo "Updating apt..."
sudo apt update -y

echo "Installing dnsmasq..."
sudo apt install -y dnsmasq

echo "Purging resolvconf so it doesn't conflict with dnsmasq..."
sudo apt purge -y resolvconf

echo "Purging systemd-resolved so it doesn't conflict with dnsmasq..."
sudo apt purge -y systemd-resolved

echo "Configuring dnsmasq to forward DNS requests..."
sudo tee -a /etc/dnsmasq.conf >/dev/null <<'CONF'
no-resolv
server=168.63.129.16
interface=eth0
CONF

echo "Updating resolv.conf to use dnsmasq..."
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf

echo "Updating /etc/hosts to include dnsforwarder..."
sudo sed -i 's/127\.0\.0\.1 localhost/127.0.0.1 localhost dnsforwarder/' /etc/hosts

echo "Enabling & starting dnsmasq..."
sudo systemctl enable --now dnsmasq
