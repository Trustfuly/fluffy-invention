#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2026 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE

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

# --- Safe Update Function ---
function update_script() {
  # Disable Proxmox Helper Scripts cleanup traps to prevent accidental container deletion
  trap - EXIT
  trap - ERR
  
  header_info
  msg_info "Searching for containers with 'yopass' tag..."
  
  # Find Container IDs safely. xargs -r prevents the 'basename' error if no files are found.
  local UPD_CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/*.conf 2>/dev/null | xargs -r -n1 basename | sed 's/\.conf$//' || true)

  if [[ -z "$UPD_CTIDS" ]]; then
    msg_error "No containers found with 'yopass' tag."
    exit 0
  fi

  for TARGET_ID in $UPD_CTIDS; do
    local STATUS=$(pct status "$TARGET_ID" 2>/dev/null | awk '{print $2}' || echo "stopped")
    
    if [[ "$STATUS" != "running" ]]; then
      msg_info "Container $TARGET_ID is $STATUS. Skipping."
      continue
    fi

    msg_info "Updating ${APP} in Container $TARGET_ID..."
    
    # Download and execute the script inside the container
    if pct exec "$TARGET_ID" -- bash -c "wget -qO /tmp/yopass-update.sh ${INSTALL_URL} && export UPDATE_ONLY=yes && bash /tmp/yopass-update.sh"; then
      msg_ok "Container $TARGET_ID updated successfully."
    else
      msg_error "Failed to update Container $TARGET_ID."
    fi
    
    # Cleanup internal temp file
    pct exec "$TARGET_ID" -- rm -f /tmp/yopass-update.sh
  done
  
  msg_ok "All update tasks completed."
  exit 0
}

# --- Main Initialization ---

# Search for existing containers before triggering the build engine
# Using -r flag for xargs to avoid "basename: missing operand"
EXISTING_CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/*.conf 2>/dev/null | xargs -r -n1 basename | sed 's/\.conf$//' || true)

if [[ -n "$EXISTING_CTIDS" ]]; then
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Update Detected" --yesno "Existing Yopass containers found ($EXISTING_CTIDS).\n\nDo you want to UPDATE them instead of creating a new one?" 12 65); then
    update_script
  fi
fi

# --- If we continue here, it is a NEW INSTALLATION ---
header_info "$APP"
base_settings
variables
color
catch_errors # This starts the cleanup trap ONLY for the new build

start
build_container

# Configure New Container Autologin
pct exec "$CTID" -- mkdir -p /etc/systemd/system/container-getty@1.service.d
pct exec "$CTID" -- bash -c "printf '[Service]\nExecStart=\nExecStart=-/sbin/agetty --autologin root --noclear tty1\n' > /etc/systemd/system/container-getty@1.service.d/autologin.conf"
pct exec "$CTID" -- passwd -d root 2>/dev/null
pct exec "$CTID" -- systemctl daemon-reload
pct exec "$CTID" -- systemctl restart container-getty@1

# Mode Selection for New Install
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
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && INSTALL_MODE='1' APP_DOMAIN='${APP_DOMAIN}' APP_EMAIL='${APP_EMAIL}' bash /tmp/yopass-install.sh"
else
  msg_info "Installing Yopass (Proxy Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && INSTALL_MODE='2' bash /tmp/yopass-install.sh"
fi

msg_ok "Completed Successfully!"  for TARGET_ID in $UPD_CTIDS; do
    local STATUS=$(pct status "$TARGET_ID" | awk '{print $2}')
    if [[ "$STATUS" != "running" ]]; then
      msg_info "Container $TARGET_ID is not running. Skipping."
      continue
    fi

    msg_info "Updating ${APP} in Container $TARGET_ID..."
    
    # Use wget to a file to avoid pipe errors, then execute
    if pct exec "$TARGET_ID" -- bash -c "wget -qO /tmp/yopass-update.sh ${INSTALL_URL} && export UPDATE_ONLY=yes && bash /tmp/yopass-update.sh"; then
      msg_ok "Container $TARGET_ID updated successfully."
    else
      msg_error "Failed to update Container $TARGET_ID."
    fi
    
    # Cleanup temp file inside container
    pct exec "$TARGET_ID" -- rm -f /tmp/yopass-update.sh
  done
  
  msg_ok "Process finished."
  exit 0
}

# --- Check for Update Mode FIRST ---
# We check for existing tags BEFORE loading the full helper environment
EXISTING_CTIDS=$(grep -lE "^tags:.*yopass" /etc/pve/lxc/*.conf | xargs -n1 basename | cut -d. -f1 || true)

if [[ -n "$EXISTING_CTIDS" ]]; then
  # Use whiptail to ask the user
  if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Update Found" --yesno "Existing Yopass containers detected. Would you like to UPDATE them?\n\n(Choosing 'No' will continue to create a NEW container)" 12 65); then
    update_script
  fi
fi

# --- If we reach here, we are doing a NEW INSTALLATION ---
header_info "$APP"
base_settings
variables
color
catch_errors # This starts the 'trap' for the NEW container only

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
  msg_info "Installing (Public Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && INSTALL_MODE='1' APP_DOMAIN='${APP_DOMAIN}' APP_EMAIL='${APP_EMAIL}' bash /tmp/yopass-install.sh"
else
  msg_info "Installing (Proxy Mode)..."
  pct exec "$CTID" -- bash -c "wget -qO /tmp/yopass-install.sh ${INSTALL_URL} && INSTALL_MODE='2' bash /tmp/yopass-install.sh"
fi

msg_ok "Completed Successfully!"
