#!/usr/bin/env bash
# ==============================================================================
# SHVL: Automated Next-Generation Tunneling Stack Installer
# Engineered for Ubuntu 24.04 LTS & Debian 13 (Systemd, Glibc)
# 100% Static Binaries - Zero Compilation on Target VPS
# Includes: SSH, WS, TLS, VLESS (WS/HU/XHTTP), OpenVPN TCP, Squid HTTP Proxy
# ==============================================================================

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

DEFAULT_REPO="mann-bott/shvl"
DEFAULT_BRANCH="main"

print_header() {
    clear 2>/dev/null || true
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e " ${BOLD}${PURPLE}             SHVL TUNNEL SYSTEM - AUTO INSTALLER            ${NC}"
    echo -e " ${BOLD}${CYAN}          Optimized for Ubuntu 24.04 LTS & Debian 13        ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_ok()   { echo -e " ${GREEN}[OK]${NC} $1"; }
print_info() { echo -e " ${CYAN}[INFO]${NC} $1"; }
print_warn() { echo -e " ${YELLOW}[WARN]${NC} $1"; }
print_err()  { echo -e " ${RED}[ERR]${NC} $1"; }

# 1. Root Check
if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    print_err "Script ini harus dijalankan sebagai root!"
    exit 1
fi

# 2. OS Compatibility Check
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="$ID"
    OS_VER="$VERSION_ID"
else
    print_err "File /etc/os-release tidak ditemukan. Hanya Ubuntu dan Debian yang didukung."
    exit 1
fi

if [[ "$OS_ID" != "ubuntu" && "$OS_ID" != "debian" ]]; then
    print_warn "Distribusi '$OS_ID' terdeteksi. Script dioptimalkan untuk Ubuntu 24.04 dan Debian 13."
fi

# 3. Detect Source Directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
PROJECT_DIR=""

is_valid_dir() {
    local d="$1"
    [ -n "$d" ] && [ -d "$d" ] && [ -f "$d/conf/haproxy.cfg" ] && [ -f "$d/install.sh" ]
}

if is_valid_dir "$SCRIPT_DIR"; then
    PROJECT_DIR="$SCRIPT_DIR"
elif is_valid_dir "$(pwd)"; then
    PROJECT_DIR="$(pwd)"
elif is_valid_dir "/root/shvl"; then
    PROJECT_DIR="/root/shvl"
elif is_valid_dir "$HOME/shvl"; then
    PROJECT_DIR="$HOME/shvl"
fi

# Parse CLI Flags
PARAM_DOMAIN=""
FORCE_LOCAL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --local)
            FORCE_LOCAL=1
            shift
            ;;
        --domain)
            PARAM_DOMAIN="$2"
            shift 2
            ;;
        *)
            shift
            ;;
    esac
done

print_header

# If local source not found, download package from GitHub
if [ -z "$PROJECT_DIR" ] && [ "$FORCE_LOCAL" -eq 0 ]; then
    print_info "Mengunduh paket instalasi SHVL dari https://github.com/${DEFAULT_REPO}..."
    mkdir -p /root/shvl
    local_archive="/tmp/shvl.tar.gz"
    rm -f "$local_archive"
    download_ok=0

    if curl -fsSL -o "$local_archive" "https://github.com/${DEFAULT_REPO}/archive/refs/heads/${DEFAULT_BRANCH}.tar.gz" 2>/dev/null; then
        download_ok=1
    elif wget -qO "$local_archive" "https://github.com/${DEFAULT_REPO}/archive/refs/heads/${DEFAULT_BRANCH}.tar.gz" 2>/dev/null; then
        download_ok=1
    fi

    if [ "$download_ok" -eq 1 ] && [ -s "$local_archive" ]; then
        tar -xzf "$local_archive" -C /root/shvl --strip-components=1 2>/dev/null || true
        rm -f "$local_archive"
        if is_valid_dir "/root/shvl"; then
            PROJECT_DIR="/root/shvl"
        fi
    fi

    # Fallback to git clone if tarball failed or files incomplete
    if ! is_valid_dir "$PROJECT_DIR"; then
        print_warn "Download arsip tar.gz tidak lengkap, mencoba fallback git clone..."
        if ! command -v git >/dev/null 2>&1; then
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y >/dev/null 2>&1 || true
            apt-get install -y git >/dev/null 2>&1 || true
        fi
        rm -rf /root/shvl
        if git clone --depth 1 "https://github.com/${DEFAULT_REPO}.git" /root/shvl 2>/dev/null; then
            if is_valid_dir "/root/shvl"; then
                PROJECT_DIR="/root/shvl"
            fi
        fi
    fi
