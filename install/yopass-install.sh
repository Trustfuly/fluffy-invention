# Copyright (c) 2024 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/paepckehh/yopass-ng

#!/usr/bin/env bash
set -euo pipefail

GITHUB_USER="Trustfuly"
REPO="fluffy-invention"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO}/main"

msg_info()  { echo -e "\e[34m[INFO]\e[0m $1"; }
msg_ok()    { echo -e "\e[32m[OK]\e[0m   $1"; }
msg_error() { echo -e "\e[31m[ERROR]\e[0m $1"; exit 1; }

clear
echo "==========================================="
echo "   Yopass Installation Mode Selection      "
echo "==========================================="
echo "1) Public (Standalone with Certbot/SSL)"
echo "2) Behind Proxy (Nginx Proxy Manager / NPM)"
echo "==========================================="
# Фікс для інтерактивного меню всередині LXC
printf "Select option [1-2]: "
read -r INSTALL_MODE </dev/tty

msg_info "Installing core dependencies..."
apt-get update -qq && apt-get install -y -qq curl wget nginx memcached openssl

msg_info "Configuring Memcached..."
sed -i 's/^-l.*/-l 127.0.0.1/' /etc/memcached.conf
systemctl enable --now memcached

msg_info "Downloading custom binary..."
wget -qO /usr/local/bin/yopass-server "${RAW_URL}/bin/yopass-server"
chmod +x /usr/local/bin/yopass-server

msg_info "Downloading website assets..."
mkdir -p /var/www/yopass
curl -fsSL "https://github.com/${GITHUB_USER}/${REPO}/archive/refs/heads/main.tar.gz" | tar -xz --strip-components=1 -C /tmp/
cp -r /tmp/public/* /var/www/yopass/

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

systemctl daemon-reload && systemctl enable --now yopass

if [[ "$INSTALL_MODE" == "1" ]]; then
    read -rp "Enter domain: " APP_DOMAIN < /dev/tty
    read -rp "Enter email: " APP_EMAIL < /dev/tty
    apt-get install -y -qq certbot python3-certbot-nginx
    cat >/etc/nginx/sites-available/yopass <<'EOF'
server {
    listen 80;
    server_name $APP_DOMAIN;
    root /var/www/yopass;
    index index.html;
    location / { try_files $uri $uri/ /index.html; }
    location /api/ {
        proxy_pass http://127.0.0.1:1337;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx
    certbot --nginx --non-interactive --agree-tos --email "$APP_EMAIL" -d "$APP_DOMAIN" --redirect
elif [[ "$INSTALL_MODE" == "2" ]]; then
    cat >/etc/nginx/sites-available/yopass <<'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/yopass;
    index index.html;
    location / { try_files $uri $uri/ /index.html; }
    location /api/ {
        proxy_pass http://127.0.0.1:1337;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF
    ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
    rm -f /etc/nginx/sites-enabled/default
    systemctl restart nginx
    msg_ok "Installation complete! Use IP: $(hostname -I | awk '{print $1}')"
fi
