#!/usr/bin/env bash

# Copyright (c) 2024 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/paepckehh/yopass-ng

#!/usr/bin/env bash
set -euo pipefail

# ─── Color output helpers ────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

msg_info()  { echo -e "  ${YELLOW}[INFO]${NC}  $1"; }
msg_ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
msg_error() { echo -e "  ${RED}[ERROR]${NC} $1"; exit 1; }

[[ "$EUID" -ne 0 ]] && msg_error "Please run as root."

# ─── Domain Prompt ───────────────────────────────────────────────────────────
echo -e "${YELLOW}>>> Configuration Request${NC}"
read -rp "  Enter your domain (e.g., secrets.yourdomain.com): " APP_DOMAIN
[[ -z "$APP_DOMAIN" ]] && APP_DOMAIN="yopass.local"
msg_ok "Using domain: $APP_DOMAIN"

# ─── Update & Dependencies ───────────────────────────────────────────────────
msg_info "Updating OS and installing dependencies"
apt-get update -qq && apt-get upgrade -y -qq
apt-get install -y -qq curl wget nginx certbot python3-certbot-nginx openssl memcached

# ─── Memcached ───────────────────────────────────────────────────────────────
sed -i 's/^-l.*/-l 127.0.0.1/' /etc/memcached.conf
systemctl enable --now memcached

# ─── Yopass-NG Binary ────────────────────────────────────────────────────────
RELEASE=$(curl -fsSL https://api.github.com/repos/paepckehh/yopass-ng/releases/latest | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')
ARCH="amd64"
[[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"

msg_info "Installing Yopass-NG v${RELEASE}"
curl -fsSL "https://github.com/paepckehh/yopass-ng/releases/download/v${RELEASE}/yopass-ng-linux_${ARCH}_${RELEASE}.tar.gz" -o /tmp/yopass.tar.gz
tar -xzf /tmp/yopass.tar.gz -C /tmp/
# Знаходимо бінарний файл незалежно від структури архіву
BINARY=$(find /tmp -type f -name "yopass-ng" | head -n 1)
mv "$BINARY" /usr/local/bin/yopass-ng
chmod +x /usr/local/bin/yopass-ng
echo "${RELEASE}" >/opt/yopass_version.txt

# ─── Systemd (ВИПРАВЛЕНО: без trusted-proxies) ───────────────────────────────
cat >/etc/systemd/system/yopass.service <<EOF
[Unit]
Description=Yopass-NG Secret Sharing Server
After=network.target memcached.service

[Service]
Type=simple
User=www-data
Group=www-data
ExecStart=/usr/local/bin/yopass-ng \\
  --address=127.0.0.1 \\
  --port=1337 \\
  --database=memcached \\
  --memcached=localhost:11211
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=strict

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now yopass

# ─── Nginx (ВИПРАВЛЕНО: домен прописано) ─────────────────────────────────────
mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/yopass.key -out /etc/nginx/ssl/yopass.crt \
  -subj "/CN=${APP_DOMAIN}" 2>/dev/null

cat >/etc/nginx/sites-available/yopass <<NGINXCONF
server {
    listen 80;
    server_name ${APP_DOMAIN};
    location / { return 301 https://\$host\$request_uri; }
 }
server {
    listen 443 ssl;
    server_name ${APP_DOMAIN};
    ssl_certificate /etc/nginx/ssl/yopass.crt;
    ssl_certificate_key /etc/nginx/ssl/yopass.key;
    location / {
        proxy_pass http://127.0.0.1:1337;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
NGINXCONF

ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
rm -f /etc/nginx/sites-enabled/default
systemctl restart nginx
