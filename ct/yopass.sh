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

# Main installation script on GitHub
INSTALL_URL="https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/install/yopass-install.sh"

header_info "$APP"

# --- Update Function ---
function update_script() {
  header_info
  msg_info "Searching for containers with 'yopass' tag..."
  
  # Search for Container IDs based on the tag
  CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/*.conf | xargs -n1 basename | cut -d. -f1 || true)

  if [[ -z "$CTIDS" ]]; then
    msg_error "No containers found with the required tag!"
    exit 1
  fi

  for CTID in $CTIDS; do
    STATUS=$(pct status "$CTID" | awk '{print $2}')
    if [[ "$STATUS" != "running" ]]; then
      msg_info "Container $CTID is not running. Skipping."
      continue
    fi

    msg_info "Updating ${APP} in Container $CTID..."
    
    # We download the script to a file first to avoid 'curl (23)' and pipe issues.
    # We export UPDATE_ONLY=yes to skip interactive prompts inside the install script.
    pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-update.sh ${INSTALL_URL} && export UPDATE_ONLY=yes && bash /tmp/yopass-update.sh"
    
    # Clean up the temporary script
    pct exec "$CTID" -- rm -f /tmp/yopass-update.sh
    
    msg_ok "Container $CTID updated successfully."
  done
  
  msg_ok "All updates completed."
  exit
}

# --- Main Logic ---

# Check if any containers with the tag already exist
CTIDS_EXIST=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/*.conf | xargs -n1 basename | cut -d. -f1 || true)
if [[ -n "$CTIDS_EXIST" ]]; then
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Update Detected" --yesno "Existing Yopass containers found. Would you like to UPDATE them instead of creating a new one?" 10 60); then
    update_script
  fi
fi

# Standard Proxmox Helper Build Process
base_settings
variables
color
catch_errors

start
build_container

# Configure Container Access
pct exec "$CTID" -- mkdir -p /etc/systemd/system/container-getty@1.service.d
pct exec "$CTID" -- bash -c "printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear tty1\n' > /etc/systemd/system/container-getty@1.service.d/autologin.conf"
pct exec "$CTID" -- passwd -d root 2>/dev/null
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart container-getty@1

# Selection of Installation Mode (on Host Terminal)
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

# Run the Installation inside the newly created container
if [[ "$INSTALL_MODE" == "1" ]]; then
  set +e
  APP_DOMAIN=$(whiptail --inputbox "Enter domain (e.g. secrets.example.com)" 8 60 3>&1 1>&2 2>&3)
  APP_EMAIL=$(whiptail --inputbox "Enter email for Let's Encrypt notices" 8 60 3>&1 1>&2 2>&3)
  set -e
  [[ -z "$APP_DOMAIN" || -z "$APP_EMAIL" ]] && msg_error "Domain and email are required."
  
  msg_info "Installing Yopass (Public Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && INSTALL_MODE='${INSTALL_MODE}' APP_DOMAIN='${APP_DOMAIN}' APP_EMAIL='${APP_EMAIL}' bash /tmp/yopass-install.sh"
else
  msg_info "Installing Yopass (Proxy Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && INSTALL_MODE='${INSTALL_MODE}' bash /tmp/yopass-install.sh"
fi

msg_ok "Completed Successfully!\n"
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
  for CTID in $CTIDS; do
    STATUS=$(pct status "$CTID" | awk '{print $2}')
    if [[ "$STATUS" != "running" ]]; then
      msg_info "Container $CTID is not running. Skipping."
      continue
    fi

    msg_info "Updating ${APP} in Container $CTID..."
    # Execute the internal install script inside the container
    # We pass a flag 'UPDATE_ONLY=yes' so your yopass-install.sh knows it's an update
    pct exec "$CTID" -- bash -c "curl -fsSL ${INSTALL_URL} | UPDATE_ONLY=yes bash"
    msg_ok "Container $CTID updated."
  done
  
  msg_ok "Update process completed."
  exit
}

# ─── Main Logic ─────────────────────────────────────────────────────────────

# Check if we should update existing or build new
# If containers with tag exist, we ask the user
CTIDS_EXIST=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/*.conf | xargs -n1 basename | cut -d. -f1 || true)
if [[ -n "$CTIDS_EXIST" ]]; then
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Existing Containers Found" --yesno "Existing Yopass containers detected. Do you want to UPDATE them instead of creating a new one?" 10 60); then
    update_script
  fi
fi

base_settings
variables
color
catch_errors

# Start Proxmox LXC Build Process
start
build_container

# Configure Container Autologin & Terminal
pct exec "$CTID" -- mkdir -p /etc/systemd/system/container-getty@1.service.d
pct exec "$CTID" -- bash -c "printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear tty1\n' > /etc/systemd/system/container-getty@1.service.d/autologin.conf"
pct exec "$CTID" -- passwd -d root 2>/dev/null
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart container-getty@1

# Ask install mode on the HOST
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

# Provisioning logic
if [[ "$INSTALL_MODE" == "1" ]]; then
  set +e
  APP_DOMAIN=$(whiptail --inputbox "Enter domain (e.g. secrets.example.com)" 8 60 3>&1 1>&2 2>&3)
  APP_EMAIL=$(whiptail --inputbox "Enter email for Let's Encrypt notices" 8 60 3>&1 1>&2 2>&3)
  set -e
  [[ -z "$APP_DOMAIN" || -z "$APP_EMAIL" ]] && msg_error "Domain and email are required."
  msg_info "Starting Yopass installation (mode: ${INSTALL_MODE})"

  pct exec "$CTID" -- bash -c "
    curl -fsSL '${INSTALL_URL}' -o /tmp/yopass-install.sh
    INSTALL_MODE='${INSTALL_MODE}' APP_DOMAIN='${APP_DOMAIN}' APP_EMAIL='${APP_EMAIL}' bash /tmp/yopass-install.sh
  "
else
  msg_info "Starting Yopass installation (mode: Proxy)"
  pct exec "$CTID" -- bash -c "
    curl -fsSL '${INSTALL_URL}' -o /tmp/yopass-install.sh
    INSTALL_MODE='${INSTALL_MODE}' bash /tmp/yopass-install.sh
  "
fi

msg_ok "Completed Successfully!\n"
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"start
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
