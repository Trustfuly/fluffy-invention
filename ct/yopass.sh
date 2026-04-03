#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026 Trustfuly
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

GITHUB_USER="Trustfuly"
REPO="fluffy-invention"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO}/main"
INSTALL_URL="${RAW_URL}/install/yopass-install.sh"

header_info "$APP"
base_settings
variables
color
catch_errors

start

# ─── ASCII logo ───────────────────────────────────────────────────────────────
echo -e "\n${GN}
    ██╗   ██╗ ██████╗ ██████╗  █████╗ ███████╗███████╗
    ╚██╗ ██╔╝██╔═══██╗██╔══██╗██╔══██╗██╔════╝██╔════╝
     ╚████╔╝ ██║   ██║██████╔╝███████║███████╗███████╗
      ╚██╔╝  ██║   ██║██╔═══╝ ██╔══██║╚════██║╚════██║
       ██║   ╚██████╔╝██║     ██║  ██║███████║███████║
       ╚═╝    ╚═════╝ ╚═╝     ╚═╝  ╚═╝╚══════╝╚══════╝
${CL}"
echo -e "  ${YW}Secure sharing of secrets, passwords and files${CL}\n"

build_container

# ─── Auto-login setup ────────────────────────────────────────────────────────
pct exec "$CTID" -- mkdir -p /etc/systemd/system/container-getty@1.service.d
pct exec "$CTID" -- bash -c "printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear tty1\n' > /etc/systemd/system/container-getty@1.service.d/autologin.conf"
pct exec "$CTID" -- passwd -d root >/dev/null 2>&1
pct exec "$CTID" -- systemctl daemon-reload >/dev/null 2>&1
pct exec "$CTID" -- systemctl restart container-getty@1 >/dev/null 2>&1

# ─── Installation mode selection ─────────────────────────────────────────────
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

# ─── Run installer inside container ──────────────────────────────────────────
if [[ "$INSTALL_MODE" == "1" ]]; then
  set +e
  APP_DOMAIN=$(whiptail --inputbox "Enter domain (e.g. secrets.example.com)" 8 60 3>&1 1>&2 2>&3)
  APP_EMAIL=$(whiptail --inputbox "Enter email for Let's Encrypt notices" 8 60 3>&1 1>&2 2>&3)
  set -e
  [[ -z "$APP_DOMAIN" || -z "$APP_EMAIL" ]] && msg_error "Domain and email are required."
  msg_info "Starting Yopass installation (mode: ${INSTALL_MODE})"
  lxc-attach -n "$CTID" -- bash -c "
    curl -fsSL '${INSTALL_URL}' -o /tmp/yopass-install.sh 2>/dev/null
    INSTALL_MODE='${INSTALL_MODE}' APP_DOMAIN='${APP_DOMAIN}' APP_EMAIL='${APP_EMAIL}' bash /tmp/yopass-install.sh
  "
else
  msg_info "Starting Yopass installation (mode: ${INSTALL_MODE})"
  lxc-attach -n "$CTID" -- bash -c "
    curl -fsSL '${INSTALL_URL}' -o /tmp/yopass-install.sh 2>/dev/null
    INSTALL_MODE='${INSTALL_MODE}' bash /tmp/yopass-install.sh
  "
fi

msg_ok "Completed Successfully!\n"
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
