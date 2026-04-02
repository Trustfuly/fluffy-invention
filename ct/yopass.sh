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
pct exec "$CTID" -- passwd -d root

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
lxc-attach -n "$CTID" -- bash -c "
  curl -fsSL '${INSTALL_URL}' -o /tmp/yopass-install.sh
  INSTALL_MODE='${INSTALL_MODE}' bash /tmp/yopass-install.sh
"

msg_ok "Completed Successfully!\n"
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
