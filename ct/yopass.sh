#!/usr/bin/env bash

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

# URL of the main installation script
INSTALL_URL="https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/install/yopass-install.sh"

# --- Function to update existing containers ---
function update_script() {
  # Clear any traps to prevent accidental container deletion by build.func
  trap - EXIT
  trap - ERR
  
  echo -e "\n  [INFO] Starting Update Process..."
  
  # Find Container IDs with the 'yopass' tag safely
  # 1. Search for config files containing the tag
  # 2. Use awk to extract the ID from the file path
  local UPD_CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/[0-9]*.conf 2>/dev/null | awk -F'/' '{print $NF}' | sed 's/\.conf//' || true)

  if [[ -z "$UPD_CTIDS" ]]; then
    echo -e "  [ERROR] No containers found with 'yopass' tag."
    exit 0
  fi

  for TARGET_ID in $UPD_CTIDS; do
    local STATUS=$(pct status "$TARGET_ID" 2>/dev/null | awk '{print $2}' || echo "stopped")
    
    if [[ "$STATUS" != "running" ]]; then
      echo -e "  [INFO] Container $TARGET_ID is $STATUS. Skipping."
      continue
    fi

    echo -e "  [INFO] Updating ${APP} in Container $TARGET_ID..."
    
    # Download the script and run it with UPDATE_ONLY flag
    # We use a temporary file inside the container for stability
    if pct exec "$TARGET_ID" -- bash -c "wget -qO /tmp/yopass-update.sh ${INSTALL_URL} && export UPDATE_ONLY=yes && bash /tmp/yopass-update.sh"; then
      echo -e "  [OK] Container $TARGET_ID updated successfully."
    else
      echo -e "  [ERROR] Failed to update Container $TARGET_ID."
    fi
    
    # Clean up temp file
    pct exec "$TARGET_ID" -- rm -f /tmp/yopass-update.sh
  done
  
  echo -e "  [OK] Update process finished.\n"
  exit 0
}

# --- Check for Updates BEFORE loading build.func engine ---

# Search for existing containers by tag
# We do this before sourcing build.func to avoid initializing the cleanup trap
EXISTING_CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/[0-9]*.conf 2>/dev/null | awk -F'/' '{print $NF}' | sed 's/\.conf//' || true)

if [[ -n "$EXISTING_CTIDS" ]]; then
  # Use whiptail to ask for update. We call it directly to avoid build.func dependency at this stage.
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Update Detected" --yesno "Existing Yopass containers found: $EXISTING_CTIDS\n\nDo you want to UPDATE them instead of creating a new one?" 12 65); then
    update_script
  fi
fi

# --- If we continue here, we are performing a NEW INSTALLATION ---

# Load Proxmox VE Helper Scripts functions
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

header_info "$APP"
base_settings
variables
color
catch_errors # This starts the cleanup trap ONLY for the new build

start
build_container

# Configure New Container Autologin & Access
pct exec "$CTID" -- mkdir -p /etc/systemd/system/container-getty@1.service.d
pct exec "$CTID" -- bash -c "printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear tty1\n' > /etc/systemd/system/container-getty@1.service.d/autologin.conf"
pct exec "$CTID" -- passwd -d root 2>/dev/null
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart container-getty@1

# Mode Selection for New Installation
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

# Run final provisioning inside the container
if [[ "$INSTALL_MODE" == "1" ]]; then
  set +e
  APP_DOMAIN=$(whiptail --inputbox "Enter domain (e.g. secrets.example.com)" 8 60 3>&1 1>&2 2>&3)
  APP_EMAIL=$(whiptail --inputbox "Enter email for Let's Encrypt notices" 8 60 3>&1 1>&2 2>&3)
  set -e
  msg_info "Installing Yopass (Public Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && INSTALL_MODE='1' APP_DOMAIN='${APP_DOMAIN}' APP_EMAIL='${APP_EMAIL}' bash /tmp/yopass-install.sh"
else
  msg_info "Installing Yopass (Proxy Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && INSTALL_MODE='2' bash /tmp/yopass-install.sh"
fi

msg_ok "Completed Successfully!"
