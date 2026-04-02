#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/misc/build.func)

# Copyright (c) 2024 community-scripts ORG
# Author: community
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
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

  if [[ ! -f /usr/local/bin/yopass-server ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  RELEASE=$(curl -fsSL https://api.github.com/repos/jhaals/yopass/releases/latest | grep "tag_name" | awk '{print substr($2, 2, length($2)-3)}')
  if [[ ! -f /opt/yopass_version.txt ]] || [[ "${RELEASE}" != "$(cat /opt/yopass_version.txt)" ]]; then
    msg_info "Updating ${APP} to ${RELEASE}"

    ARCH="amd64"
    [[ "$(uname -m)" == "aarch64" ]] && ARCH="arm64"

    curl -fsSL "https://github.com/jhaals/yopass/releases/download/${RELEASE}/yopass-server_linux_${ARCH}.tar.gz" \
      -o /tmp/yopass-server.tar.gz
    systemctl stop yopass
    tar -xzf /tmp/yopass-server.tar.gz -C /tmp/
    mv /tmp/yopass-server /usr/local/bin/yopass-server
    chmod +x /usr/local/bin/yopass-server
    rm -f /tmp/yopass-server.tar.gz
    echo "${RELEASE}" >/opt/yopass_version.txt
    systemctl start yopass
    msg_ok "Updated ${APP} to ${RELEASE}"
  else
    msg_ok "No update required. ${APP} is already at ${RELEASE}"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}https://${IP}${CL}"
