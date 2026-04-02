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

# Override install URL to use our own repo instead of community-scripts
INSTALL_URL="https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/install/yopass-install.sh"

# App Output & Base Settings
header_info "$APP"
base_settings

# Core
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -f /usr/local/bin/yopass-ng ]]; then
    msg_error "No ${APP} installation found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/paepckehh/yopass-ng/releases/latest \
    | grep "tag_name" | awk '{print substr($2, 3, length($2)-4)}')

  if [[ ! -f /opt/yopass_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/yopass_version.txt)" ]]; then
    msg_info "Updating ${APP} to v${RELEASE}"
    ARCH="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"
    curl -fsSL "https://github.com/paepckehh/yopass-ng/releases/download/v${RELEASE}/yopass-ng-linux_${ARCH}_${RELEASE}.tar.gz" \
      -o /tmp/yopass-ng.tar.gz
    systemctl stop yopass
    tar -xzf /tmp/yopass-ng.tar.gz -C /tmp/
    mv /tmp/yopass-ng /usr/local/bin/yopass-ng
    chmod +x /usr/local/bin/yopass-ng
    rm -f /tmp/yopass-ng.tar.gz
    echo "${RELEASE}" >/opt/yopass_version.txt
    systemctl start yopass
    msg_ok "Updated ${APP} to v${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at v${RELEASE}"
  fi
  exit
}

start
build_container

# Run our own install script instead of the community-scripts one
msg_info "Running Yopass installer"
lxc-attach -n "$CTID" -- bash -c "$(curl -fsSL ${INSTALL_URL})"

description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