fi

if ! is_valid_dir "$PROJECT_DIR"; then
    print_err "Direktori project SHVL tidak valid atau file konfigurasi tidak lengkap!"
    print_err "Pastikan repositori https://github.com/${DEFAULT_REPO} dapat diakses."
    exit 1
fi

print_ok "Direktori project terdeteksi: $PROJECT_DIR"

# 4. Input Domain
DOMAIN="$PARAM_DOMAIN"
if [ -z "$DOMAIN" ]; then
    if [ -f /etc/shvl/domain ]; then
        EXISTING_DOMAIN=$(head -n 1 /etc/shvl/domain | tr -d ' \r\n')
    fi
    echo ""
    echo -e "${BOLD}${YELLOW}Masukkan domain/subdomain yang telah di-pointing ke IP server ini:${NC}"
    
    # Read interactively if TTY is available (even when piped via curl | bash)
    if [ -t 0 ]; then
        if [ -n "$EXISTING_DOMAIN" ]; then
            read -r -p "Domain [$EXISTING_DOMAIN]: " INPUT_DOMAIN
            DOMAIN="${INPUT_DOMAIN:-$EXISTING_DOMAIN}"
        else
            read -r -p "Domain : " DOMAIN
        fi
    elif [ -e /dev/tty ]; then
        if [ -n "$EXISTING_DOMAIN" ]; then
            read -r -p "Domain [$EXISTING_DOMAIN]: " INPUT_DOMAIN </dev/tty 2>/dev/null || true
            DOMAIN="${INPUT_DOMAIN:-$EXISTING_DOMAIN}"
        else
            read -r -p "Domain : " DOMAIN </dev/tty 2>/dev/null || true
        fi
    fi
fi

DOMAIN=$(echo "$DOMAIN" | tr -d ' \r\n')

if [ -z "$DOMAIN" ]; then
    DOMAIN=$(curl -s --connect-timeout 2 ifconfig.me 2>/dev/null || curl -s --connect-timeout 2 icanhazip.com 2>/dev/null || echo "127.0.0.1")
    print_warn "Domain tidak diisi, menggunakan IP server: $DOMAIN"
fi

print_ok "Domain yang digunakan: $DOMAIN"

# 5. Runtime Dependencies (Includes OpenVPN, Squid, and Python3)
print_info "Memperbarui paket sistem & menginstal dependensi runtime..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y >/dev/null 2>&1 || true
apt-get install -y haproxy openvpn squid curl wget jq socat cron net-tools iptables zip unzip python3 psmisc >/dev/null 2>&1 || {
    print_warn "Percobaan pertama apt gagal, mencoba sekali lagi..."
    apt-get install -y haproxy openvpn squid curl wget jq socat cron net-tools iptables zip unzip python3 psmisc || true
}

# Stop conflicting default services if running
systemctl stop apache2 nginx haproxy 2>/dev/null || true
systemctl disable apache2 nginx 2>/dev/null || true

# 6. Create System Directories
mkdir -p /etc/shvl /etc/shvl/ssl /etc/shvl/ovpn /var/www/html /home/vps/public_html /etc/xray /var/log/xray /etc/dropbear /etc/haproxy /etc/squid /etc/openvpn /usr/local/bin /usr/sbin /usr/bin

# 7. Deploy Static Binaries (No Build Time!)
print_info "Memasang binary statis (Dropbear 2019, SSH-WS, Xray Core, SHVL Core)..."

BIN_SRC="$PROJECT_DIR/bin/amd64"
[ ! -d "$BIN_SRC" ] && BIN_SRC="$PROJECT_DIR/bin"

if [ ! -f "$BIN_SRC/xray" ]; then
    print_info "Mengunduh Xray Core binary dari official GitHub release..."
    mkdir -p /tmp/xray_dl "$BIN_SRC"
    curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip" -o /tmp/xray_dl/xray.zip 2>/dev/null || \
    wget -qO /tmp/xray_dl/xray.zip "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip" 2>/dev/null || true
    unzip -q -o /tmp/xray_dl/xray.zip -d "$BIN_SRC" 2>/dev/null || true
    rm -rf /tmp/xray_dl
