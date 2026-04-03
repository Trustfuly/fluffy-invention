#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/jhaals/yopass

# App Default Values
APP="Yopass"
var_tags="yopass;security;secrets"
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

# ─── Check for existing Yopass containers ────────────────────────────────────
GITHUB_USER="Trustfuly"
REPO="fluffy-invention"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO}/main"

function update_script() {
  trap - EXIT
  trap - ERR
  
  header_info
  msg_info "Searching for containers with 'yopass' tag..."
  
  local UPD_CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/[0-9]*.conf 2>/dev/null | awk -F'/' '{print $NF}' | sed 's/\.conf//' || true)

  if [[ -z "$UPD_CTIDS" ]]; then
    msg_error "No containers found with 'yopass' tag."
    exit 0
  fi

  for CTID in $UPD_CTIDS; do
    local STATUS=$(pct status "$CTID" 2>/dev/null | awk '{print $2}' || echo "stopped")
    
    if [[ "$STATUS" != "running" ]]; then
      msg_info "Container $CTID is $STATUS. Skipping."
      continue
    fi

    pct exec "$CTID" -- bash -c "
        set -euo pipefail
        G='\033[0;32m'
        Y='\033[1;33m'
        R='\033[0;31m'
        NC='\033[0m'

        echo \"\"
        echo \"  ╔══════════════════════════════════════════════════════════╗\"
        echo \"  ║              Yopass – Update ($CTID)                     ║\"
        echo \"  ╚══════════════════════════════════════════════════════════╝\"
        echo \"\"

        echo -e \"  \${Y}[1/4]\${NC} Stopping service & cleaning web root...\"
        systemctl stop yopass || true
        find /var/www/yopass -mindepth 1 -delete

        echo -e \"  \${Y}[2/4]\${NC} Updating Yopass binary...\"
        wget -qO /usr/local/bin/yopass-server \"${RAW_URL}/bin/yopass-server\"
        chmod +x /usr/local/bin/yopass-server

        echo -e \"  \${Y}[3/4]\${NC} Fetching and deploying frontend assets...\"
        mkdir -p /tmp/yopass_update
        curl -fsSL \"https://github.com/${GITHUB_USER}/${REPO}/archive/refs/heads/main.tar.gz\" \
          | tar -xz -C /tmp/yopass_update --strip-components=1
        if [ -d \"/tmp/yopass_update/public\" ]; then
            cp -a /tmp/yopass_update/public/. /var/www/yopass/
        else
            cp -a /tmp/yopass_update/. /var/www/yopass/
        fi
        rm -rf /tmp/yopass_update
        chown -R www-data:www-data /var/www/yopass
        chmod -R 755 /var/www/yopass

        echo -e \"  \${Y}[4/4]\${NC} Finalizing and restarting...\"
        rm -rf /var/lib/nginx/proxy/*
        systemctl start yopass
        systemctl restart nginx

        IP=\$(hostname -I | awk '{print \$1}')
        echo \"\"
        echo \"  ╔══════════════════════════════════════════════════════════╗\"
        echo \"  ║          ✅  Yopass updated successfully!                 ║\"
        echo \"  ╠══════════════════════════════════════════════════════════╣\"
        printf \"  ║   🌐  URL : https://%-38s ║\\n\" \"\${IP}\"
        echo \"  ╚══════════════════════════════════════════════════════════╝\"
    "
  done
  
  msg_ok "All updates finished. Please restart your browser or clear cache."
  exit 0
}

EXISTING_CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/[0-9]*.conf 2>/dev/null | awk -F'/' '{print $NF}' | sed 's/\.conf//' || true)

if [[ -n "$EXISTING_CTIDS" ]]; then
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Update Detected" --yesno "Existing Yopass containers found: $EXISTING_CTIDS\n\nDo you want to UPDATE them instead of creating a new one?" 12 65); then
    update_script
  fi
fi

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
pct exec "$CTID" -- mkdir -p /etc/systemd/system/container-getty@1.service.d
pct exec "$CTID" -- bash -c "printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear tty1\n' > /etc/systemd/system/container-getty@1.service.d/autologin.conf"
pct exec "$CTID" -- passwd -d root 2>/dev/null
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

# Download install script into container and run it with INSTALL_MODE env var
if [[ "$INSTALL_MODE" == "1" ]]; then
  set +e
  APP_DOMAIN=$(whiptail --inputbox "Enter domain (e.g. secrets.example.com)" 8 60 3>&1 1>&2 2>&3)
  APP_EMAIL=$(whiptail --inputbox "Enter email for Let's Encrypt notices" 8 60 3>&1 1>&2 2>&3)
  set -e
  [[ -z "$APP_DOMAIN" || -z "$APP_EMAIL" ]] && msg_error "Domain and email are required."
  msg_info "Starting Yopass installation (mode: ${INSTALL_MODE})"

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
