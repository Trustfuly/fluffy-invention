#!/usr/bin/env bash

# Copyright (c) 2024 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/paepckehh/yopass-ng

#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
GITHUB_USER="Trustfuly"
REPO="fluffy-invention"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO}/main"

msg_info()  { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_ok()    { echo -e "\e[32m[OK]\e[0m   $1"; }
msg_error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

 # --- Installation Mode Menu ---
clear
echo "==========================================="
echo "   Yopass Installation Mode Selection      "
echo "==========================================="
echo "1) Public (Standalone with Certbot/SSL)"
echo "   - For direct internet connection"
echo "   - Automatically obtains SSL certificate"
echo ""
echo "2) Behind Proxy (Nginx Proxy Manager / NPM)"
echo "   - For use with an external proxy server"
echo "   - Container runs on HTTP (Port 80)"
echo "==========================================="
read -p "Select option [1-2]: " INSTALL_MODE

# --- Core Installation Steps ---

msg_info "Installing core dependencies..."
apt-get update -qq
apt-get install -y -qq curl wget nginx memcached openssl

msg_info "Configuring Memcached..."
sed -i 's/^-l.*/-l 127.0.0.1/' /etc/memcached.conf
systemctl enable --now memcached

msg_info "Downloading custom yopass-server binary..."
wget -qO /usr/local/bin/yopass-server "${RAW_URL}/bin/yopass-server"
chmod +x /usr/local/bin/yopass-server

msg_info "Downloading website assets..."
mkdir -p /var/www/yopass
mkdir -p /tmp/yopass_repo
curl -fsSL "https://github.com/${GITHUB_USER}/${REPO}/archive/refs/heads/main.tar.gz" | tar -xz -C /tmp/yopass_repo --strip-components=1
cp -r /tmp/yopass_repo/public/* /var/www/yopass/
rm -rf /tmp/yopass_repo

msg_info "Creating systemd service..."
cat >/etc/systemd/system/yopass.service <<EOF
[Unit]
Description=Yopass Secret Sharing Server
After=network.target memcached.service

[Service]
Type=simple
User=www-data
Group=www-data
ExecStart=/usr/local/bin/yopass-server --address 127.0.0.1 --port 1337 --database memcached
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now yopass

 # --- Mode-Specific Configuration ---
 
if [[ "$INSTALL_MODE" == "1" ]]; then
    # MODE 1: PUBLIC STANDALONE
    read -rp "Enter domain (e.g., secrets.domain.com): " APP_DOMAIN
    read -rp "Enter email (for Let's Encrypt notices): " APP_EMAIL
     
    if [[ -z "$APP_DOMAIN" || -z "$APP_EMAIL" ]]; then
    msg_error "Domain and Email are required for Standalone mode."
    fi
 
    msg_info "Installing Certbot..."
    apt-get install -y -qq certbot python3-certbot-nginx
     
    cat >/etc/nginx/sites-available/yopass <<EOF
server {
    listen 80;
    server_name $APP_DOMAIN;
    root /var/www/yopass;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }

    location /api/ {
        proxy_pass http://127.0.0.1:1337;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx
     
    msg_info "Requesting SSL certificate from Let's Encrypt..."
    certbot --nginx --non-interactive --agree-tos --email "$APP_EMAIL" -d "$APP_DOMAIN" --redirect
     
    msg_ok "Installation complete! Access your Yopass at: https://$APP_DOMAIN"

elif [[ "$INSTALL_MODE" == "2" ]]; then
    # MODE 2: BEHIND PROXY
    msg_info "Configuring Nginx for Proxy Mode (HTTP)..."
    
    cat >/etc/nginx/sites-available/yopass <<EOF
server {
    listen 80;
    server_name _;
    root /var/www/yopass;
    index index.html;
     
    location / {
        try_files \$uri \$uri/ /index.html;
    }
     
    location /api/ {
        proxy_pass http://127.0.0.1:1337;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx
    
    IP_ADDR=$(hostname -I | awk '{print $1}')
    msg_ok "Installation complete in Proxy Mode!"
    echo "-------------------------------------------------------"
    echo "Configuration for your external Proxy (e.g., NPM):"
    echo "1. Domain: your.domain.com"
    echo "2. Scheme: http"
    echo "3. Forward IP: $IP_ADDR"
    echo "4. Forward Port: 80"
    echo "5. Enable 'Websockets support' and 'SSL' in your proxy."
    echo "-------------------------------------------------------"
else
