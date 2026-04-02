#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2024 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE
# Source: https://github.com/paepckehh/yopass-ng

# App Default Values
APP="Yopass"
var_tags="security;secrets"
var_cpu="1"
var_ram="256"
var_disk="2"
var_os="debian"
var_version="12"
var_unprivileged="1"

# URL to your NEW install script
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
    msg_info "Update logic should be handled by re-running the installer."
    exit
}

start
build_container

msg_info "Starting Yopass installation inside the container..."
# Using -t for interactive menu support
lxc-attach -t 0 -n "$CTID" -- bash -c "wget -qO /tmp/install.sh ${INSTALL_URL} && bash /tmp/install.sh"

msg_ok "Completed Successfully!\n"
echo -e "${GN}${APP} setup has been successfully initialized!${CL}"
