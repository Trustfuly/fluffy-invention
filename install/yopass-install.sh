#!/usr/bin/env bash

# Copyright (c) 2024 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/paepckehh/yopass-ng

set -euo pipefail

# ─── Color output helpers ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

msg_info()  { echo -e "  ${YELLOW}[INFO]${NC}  $1"; }
msg_ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
msg_error() { echo -e "  ${RED}[ERROR]${NC} $1"; exit 1; }

# ─── Must run as root ────────────────────────────────────────────────────────
[[ "$EUID" -ne 0 ]] && msg_error "Please run as root."

echo ""
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   Yopass-NG – LXC Installer                  ║"
echo "  ║   https://github.com/Trustfuly/fluffy-invention ║"
echo "  ╚══════════════════════════════════════════════╝"
echo ""

# ─── Update OS ───────────────────────────────────────────────────────────────
msg_info "Updating OS packages"
apt-get update -qq
apt-get upgrade -y -qq
msg_ok "OS packages updated"

# ─── Install dependencies ────────────────────────────────────────────────────
msg_info "Installing dependencies"
apt-get install -y -qq \
  curl \
  wget \
  nginx \
  certbot \
  python3-certbot-nginx \
  openssl \
  memcached
msg_ok "Dependencies installed"

# ─── Configure Memcached ─────────────────────────────────────────────────────
msg_info "Configuring Memcached"
# Bind to localhost only for security
sed -i 's/^-l.*/-l 127.0.0.1/' /etc/memcached.conf
systemctl enable --now memcached
msg_ok "Memcached configured and started"

# ─── Install Yopass-NG binary ────────────────────────────────────────────────
msg_info "Fetching latest Yopass-NG release"
RELEASE=$(curl -fsSL https://api.github.com/repos/paepckehh/yopass-ng/releases/latest \
  | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')

[[ -z "$RELEASE" ]] && msg_error "Could not determine latest release version."
msg_ok "Latest version: v${RELEASE}"

ARCH="amd64"
[[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"

TARBALL="yopass-ng-linux_${ARCH}_${RELEASE}.tar.gz"
DOWNLOAD_URL="https://github.com/paepckehh/yopass-ng/releases/download/v${RELEASE}/${TARBALL}"

msg_info "Downloading ${TARBALL}"
curl -fsSL "$DOWNLOAD_URL" -o /tmp/yopass-ng.tar.gz \
  || msg_error "Download failed. URL: ${DOWNLOAD_URL}"

msg_info "Installing binary"
tar -xzf /tmp/yopass-ng.tar.gz -C /tmp/
mv /tmp/yopass-ng /usr/local/bin/yopass-ng
chmod +x /usr/local/bin/yopass-ng
rm -f /tmp/yopass-ng.tar.gz
echo "${RELEASE}" >/opt/yopass_version.txt
msg_ok "Yopass-NG v${RELEASE} installed to /usr/local/bin/yopass-ng"

# ─── Systemd service ─────────────────────────────────────────────────────────
msg_info "Creating systemd service"
cat >/etc/systemd/system/yopass.service <<EOF
[Unit]
Description=Yopass-NG Secret Sharing Server
Documentation=https://github.com/paepckehh/yopass-ng
After=network.target memcached.service
Wants=memcached.service

[Service]
Type=simple
User=www-data
Group=www-data
ExecStart=/usr/local/bin/yopass-ng \\
  --address=127.0.0.1 \\
  --port=1337 \\
  --database=memcached \\
  --memcached=localhost:11211 \\
  --trusted-proxies=127.0.0.1
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
ProtectSystem=strict
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now yopass
msg_ok "Yopass service started"

# ─── Nginx + self-signed TLS ─────────────────────────────────────────────────
msg_info "Configuring Nginx"
rm -f /etc/nginx/sites-enabled/default

SSL_DIR="/etc/nginx/ssl"
mkdir -p "$SSL_DIR"
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$SSL_DIR/yopass.key" \
  -out "$SSL_DIR/yopass.crt" \
  -subj "/CN=yopass.local" 2>/dev/null

cat >/etc/nginx/sites-available/yopass <<'NGINXCONF'
# Yopass-NG Nginx configuration
# Repository: https://github.com/Trustfuly/fluffy-invention
# To issue a trusted certificate: bash /opt/yopass-certbot.sh

server {
    listen 80;
    server_name _;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/yopass.crt;
    ssl_certificate_key /etc/nginx/ssl/yopass.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy no-referrer;

    location / {
        proxy_pass         http://127.0.0.1:1337;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_read_timeout 30;
    }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
nginx -t && systemctl enable --now nginx
msg_ok "Nginx configured with self-signed TLS"

# ─── Certbot helper script ───────────────────────────────────────────────────
msg_info "Creating Let's Encrypt helper"
cat >/opt/yopass-certbot.sh <<'CERTBOT'
#!/usr/bin/env bash
# Yopass-NG – Let's Encrypt certificate setup
# Repository: https://github.com/Trustfuly/fluffy-invention
#
# Requirements:
#   • Ports 80 and 443 open and reachable from the internet
#   • DNS A-record pointing to this server's IP
#
# Usage: bash /opt/yopass-certbot.sh

set -euo pipefail

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Yopass-NG – Let's Encrypt TLS Setup    ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""
echo "  Make sure ports 80 and 443 are reachable from the internet"
echo "  and a DNS A-record points to this server's IP."
echo ""

read -rp "  Domain (e.g. secrets.example.com): " DOMAIN
read -rp "  Email for Let's Encrypt notices:   " EMAIL

[[ -z "$DOMAIN" || -z "$EMAIL" ]] && { echo "  [ERROR] Domain and email are required."; exit 1; }

certbot --nginx \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  -d "$DOMAIN" \
  --redirect

sed -i "s/server_name _;/server_name ${DOMAIN};/g" /etc/nginx/sites-available/yopass
nginx -t && systemctl reload nginx

echo ""
echo "  ✅  Certificate issued!"
echo "      https://${DOMAIN}"
echo ""
echo "  Auto-renewal is handled by the certbot systemd timer."
echo "  Test with: certbot renew --dry-run"
CERTBOT

chmod +x /opt/yopass-certbot.sh
msg_ok "Created /opt/yopass-certbot.sh"

# ─── Done ────────────────────────────────────────────────────────────────────
IP=$(hostname -I | awk '{print $1}')
echo ""
echo "  ╔══════════════════════════════════════════════════════════════╗"
echo "  ║   ✅  Yopass-NG installed successfully!                      ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
printf  "  ║   🌐  URL     : https://%-38s ║\n" "${IP}  (self-signed)"
echo "  ║   🔒  TLS     : self-signed (browser warning expected)      ║"
echo "  ║   📜  Certbot : bash /opt/yopass-certbot.sh                 ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo "  ║   Service management:                                        ║"
echo "  ║     systemctl status|restart|stop yopass                    ║"
echo "  ╠══════════════════════════════════════════════════════════════╣"
echo "  ║   Config files:                                              ║"
echo "  ║     /etc/systemd/system/yopass.service                      ║"
echo "  ║     /etc/nginx/sites-available/yopass                       ║"
echo "  ║     /etc/memcached.conf                                      ║"
echo "  ╚══════════════════════════════════════════════════════════════╝"
echo ""
