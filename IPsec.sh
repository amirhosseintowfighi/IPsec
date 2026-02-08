#!/bin/bash
# ============================================
# Complete StrongSwan + NAT + Port Forward Setup
# ============================================

# دریافت اطلاعات کاربر
read -p "Local Public IP: " LOCAL_IP
read -p "Local Subnet (e.g., 10.10.10.0/24): " LOCAL_SUBNET
read -p "Remote Public IP: " REMOTE_IP
read -p "Remote Subnet (e.g., 10.20.20.0/24): " REMOTE_SUBNET
read -s -p "Pre-shared Key (PSK): " PSK
echo
read -p "Port to forward from Local to Remote (TCP/UDP e.g., 8080:80/tcp): " PORT_MAP

# پکیج‌های مورد نیاز
echo "[*] Installing required packages..."
sudo apt update
sudo apt install -y strongswan strongswan-pki socat ufw iptables-persistent

# =============================
# تنظیم StrongSwan
# =============================
echo "[*] Configuring StrongSwan..."
sudo bash -c "cat > /etc/ipsec.conf" <<EOF
config setup
    uniqueids=no
    charondebug="ike 2, knl 2, cfg 2"

conn iran-eu
    auto=start
    keyexchange=ikev2
    type=tunnel

    left=$LOCAL_IP
    leftid=$LOCAL_IP
    leftsubnet=$LOCAL_SUBNET
    leftauth=psk

    right=$REMOTE_IP
    rightid=$REMOTE_IP
    rightsubnet=$REMOTE_SUBNET
    rightauth=psk

    ike=aes256gcm16-prfsha384-ecp384!
    esp=aes256gcm16-ecp384!

    dpdaction=restart
    dpddelay=30s
    rekey=no
EOF

sudo bash -c "cat > /etc/ipsec.secrets" <<EOF
$LOCAL_IP $REMOTE_IP : PSK "$PSK"
EOF

sudo chmod 600 /etc/ipsec.secrets
sudo chown root:root /etc/ipsec.secrets

# =============================
# فعال سازی IP forwarding و NAT
# =============================
echo "[*] Enabling IP forwarding and NAT..."
sudo sysctl -w net.ipv4.ip_forward=1
# NAT برای عبور ترافیک subnet ها از تونل
sudo iptables -t nat -A POSTROUTING -s $LOCAL_SUBNET -d $REMOTE_SUBNET -j MASQUERADE
# ذخیره iptables برای reboot
sudo netfilter-persistent save

# =============================
# فایروال UFW
# =============================
echo "[*] Configuring firewall..."
sudo ufw allow 500/udp
sudo ufw allow 4500/udp

IFS=':/' read -r LOCAL_PORT REMOTE_PORT PROTO <<< "$PORT_MAP"
sudo ufw allow $LOCAL_PORT/$PROTO
sudo ufw reload

# =============================
# Restart StrongSwan
# =============================
echo "[*] Restarting StrongSwan..."
sudo ipsec stop
sudo ipsec start
sleep 2
ipsec statusall

# =============================
# Port forwarding با socat
# =============================
echo "[*] Setting up port forwarding..."
echo "Local Port: $LOCAL_PORT, Remote IP: $REMOTE_SUBNET, Remote Port: $REMOTE_PORT, Protocol: $PROTO"

# حذف forwarding قدیمی اگر موجود بود
sudo pkill -f "socat TCP-LISTEN:$LOCAL_PORT"
sudo pkill -f "socat UDP-LISTEN:$LOCAL_PORT"

# اجرا socat در background
if [[ "$PROTO" == "tcp" ]]; then
    sudo nohup socat TCP-LISTEN:$LOCAL_PORT,fork TCP:$REMOTE_SUBNET:$REMOTE_PORT >/dev/null 2>&1 &
else
    sudo nohup socat UDP-LISTEN:$LOCAL_PORT,fork UDP:$REMOTE_SUBNET:$REMOTE_PORT >/dev/null 2>&1 &
fi

echo "[*] Port forwarding is running!"
echo "============================"
echo "StrongSwan tunnel status:"
ipsec statusall
echo "Port $LOCAL_PORT forwarded to $REMOTE_SUBNET:$REMOTE_PORT ($PROTO)"
