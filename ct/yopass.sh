#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2024 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/jhaals/yopass

# App Default Values
APP="Yopass"
var_tags="security;secrets"
var_cpu="1"
var_ram="256"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

INSTALL_URL="https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/install/yopass-install.sh"

header_info "$APP"
base_settings
variables
color
catch_errors

function update_script() {
  header_info
  if [[ ! -f /usr/local/bin/yopass-server ]]; then
    msg_error "No ${APP} installation found!"
    exit
  fi
  msg_info "Re-run the installer to update."
  exit
}

start
build_container
pct exec "$CTID" -- bash -c "mkdir -p /etc/systemd/system/container-getty@1.service.d && cat > /etc/systemd/system/container-getty@1.service.d/autologin.conf << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin root --noclear %I \$TERM
EOF"
pct exec "$CTID" -- passwd -d root
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart container-getty@1

# Ask install mode on the HOST (has a real terminal)
echo ""
echo "  ┌──────────────────────────────────────────┐"
echo "  │      Yopass – Installation Mode          │"
echo "  ├──────────────────────────────────────────┤"
echo "  │  1) Public  – Standalone + Certbot/SSL   │"
echo "  │  2) Proxy   – Behind NPM / Traefik       │"
echo "  └──────────────────────────────────────────┘"
printf "  Select option [1-2]: "
read -r INSTALL_MODE

while [[ "$INSTALL_MODE" != "1" && "$INSTALL_MODE" != "2" ]]; do
  printf "  Invalid choice. Select option [1-2]: "
  read -r INSTALL_MODE
done

msg_info "Starting Yopass installation (mode: ${INSTALL_MODE})"

# Download install script into container and run it with INSTALL_MODE env var
if [[ "$INSTALL_MODE" == "1" ]]; then
  printf "  Enter domain (e.g. secrets.example.com): "
  read -r APP_DOMAIN
  printf "  Enter email for Let's Encrypt notices:   "
  read -r APP_EMAIL

  lxc-attach -n "$CTID" -- bash -c "
    curl -fsSL '${INSTALL_URL}' -o /tmp/yopass-install.sh
    INSTALL_MODE='${INSTALL_MODE}' APP_DOMAIN='${APP_DOMAIN}' APP_EMAIL='${APP_EMAIL}' bash /tmp/yopass-install.sh
  "
else
  lxc-attach -n "$CTID" -- bash -c "
    curl -fsSL '${INSTALL_URL}' -o /tmp/yopass-install.sh
    INSTALL_MODE='${INSTALL_MODE}' bash /tmp/yopass-install.sh
  "
fi

msg_ok "Completed Successfully!\n"
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