fi

if [ -d "$BIN_SRC" ]; then
    cp -f "$BIN_SRC/dropbear" /usr/sbin/dropbear
    cp -f "$BIN_SRC/dropbearkey" /usr/bin/dropbearkey
    cp -f "$BIN_SRC/dropbearconvert" /usr/bin/dropbearconvert 2>/dev/null || true
    cp -f "$BIN_SRC/dbclient" /usr/bin/dbclient 2>/dev/null || true
    cp -f "$BIN_SRC/scp" /usr/bin/scp 2>/dev/null || true
    cp -f "$BIN_SRC/ssh-ws" /usr/local/bin/ssh-ws
    cp -f "$BIN_SRC/xray" /usr/local/bin/xray
    cp -f "$BIN_SRC/shvl" /usr/local/bin/shvl
    [ -f "$BIN_SRC/geoip.dat" ] && cp -f "$BIN_SRC/geoip.dat" /usr/local/bin/geoip.dat
    [ -f "$BIN_SRC/geosite.dat" ] && cp -f "$BIN_SRC/geosite.dat" /usr/local/bin/geosite.dat
    [ -f "$BIN_SRC/geoip.dat" ] && cp -f "$BIN_SRC/geoip.dat" /etc/xray/geoip.dat
    [ -f "$BIN_SRC/geosite.dat" ] && cp -f "$BIN_SRC/geosite.dat" /etc/xray/geosite.dat
fi

chmod +x /usr/sbin/dropbear /usr/bin/dropbearkey /usr/bin/dropbearconvert /usr/bin/dbclient /usr/bin/scp /usr/local/bin/ssh-ws /usr/local/bin/xray /usr/local/bin/shvl 2>/dev/null || true

# Verify binaries
if [ ! -x /usr/sbin/dropbear ] || [ ! -x /usr/local/bin/xray ] || [ ! -x /usr/local/bin/shvl ]; then
    print_err "Gagal menyalin binary statis! Pastikan folder bin/amd64/ tersedia."
    exit 1
fi
print_ok "Binary statis terverifikasi:"
print_ok "  • Dropbear : $(/usr/sbin/dropbear -V 2>&1 | head -n 1)"
print_ok "  • Xray Core: $(/usr/local/bin/xray version 2>&1 | head -n 1)"
print_ok "  • SHVL Core: $(/usr/local/bin/shvl version 2>&1 | head -n 1)"

# 8. Generate Dropbear Keys
if [ ! -f /etc/dropbear/dropbear_rsa_host_key ]; then
    /usr/bin/dropbearkey -t rsa -f /etc/dropbear/dropbear_rsa_host_key >/dev/null 2>&1 || true
fi
if [ ! -f /etc/dropbear/dropbear_dss_host_key ]; then
    /usr/bin/dropbearkey -t dss -f /etc/dropbear/dropbear_dss_host_key >/dev/null 2>&1 || true
fi
if [ ! -f /etc/dropbear/dropbear_ecdsa_host_key ]; then
    /usr/bin/dropbearkey -t ecdsa -f /etc/dropbear/dropbear_ecdsa_host_key >/dev/null 2>&1 || true
fi
if [ ! -f /etc/dropbear/dropbear_ed25519_host_key ]; then
    /usr/bin/dropbearkey -t ed25519 -f /etc/dropbear/dropbear_ed25519_host_key >/dev/null 2>&1 || true
fi

# 9. Deploy Configurations
print_info "Memasang konfigurasi sistem..."
mkdir -p /etc/shvl /etc/xray /etc/haproxy /etc/squid /etc/openvpn /etc/default
echo "$DOMAIN" > /etc/shvl/domain
echo "$DOMAIN" > /etc/xray/domain

