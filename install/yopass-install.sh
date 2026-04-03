#!/usr/bin/env bash

# Copyright (c) 2024 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/jhaals/yopass

set -euo pipefail

GITHUB_USER="Trustfuly"
REPO="fluffy-invention"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO}/main"

msg_info()  { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_ok()    { echo -e "\e[32m[OK]\e[0m   $1"; }
msg_error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

# INSTALL_MODE is passed as env var from ct/yopass.sh
# If running standalone (direct call), ask interactively
if [[ -z "${INSTALL_MODE:-}" ]]; then
  clear
  echo "==========================================="
  echo "   Yopass Installation Mode Selection      "
  echo "==========================================="
  echo "1) Public (Standalone with Certbot/SSL)"
  echo "2) Behind Proxy (Nginx Proxy Manager / NPM)"
  echo "==========================================="
  printf "Select option [1-2]: "
  read -r INSTALL_MODE
fi

[[ "$INSTALL_MODE" != "1" && "$INSTALL_MODE" != "2" ]] && msg_error "Invalid selection. Please enter 1 or 2."
msg_info "Install mode: ${INSTALL_MODE}"

msg_info "Installing core dependencies"
apt-get update -qq && apt-get install -y -qq curl wget nginx memcached openssl

msg_info "Configuring Memcached"
sed -i 's/^-l.*/-l 127.0.0.1/' /etc/memcached.conf
systemctl enable --now memcached
msg_ok "Memcached configured"

msg_info "Downloading Yopass binary"
wget -qO /usr/local/bin/yopass-server "${RAW_URL}/bin/yopass-server"
chmod +x /usr/local/bin/yopass-server
msg_ok "Binary installed"

msg_info "Downloading website assets"
mkdir -p /var/www/yopass /tmp/yopass_repo
curl -fsSL "https://github.com/${GITHUB_USER}/${REPO}/archive/refs/heads/main.tar.gz" \
  | tar -xz -C /tmp/yopass_repo --strip-components=1
cp -r /tmp/yopass_repo/public/* /var/www/yopass/
rm -rf /tmp/yopass_repo
chown -R www-data:www-data /var/www/yopass
msg_ok "Website assets installed"

msg_info "Creating systemd service"
cat >/etc/systemd/system/yopass.service <<EOF
[Unit]
Description=Yopass Secret Sharing Server
Documentation=https://github.com/jhaals/yopass
After=network.target memcached.service
Wants=memcached.service

[Service]
Type=simple
User=www-data
Group=www-data
ExecStart=/usr/local/bin/yopass-server --address 127.0.0.1 --port 1337 --database memcached --memcached localhost:11211
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload && systemctl enable --now yopass
msg_ok "Yopass service started"

rm -f /etc/nginx/sites-enabled/default

mkdir -p /etc/nginx/ssl
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout /etc/nginx/ssl/yopass.key \
  -out /etc/nginx/ssl/yopass.crt \
  -subj "/CN=yopass.local" 2>/dev/null
msg_ok "Self-signed certificate generated"

if [[ "$INSTALL_MODE" == "1" ]]; then
    printf "Enter domain (e.g. secrets.example.com): "
    APP_DOMAIN="${APP_DOMAIN:-}"
    printf "Enter email for Let's Encrypt notices:   "
    APP_EMAIL="${APP_EMAIL:-}"

    [[ -z "$APP_DOMAIN" || -z "$APP_EMAIL" ]] && msg_error "Domain and email are required."

    msg_info "Installing Certbot"
    apt-get install -y -qq certbot python3-certbot-nginx

    # Note: double-quoted EOF so $APP_DOMAIN is expanded
    cat >/etc/nginx/sites-available/yopass <<EOF
server {
    listen 80;
    server_name ${APP_DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl;
    server_name ${APP_DOMAIN};
    ssl_protocols TLSv1.2 TLSv1.3;

    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy no-referrer;

    root /var/www/yopass;
    index index.html;

    # Frontend - serve React SPA
    location / {
        try_files \$uri \$uri/ /index.html;
    }

    # Backend API - proxy to yopass-server
    location ~ ^/(secret|create|file|config) {
        proxy_pass         http://127.0.0.1:1337;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
    nginx -t && systemctl restart nginx

    msg_info "Requesting Let's Encrypt certificate for ${APP_DOMAIN}"
    certbot --nginx --non-interactive --agree-tos --email "$APP_EMAIL" -d "$APP_DOMAIN" --redirect
    msg_ok "Standalone install complete!"
    echo ""
    echo "  ✅  Yopass is available at: https://${APP_DOMAIN}"

elif [[ "$INSTALL_MODE" == "2" ]]; then
    msg_info "Configuring Proxy Mode (HTTP only, no TLS)"
    cat >/etc/nginx/sites-available/yopass <<'EOF'

server {
    listen 80;
    server_name _;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/yopass.crt;
    ssl_certificate_key /etc/nginx/ssl/yopass.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header Referrer-Policy no-referrer;

    root /var/www/yopass;
    index index.html;

    location ~ ^/(secret|create|file|config) {
        proxy_pass         http://127.0.0.1:1337;
        proxy_set_header   Host              $host;
        proxy_set_header   X-Real-IP         $remote_addr;
        proxy_set_header   X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
    }

    location / {
        try_files $uri $uri/ /index.html;
    }
}
EOF

    ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
    rm -f /etc/nginx/sites-enabled/default
    nginx -t && systemctl restart nginx

    IP=$(hostname -I | awk '{print $1}')

    clear
    echo -e "\e[32m"
    echo ""
    echo ""
    echo ""
    echo "    ╔══════════════════════════════════════════════════════════╗"
    echo "    ║          ✅  Yopass installed successfully!              ║"
    echo "    ╚══════════════════════════════════════════════════════════╝"
    echo "        🌐  URL      : https://${IP}                           "
    echo "        🔁  Proxy to : https://${IP}                           "
    echo "        🔒  TLS      : handled by your reverse proxy           "
    echo "    ╔══════════════════════════════════════════════════════════╗"
    echo "    ║              Container login: root                       ║"
    echo "    ║              Container password: blank                   ║"
    echo "    ╠══════════════════════════════════════════════════════════╣"
    echo "    ║   Service management:                                    ║"
    echo "    ║     systemctl status yopass                              ║"
    echo "    ║     systemctl restart yopass                             ║"
    echo "    ╠══════════════════════════════════════════════════════════╣"
    echo "    ║   Config files:                                          ║"
    echo "    ║     /etc/nginx/sites-available/yopass                    ║"
    echo "    ║     /etc/systemd/system/yopass.service                   ║"
    echo "    ║     /etc/memcached.conf                                  ║"
    echo "    ╚══════════════════════════════════════════════════════════╝"
    echo -e "\e[0m"
else
    msg_error "Invalid selection. Please enter 1 or 2."
fi
