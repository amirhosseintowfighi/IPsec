#!/bin/bash
# =============================================
# StrongSwan IKEv2 Site-to-Site Tunnel Manager
# =============================================

CONFIG_DIR="/etc/ipsec_tunnels"
LOG_DIR="/var/log/ipsec_tunnels"
mkdir -p "$CONFIG_DIR"
mkdir -p "$LOG_DIR"

# =============================
# تابع نصب و پیش‌نیازها
# =============================
install_dependencies() {
    echo "[*] Installing required packages..."
    sudo apt update
    sudo apt install -y strongswan strongswan-pki socat ufw iptables-persistent nano
    sudo sysctl -w net.ipv4.ip_forward=1
}

# =============================
# تابع ایجاد تونل جدید
# =============================
create_tunnel() {
    read -p "Tunnel name: " TUNNEL_NAME
    read -p "Local Public IP: " LOCAL_IP
    read -p "Local Subnet (e.g., 10.10.10.0/24): " LOCAL_SUBNET
    read -p "Remote Public IP: " REMOTE_IP
    read -p "Remote Subnet (e.g., 10.20.20.0/24): " REMOTE_SUBNET
    read -s -p "PSK: " PSK
    echo
    read -p "Number of port forwards: " PORT_COUNT

    PORTS=()
    for ((i=1;i<=PORT_COUNT;i++)); do
        read -p "Port mapping #$i (Local:Remote:proto e.g., 8080:80/tcp): " PM
        PORTS+=("$PM")
    done

    # ایجاد دایرکتوری تونل
    mkdir -p "$CONFIG_DIR/$TUNNEL_NAME"

    # =============================
    # ساخت ipsec.conf و ipsec.secrets
    # =============================
    cat > "$CONFIG_DIR/$TUNNEL_NAME/ipsec.conf" <<EOF
config setup
    uniqueids=no
    charondebug="ike 2, knl 2, cfg 2"

conn $TUNNEL_NAME
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

    cat > "$CONFIG_DIR/$TUNNEL_NAME/ipsec.secrets" <<EOF
$LOCAL_IP $REMOTE_IP : PSK "$PSK"
EOF

    chmod 600 "$CONFIG_DIR/$TUNNEL_NAME/ipsec.secrets"
    chown root:root "$CONFIG_DIR/$TUNNEL_NAME/ipsec.secrets"

    # =============================
    # اعمال NAT و IP forwarding
    # =============================
    sudo iptables -t nat -A POSTROUTING -s $LOCAL_SUBNET -d $REMOTE_SUBNET -j MASQUERADE
    sudo netfilter-persistent save

    # =============================
    # اعمال port forward ها
    # =============================
    for PM in "${PORTS[@]}"; do
        IFS=':/' read -r LPORT RPORT PROTO <<< "$PM"
        if [[ "$PROTO" == "tcp" ]]; then
            sudo nohup socat TCP-LISTEN:$LPORT,fork TCP:$REMOTE_SUBNET:$RPORT >/dev/null 2>&1 &
        else
            sudo nohup socat UDP-LISTEN:$LPORT,fork UDP:$REMOTE_SUBNET:$RPORT >/dev/null 2>&1 &
        fi
    done

    echo "[*] Tunnel $TUNNEL_NAME created!"
}

# =============================
# مدیریت تونل ها
# =============================
tunnel_menu() {
    echo "Select tunnel:"
    TUNNELS=($(ls "$CONFIG_DIR"))
    for i in "${!TUNNELS[@]}"; do
        echo "$((i+1))) ${TUNNELS[$i]}"
    done
    read -p "Choice: " CHOICE
    TUNNEL="${TUNNELS[$((CHOICE-1))]}"
    if [[ -z "$TUNNEL" ]]; then
        echo "Invalid choice"
        return
    fi

    echo "1) Start"
    echo "2) Stop"
    echo "3) Restart"
    echo "4) Status"
    echo "5) View logs"
    echo "6) Edit config"
    read -p "Action: " ACTION

    case $ACTION in
        1) sudo ipsec start; sudo ipsec restart; echo "[*] Starting $TUNNEL..." ;;
        2) sudo ipsec stop; echo "[*] Stopping $TUNNEL..." ;;
        3) sudo ipsec restart; echo "[*] Restarting $TUNNEL..." ;;
        4) ipsec statusall ;;
        5) sudo journalctl -u strongswan-starter -n 50 ;;
        6) sudo nano "$CONFIG_DIR/$TUNNEL/ipsec.conf" ;;
        *) echo "Invalid action" ;;
    esac
}

# =============================
# منوی اصلی
# =============================
while true; do
    echo "=============================="
    echo " StrongSwan Tunnel Manager CLI"
    echo "=============================="
    echo "1) Install prerequisites"
    echo "2) Create new tunnel"
    echo "3) Manage existing tunnels"
    echo "4) Exit"
    read -p "Choice: " MAIN_CHOICE

    case $MAIN_CHOICE in
        1) install_dependencies ;;
        2) create_tunnel ;;
        3) tunnel_menu ;;
        4) exit 0 ;;
        *) echo "Invalid choice" ;;
    esac
done
