#!/usr/bin/env bash

# Copyright (c) 2024 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/jhaals/yopass

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing dependencies"
$STD apt-get install -y \
  curl \
  wget \
  nginx \
  certbot \
  python3-certbot-nginx \
  openssl
msg_ok "Installed dependencies"

msg_info "Installing Memcached"
$STD apt-get install -y memcached
# Bind memcached to localhost only for security
sed -i 's/^-l.*/-l 127.0.0.1/' /etc/memcached.conf
systemctl enable --now memcached
msg_ok "Installed Memcached"

msg_info "Installing Yopass"
RELEASE=$(curl -fsSL https://api.github.com/repos/jhaals/yopass/releases/latest \
  | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')

# Detect CPU architecture
ARCH="amd64"
[[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"

TARBALL="yopass-server_linux_${ARCH}.tar.gz"
curl -fsSL "https://github.com/jhaals/yopass/releases/download/${RELEASE}/${TARBALL}" \
  -o /tmp/yopass-server.tar.gz

tar -xzf /tmp/yopass-server.tar.gz -C /tmp/
mv /tmp/yopass-server /usr/local/bin/yopass-server
chmod +x /usr/local/bin/yopass-server
rm -f /tmp/yopass-server.tar.gz

# Store installed version for update detection
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

# Generate a self-signed certificate as a fallback until certbot runs
SSL_DIR="/etc/nginx/ssl"
mkdir -p "$SSL_DIR"
openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
  -keyout "$SSL_DIR/yopass.key" \
  -out "$SSL_DIR/yopass.crt" \
  -subj "/CN=yopass.local" \
  2>/dev/null

cat >/etc/nginx/sites-available/yopass <<'EOF'
# Yopass Nginx configuration
# Managed by: https://github.com/Trustfuly/fluffy-invention
# To enable Let's Encrypt TLS: run /opt/yopass-certbot.sh

server {
    listen 80;
    server_name _;

    # Allow ACME challenge for certbot
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Redirect all other HTTP traffic to HTTPS
    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name _;

    ssl_certificate     /etc/nginx/ssl/yopass.crt;
    ssl_certificate_key /etc/nginx/ssl/yopass.key;
    ssl_protocols       TLSv1.2 TLSv1.3;
    ssl_ciphers         HIGH:!aNULL:!MD5;

    # Security headers
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
msg_ok "Configured Nginx with self-signed TLS"

msg_info "Creating Let's Encrypt helper script"
cat >/opt/yopass-certbot.sh <<'CERTBOT_SCRIPT'
#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Yopass – Let's Encrypt certificate setup helper
#  Repository: https://github.com/Trustfuly/fluffy-invention
#
#  Requirements before running:
#    • Port 80 and 443 must be reachable from the internet
#    • A DNS A-record must already point to this server's IP
#
#  Usage:
#    bash /opt/yopass-certbot.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   Yopass – Let's Encrypt TLS Setup       ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""
echo "  Before continuing, make sure:"
echo "    • Port 80 and 443 are open and reachable from the internet"
echo "    • A DNS A-record points to this server's IP address"
echo ""

read -rp "  Enter your domain (e.g. secrets.example.com): " DOMAIN
read -rp "  Enter your email for Let's Encrypt notices:   " EMAIL

if [[ -z "$DOMAIN" || -z "$EMAIL" ]]; then
  echo "  [ERROR] Domain and email are required. Aborting."
  exit 1
fi

echo ""
echo "  [INFO] Requesting certificate for: ${DOMAIN}"

# Obtain and install certificate; certbot will also configure nginx
certbot --nginx \
  --non-interactive \
  --agree-tos \
  --email "$EMAIL" \
  -d "$DOMAIN" \
  --redirect

# Update server_name in nginx config to match the actual domain
sed -i "s/server_name _;/server_name ${DOMAIN};/g" /etc/nginx/sites-available/yopass
nginx -t && systemctl reload nginx

echo ""
echo "  ✅  Certificate issued successfully!"
echo ""
echo "  Yopass is now available at:"
echo "      https://${DOMAIN}"
echo ""
echo "  Auto-renewal is configured via the certbot systemd timer."
echo "  Test it with:  certbot renew --dry-run"
CERTBOT_SCRIPT

chmod +x /opt/yopass-certbot.sh
msg_ok "Created /opt/yopass-certbot.sh"

msg_info "Waiting for services to settle"
sleep 2
msg_ok "All services are running"

motd_ssh
customize

echo ""
echo -e "  ${INFO}${YW} Yopass installed successfully!${CL}"
echo -e "  ${TAB}${GATEWAY}${BGN}https://$(hostname -I | awk '{print $1}')${CL}  (self-signed TLS — browser warning expected)"
echo ""
echo -e "  ${INFO}${YW} To issue a trusted Let's Encrypt certificate:${CL}"
echo -e "  ${TAB}bash /opt/yopass-certbot.sh"
echo ""
echo -e "  ${INFO}${YW} Service management:${CL}"
echo -e "  ${TAB}systemctl status yopass"
echo -e "  ${TAB}systemctl restart yopass"
echo ""
echo -e "  ${INFO}${YW} Configuration files:${CL}"
echo -e "  ${TAB}/etc/systemd/system/yopass.service"
echo -e "  ${TAB}/etc/nginx/sites-available/yopass"
echo -e "  ${TAB}/etc/memcached.conf"
