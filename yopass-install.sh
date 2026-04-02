#!/usr/bin/env bash

# Copyright (c) 2024 community-scripts ORG
# Author: community
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://github.com/jhaals/yopass

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  wget \
  nginx \
  certbot \
  python3-certbot-nginx \
  openssl
msg_ok "Installed Dependencies"

msg_info "Installing Memcached"
$STD apt-get install -y memcached
# Bind memcached to localhost only (security)
sed -i 's/^-l.*/-l 127.0.0.1/' /etc/memcached.conf
systemctl enable --now memcached
msg_ok "Installed Memcached"

msg_info "Installing Yopass"
RELEASE=$(curl -fsSL https://api.github.com/repos/jhaals/yopass/releases/latest \
  | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')

ARCH="amd64"
[[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"

TARBALL="yopass-server_linux_${ARCH}.tar.gz"
curl -fsSL "https://github.com/jhaals/yopass/releases/download/${RELEASE}/${TARBALL}" \
  -o /tmp/yopass-server.tar.gz

tar -xzf /tmp/yopass-server.tar.gz -C /tmp/
mv /tmp/yopass-server /usr/local/bin/yopass-server
chmod +x /usr/local/bin/yopass-server
rm -f /tmp/yopass-server.tar.gz

echo "${RELEASE}" >/opt/yopass_version.txt
msg_ok "Installed Yopass ${RELEASE}"

msg_info "Creating Yopass systemd service"
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
ExecStart=/usr/local/bin/yopass-server \\
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
systemctl enable --now yopass
msg_ok "Created and started Yopass service"

msg_info "Configuring Nginx"
rm -f /etc/nginx/sites-enabled/default

# --- Self-signed cert as fallback (used until certbot runs) ---
SSL_DIR="/etc/nginx/ssl"
mkdir -p "$SSL_DIR"
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$SSL_DIR/yopass.key" \
  -out "$SSL_DIR/yopass.crt" \
  -subj "/CN=yopass.local" \
  2>/dev/null

cat >/etc/nginx/sites-available/yopass <<'EOF'
# Yopass - managed by community-scripts installer
# To enable Let's Encrypt: run /opt/yopass-certbot.sh

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
EOF

ln -sf /etc/nginx/sites-available/yopass /etc/nginx/sites-enabled/yopass
nginx -t && systemctl enable --now nginx
msg_ok "Configured Nginx (self-signed TLS)"

msg_info "Creating Let's Encrypt helper script"
cat >/opt/yopass-certbot.sh <<'CERTBOT_SCRIPT'
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  Yopass – Let's Encrypt certificate setup
#  Usage:  bash /opt/yopass-certbot.sh
# ─────────────────────────────────────────────────────────────
set -euo pipefail

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Yopass – Let's Encrypt TLS Setup       ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""
echo "  Requirements:"
echo "   • Port 80 and 443 must be reachable from the internet"
echo "   • A DNS A-record must already point to this IP"
echo ""

read -rp "  Enter your domain (e.g. secrets.example.com): " DOMAIN
read -rp "  Enter your email for Let's Encrypt notices: " EMAIL

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "  [ERROR] Domain and email are required."
  exit 1
fi

echo ""
echo "  [INFO] Requesting certificate for: $DOMAIN"

certbot --nginx \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  -d "$DOMAIN" \
  --redirect

# Update nginx server_name
sed -i "s/server_name _;/server_name ${DOMAIN};/g" /etc/nginx/sites-available/yopass
nginx -t && systemctl reload nginx

echo ""
echo "  ✅  Done! Yopass is now available at:"
echo "      https://${DOMAIN}"
echo ""
echo "  Certbot auto-renewal is already configured via systemd timer."
echo "  Test it with:  certbot renew --dry-run"
CERTBOT_SCRIPT

chmod +x /opt/yopass-certbot.sh
msg_ok "Created /opt/yopass-certbot.sh"

msg_info "Waiting for services to settle"
sleep 2
msg_ok "Yopass is running"

motd_ssh
customize

echo ""
echo -e "  ${INFO}${YW}Yopass installed successfully!${CL}"
echo -e "  ${TAB}${GATEWAY}${BGN}https://$(hostname -I | awk '{print $1}')${CL}  (self-signed TLS)"
echo ""
echo -e "  ${INFO}${YW}To enable Let's Encrypt:${CL}"
echo -e "  ${TAB}bash /opt/yopass-certbot.sh"
echo ""
echo -e "  ${INFO}${YW}Service management:${CL}"
echo -e "  ${TAB}systemctl status yopass"
echo -e "  ${TAB}systemctl restart yopass"
echo ""
echo -e "  ${INFO}${YW}Config files:${CL}"
echo -e "  ${TAB}/etc/nginx/sites-available/yopass"
echo -e "  ${TAB}/etc/memcached.conf"
echo -e "  ${TAB}/etc/systemd/system/yopass.service"