[ -f "$PROJECT_DIR/conf/haproxy.cfg" ] && cp -f "$PROJECT_DIR/conf/haproxy.cfg" /etc/haproxy/haproxy.cfg
[ -f "$PROJECT_DIR/conf/xray.json" ] && cp -f "$PROJECT_DIR/conf/xray.json" /etc/xray/config.json
[ -f "$PROJECT_DIR/conf/dropbear.conf" ] && cp -f "$PROJECT_DIR/conf/dropbear.conf" /etc/default/dropbear
[ -f "$PROJECT_DIR/conf/squid.conf" ] && cp -f "$PROJECT_DIR/conf/squid.conf" /etc/squid/squid.conf
[ -f "$PROJECT_DIR/conf/issue.net" ] && cp -f "$PROJECT_DIR/conf/issue.net" /etc/shvl/issue.net
[ -f "$PROJECT_DIR/conf/shvl.conf" ] && cp -f "$PROJECT_DIR/conf/shvl.conf" /etc/shvl/shvl.conf
[ -f "$PROJECT_DIR/conf/openvpn-server.conf" ] && cp -f "$PROJECT_DIR/conf/openvpn-server.conf" /etc/openvpn/server.conf

if [ -f /etc/shvl/shvl.conf ]; then
    sed -i "s|^DOMAIN=.*|DOMAIN=\"$DOMAIN\"|" /etc/shvl/shvl.conf 2>/dev/null || true
fi

