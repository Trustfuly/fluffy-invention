#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE

# --- App Settings ---
APP="Yopass"
var_tags="yopass;security;secrets"
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

# --- Function to update existing containers with Styled UI ---
function update_script() {
  # Disable Proxmox Helper Scripts cleanup traps for safety
  trap - EXIT
  trap - ERR
  
  header_info
  msg_info "Searching for containers with 'yopass' tag..."
  
  # Find Container IDs safely using awk
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

    # ─── Execute Update Inside Container (Styled & Robust) ──────────────────
    pct exec "$CTID" -- bash -c "
        set -euo pipefail
        
        # Internal colors
        G='\033[0;32m'
        Y='\033[1;33m'
        R='\033[0;31m'
        NC='\033[0m'

        echo -e \"  \${Y}[INFO]\${NC} Checking current installation...\"
        if [[ ! -f /usr/local/bin/yopass-server ]]; then
            echo -e \"  \${R}[ERROR]\${NC} Yopass binary not found. Is it installed correctly?\"
            exit 1
        fi

        echo \"\"
        echo \"  ╔══════════════════════════════════════════════════════════╗\"
        echo \"  ║              Yopass – Update ($CTID)                     ║\"
        echo \"  ╚══════════════════════════════════════════════════════════╝\"
        echo \"\"

        echo -e \"  \${Y}[1/4]\${NC} Stopping service & clearing old assets...\"
        systemctl stop yopass || true
        # Deep clean to prevent MIME type errors (TypeError: text/html)
        rm -rf /var/www/yopass/*

        echo -e \"  \${Y}[2/4]\${NC} Updating Yopass binary...\"
        wget -qO /usr/local/bin/yopass-server \"${RAW_URL}/bin/yopass-server\"
        chmod +x /usr/local/bin/yopass-server

        echo -e \"  \${Y}[3/4]\${NC} Deploying new frontend assets...\"
        mkdir -p /tmp/yopass_update
        curl -fsSL \"https://github.com/${GITHUB_USER}/${REPO}/archive/refs/heads/main.tar.gz\" \
          | tar -xz -C /tmp/yopass_update --strip-components=1
        
        # Copy everything from public to web root
        cp -a /tmp/yopass_update/public/. /var/www/yopass/
        
        rm -rf /tmp/yopass_update
        chown -R www-data:www-data /var/www/yopass
        chmod -R 755 /var/www/yopass

        echo -e \"  \${Y}[4/4]\${NC} Restarting services...\"
        systemctl start yopass
        systemctl restart nginx

        IP=\$(hostname -I | awk '{print \$1}')
        echo \"\"
        echo \"  ╔══════════════════════════════════════════════════════════╗\"
        echo \"  ║          ✅  Yopass updated successfully!                 ║\"
        echo \"  ╠══════════════════════════════════════════════════════════╣\"
        printf \"  ║   🌐  URL : https://%-38s ║\\n\" \"\${IP}\"
        echo \"  ╚══════════════════════════════════════════════════════════╝\"
        echo \"\"
    "
  done
  
  msg_ok "All update tasks completed."
  exit 0
}

# --- Check for existing containers before starting a new build ---
EXISTING_CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/[0-9]*.conf 2>/dev/null | awk -F'/' '{print $NF}' | sed 's/\.conf//' || true)

if [[ -n "$EXISTING_CTIDS" ]]; then
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Update Detected" --yesno "Existing Yopass containers found: $EXISTING_CTIDS\n\nDo you want to UPDATE them instead of creating a new one?" 12 65); then
    update_script
  fi
fi

# --- NEW INSTALLATION SECTION ---
header_info "$APP"
base_settings
variables
color
catch_errors

start
build_container

# Configure New Container
pct exec "$CTID" -- mkdir -p /etc/systemd/system/container-getty@1.service.d
pct exec "$CTID" -- bash -c "printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear tty1\n' > /etc/systemd/system/container-getty@1.service.d/autologin.conf"
pct exec "$CTID" -- passwd -d root 2>/dev/null
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart container-getty@1

# Mode Selection
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

if [[ "$INSTALL_MODE" == "1" ]]; then
  set +e
  APP_DOMAIN=$(whiptail --inputbox "Enter domain" 8 60 3>&1 1>&2 2>&3)
  APP_EMAIL=$(whiptail --inputbox "Enter email" 8 60 3>&1 1>&2 2>&3)
  set -e
  msg_info "Installing Yopass (Public Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && export UPDATE_ONLY=no && INSTALL_MODE='1' APP_DOMAIN='${APP_DOMAIN}' APP_EMAIL='${APP_EMAIL}' bash /tmp/yopass-install.sh"
else
  msg_info "Installing Yopass (Proxy Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && export UPDATE_ONLY=no && INSTALL_MODE='2' bash /tmp/yopass-install.sh"
fi

msg_ok "Completed Successfully!"
