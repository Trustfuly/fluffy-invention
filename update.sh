#!/usr/bin/env bash

# Copyright (c) 2026 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE

set -euo pipefail

GITHUB_USER="Trustfuly"
REPO="fluffy-invention"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO}/main"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

msg_info()  { echo -e "  ${YELLOW}[INFO]${NC}  $1"; }
msg_ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
msg_error() { echo -e "  ${RED}[ERROR]${NC} $1"; exit 1; }

[[ "$EUID" -ne 0 ]] && msg_error "Please run as root."
[[ ! -f /usr/local/bin/yopass-server ]] && msg_error "Yopass is not installed in this container."

echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║              Yopass – Update                             ║"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""

# ─── Update binary ───────────────────────────────────────────────────────────
msg_info "Stopping Yopass service"
systemctl stop yopass
msg_ok "Yopass stopped"

msg_info "Updating Yopass binary"
wget -qO /usr/local/bin/yopass-server "${RAW_URL}/bin/yopass-server"
chmod +x /usr/local/bin/yopass-server
msg_ok "Binary updated"

# ─── Update frontend assets ──────────────────────────────────────────────────
msg_info "Updating frontend assets"
mkdir -p /tmp/yopass_repo
curl -fsSL "https://github.com/${GITHUB_USER}/${REPO}/archive/refs/heads/main.tar.gz" \
  | tar -xz -C /tmp/yopass_repo --strip-components=1
cp -r /tmp/yopass_repo/public/* /var/www/yopass/
rm -rf /tmp/yopass_repo
chown -R www-data:www-data /var/www/yopass
msg_ok "Frontend assets updated"

# ─── Restart service ─────────────────────────────────────────────────────────
msg_info "Starting Yopass service"
systemctl start yopass
msg_ok "Yopass started"

IP=$(hostname -I | awk '{print $1}')
echo ""
echo "  ╔══════════════════════════════════════════════════════════╗"
echo "  ║          ✅  Yopass updated successfully!                 ║"
echo "  ╠══════════════════════════════════════════════════════════╣"
printf "  ║   🌐  URL : https://%-38s ║\n" "${IP}"
echo "  ╚══════════════════════════════════════════════════════════╝"
echo ""