# Pre-deploy scripts so utilities like renew-cert are immediately available
cp -f "$PROJECT_DIR/scripts/"* /usr/local/bin/ 2>/dev/null || true
chmod +x /usr/local/bin/* 2>/dev/null || true

# 10. SSL Certificate Provisioning
print_info "Menerbitkan sertifikat SSL untuk domain $DOMAIN..."
/usr/local/bin/shvl cert issue || true

# If certificate bundle is still missing, generate self-signed fallback immediately
if [ ! -f /etc/shvl/shvl.pem ]; then
    mkdir -p /etc/shvl/ssl
    openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -days 365 -nodes -x509 \
        -subj "/CN=$DOMAIN" -keyout /etc/shvl/ssl/privkey.pem -out /etc/shvl/ssl/fullchain.pem >/dev/null 2>&1
    cat /etc/shvl/ssl/fullchain.pem /etc/shvl/ssl/privkey.pem > /etc/shvl/shvl.pem
    chmod 600 /etc/shvl/shvl.pem
fi

# 11. Configure OpenVPN Server (TCP 1194 & 443)
print_info "Mengonfigurasi OpenVPN Server (TCP 1194 & 443)..."
if [ ! -f /etc/openvpn/server.crt ]; then
    openssl req -new -x509 -days 3650 -nodes -subj "/CN=SHVL-CA" -keyout /etc/openvpn/ca.key -out /etc/openvpn/ca.crt >/dev/null 2>&1
    openssl req -new -nodes -subj "/CN=server" -keyout /etc/openvpn/server.key -out /etc/openvpn/server.csr >/dev/null 2>&1
    openssl x509 -req -days 3650 -in /etc/openvpn/server.csr -CA /etc/openvpn/ca.crt -CAkey /etc/openvpn/ca.key -CAcreateserial -out /etc/openvpn/server.crt >/dev/null 2>&1
fi

# Ensure PAM auth plugin exists
PAM_PLUGIN=$(find /usr/lib -name "openvpn-plugin-auth-pam.so" 2>/dev/null | head -n 1)
if [ -n "$PAM_PLUGIN" ]; then
    mkdir -p /usr/lib/openvpn
    ln -sf "$PAM_PLUGIN" /usr/lib/openvpn/openvpn-plugin-auth-pam.so 2>/dev/null || true
fi

[ -f "$PROJECT_DIR/conf/openvpn-server.conf" ] && cp -f "$PROJECT_DIR/conf/openvpn-server.conf" /etc/openvpn/server.conf

# Enable IP forwarding & NAT routing
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1 || true
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-openvpn.conf 2>/dev/null || true
NET_IFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
if [ -n "$NET_IFACE" ]; then
    iptables -t nat -C POSTROUTING -s 10.8.0.0/24 -o "$NET_IFACE" -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o "$NET_IFACE" -j MASQUERADE 2>/dev/null || true
fi

# Generate Client .ovpn files
cat > /etc/shvl/ovpn/client-tcp-1194.ovpn <<-EOF
client
dev tun
proto tcp
remote $DOMAIN 1194
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass
cipher AES-256-GCM
auth SHA256
verb 3
<ca>
$(cat /etc/openvpn/ca.crt 2>/dev/null)
</ca>
EOF

cat > /etc/shvl/ovpn/client-tcp-443.ovpn <<-EOF
client
dev tun
proto tcp
remote $DOMAIN 443
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass
cipher AES-256-GCM
auth SHA256
verb 3
<ca>
$(cat /etc/openvpn/ca.crt 2>/dev/null)
</ca>
EOF

cat > /etc/shvl/ovpn/client-tcp-ssl.ovpn <<-EOF
client
dev tun
proto tcp
remote 127.0.0.1 1194
route $DOMAIN 255.255.255.255 net_gateway
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass
cipher AES-256-GCM
auth SHA256
verb 3
<ca>
$(cat /etc/openvpn/ca.crt 2>/dev/null)
</ca>
EOF

cat > /etc/shvl/ovpn/client-tcp-ws.ovpn <<-EOF
client
dev tun
proto tcp
remote $DOMAIN 1194
http-proxy $DOMAIN 8080
resolv-retry infinite
nobind
persist-key
persist-tun
auth-user-pass
cipher AES-256-GCM
auth SHA256
verb 3
<ca>
$(cat /etc/openvpn/ca.crt 2>/dev/null)
</ca>
EOF

# Package OpenVPN client configs into all-in-one ZIP archive
print_info "Mengemas konfigurasi klien OpenVPN (.ovpn & .zip)..."
mkdir -p /etc/shvl/ovpn /var/www/html /home/vps/public_html
cd /etc/shvl/ovpn
zip -q -9 openvpn.zip *.ovpn 2>/dev/null || true
cp -f /etc/shvl/ovpn/*.ovpn /var/www/html/ 2>/dev/null || true
cp -f /etc/shvl/ovpn/*.zip /var/www/html/ 2>/dev/null || true
cp -f /etc/shvl/ovpn/*.ovpn /home/vps/public_html/ 2>/dev/null || true
cp -f /etc/shvl/ovpn/*.zip /home/vps/public_html/ 2>/dev/null || true
chmod 644 /etc/shvl/ovpn/* /var/www/html/* /home/vps/public_html/* 2>/dev/null || true
cd "$PROJECT_DIR"

# 12. Deploy Systemd Service Units
print_info "Memasang unit service systemd..."
cp -f "$PROJECT_DIR/systemd/dropbear.service" /etc/systemd/system/dropbear.service
cp -f "$PROJECT_DIR/systemd/ssh-ws.service" /etc/systemd/system/ssh-ws.service
cp -f "$PROJECT_DIR/systemd/xray.service" /etc/systemd/system/xray.service
cp -f "$PROJECT_DIR/systemd/openvpn.service" /etc/systemd/system/openvpn.service
cp -f "$PROJECT_DIR/systemd/shvl-limiter.service" /etc/systemd/system/shvl-limiter.service
cp -f "$PROJECT_DIR/systemd/shvl-xp.service" /etc/systemd/system/shvl-xp.service
cp -f "$PROJECT_DIR/systemd/shvl-xp.timer" /etc/systemd/system/shvl-xp.timer

systemctl daemon-reload
for svc in dropbear ssh-ws xray haproxy openvpn squid shvl-limiter; do
    systemctl enable "$svc.service" >/dev/null 2>&1 || true
    systemctl restart "$svc.service" >/dev/null 2>&1 || true
done
systemctl enable --now shvl-xp.timer >/dev/null 2>&1 || true

# 13. Deploy Interactive Menus & CLI Commands
print_info "Memasang menu TUI & command alias..."
cp -f "$PROJECT_DIR/menu/menu" /usr/local/bin/menu
cp -f "$PROJECT_DIR/menu/menu-ssh" /usr/local/bin/menu-ssh
cp -f "$PROJECT_DIR/menu/menu-vless" /usr/local/bin/menu-vless

cp -f "$PROJECT_DIR/scripts/"* /usr/local/bin/

ln -sf /usr/local/bin/menu /usr/bin/menu 2>/dev/null || true
ln -sf /usr/local/bin/menu-ssh /usr/bin/menu-ssh 2>/dev/null || true
ln -sf /usr/local/bin/menu-vless /usr/bin/menu-vless 2>/dev/null || true
ln -sf /usr/local/bin/renew-cert /usr/local/bin/cert 2>/dev/null || true
ln -sf /usr/local/bin/renew-cert /usr/local/bin/auto-certxray 2>/dev/null || true
ln -sf /usr/local/bin/renew-cert /usr/bin/renew-cert 2>/dev/null || true
ln -sf /usr/local/bin/renew-cert /usr/bin/cert 2>/dev/null || true
ln -sf /usr/local/bin/renew-cert /usr/bin/auto-certxray 2>/dev/null || true

chmod +x /usr/local/bin/* /usr/bin/menu /usr/bin/menu-ssh /usr/bin/menu-vless 2>/dev/null || true

# Add menu alias to profile files
for rc in /root/.bashrc /root/.profile /etc/bash.bashrc /etc/profile; do
    if [ -f "$rc" ] && ! grep -q "alias menu=" "$rc" 2>/dev/null; then
        echo "alias menu='/usr/local/bin/menu'" >> "$rc" 2>/dev/null || true
    fi
done

# Initialize Database
/usr/local/bin/shvl xp >/dev/null 2>&1 || true

# 14. Installation Summary
IP=$(curl -s --connect-timeout 2 ifconfig.me 2>/dev/null || echo "127.0.0.1")
clear
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e " ${BOLD}${GREEN}               INSTALASI SHVL BERHASIL SELESAI                  ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  ${WHITE}Domain Server${NC}     : ${GREEN}$DOMAIN${NC}"
echo -e "  ${WHITE}IP Address${NC}        : ${GREEN}$IP${NC}"
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}${YELLOW}DAFTAR PROTOKOL & PORT:${NC}"
echo -e "  • ${WHITE}OpenSSH${NC}           : 22"
echo -e "  • ${WHITE}Dropbear${NC}          : 109, 143 (Dropbear v2019.78 Static)"
echo -e "  • ${WHITE}Dropbear SSL${NC}      : 443, 8443 (Direct SSL/TLS SNI)"
echo -e "  • ${WHITE}SSH WS (HTTP)${NC}     : 80, 8880, 2082"
echo -e "  • ${WHITE}SSH WS (HTTPS)${NC}    : 443, 8443, 2053, 2083"
echo -e "  • ${WHITE}OpenVPN TCP${NC}       : 1194 & 443 (Direct & SSL Mux)"
echo -e "  • ${WHITE}Squid HTTP Proxy${NC}  : 3128, 8080 & 80 (CONNECT Mux)"
echo -e "  • ${WHITE}VLESS WebSocket${NC}   : 80 (HTTP) & 443 (TLS) [Path: /vless-ws]"
echo -e "  • ${WHITE}VLESS HttpUpgrade${NC} : 80 (HTTP) & 443 (TLS) [Path: /vless-hu]"
echo -e "  • ${WHITE}VLESS XHTTP${NC}       : 80 (HTTP) & 443 (TLS) [Path: /vless-xhttp]"
echo -e "  • ${WHITE}BadVPN UDPGW${NC}      : 7300 (Gaming / Call)"
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}${YELLOW}DOWNLOAD KONFIGURASI OPENVPN CLIENT:${NC}"
echo -e "  • TCP 1194            : https://$DOMAIN/client-tcp-1194.ovpn"
echo -e "  • TCP 443             : https://$DOMAIN/client-tcp-443.ovpn"
echo -e "  • TCP SSL             : https://$DOMAIN/client-tcp-ssl.ovpn"
echo -e "  • TCP WS              : https://$DOMAIN/client-tcp-ws.ovpn"
echo -e "  • All in One ZIP      : https://$DOMAIN/openvpn.zip"
echo -e "  (Catatan: Mendukung direct download di HTTPS & HTTP port 80 & 443)"
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo -e "  ${BOLD}${YELLOW}FITUR SISTEM:${NC}"
echo -e "  • Multi-login IP Limiter Daemon (5 Menit Cooldown Auto-Unlock)"
echo -e "  • REST API Engine di port 8081"
echo -e "  • Notifikasi Bot Telegram otomatis"
echo -e "  • Daily Auto-Expiry cleaner (Systemd timer)"
echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
echo -e "  Ketik ${BOLD}${GREEN}menu${NC} untuk membuka Dashboard Interaktif."
echo -e "  Ketik ${BOLD}${GREEN}menu-ssh${NC} untuk mengelola akun SSH & OpenVPN."
echo -e "  Ketik ${BOLD}${GREEN}menu-vless${NC} untuk mengelola akun VLESS."
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
