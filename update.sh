#!/usr/bin/env bash

# Copyright (c) 2026 Trustfuly
# Author: Trustfuly (https://github.com/Trustfuly)
# License: MIT | https://github.com/Trustfuly/fluffy-invention/raw/main/LICENSE

set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────
GITHUB_USER="Trustfuly"
REPO="fluffy-invention"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${REPO}/main"
TAG_NAME="yopass"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

msg_info()  { echo -e "  ${YELLOW}[INFO]${NC}  $1"; }
msg_ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
msg_error() { echo -e "  ${RED}[ERROR]${NC} $1"; }

# ─── Pre-flight Checks ──────────────────────────────────────────────────────
[[ "$EUID" -ne 0 ]] && { echo "Please run as root (on Proxmox host)."; exit 1; }

if ! command -v pct &> /dev/null; then
    msg_error "This script must be run on a Proxmox host (pct command not found)."
    exit 1
fi

# ─── Find Containers ────────────────────────────────────────────────────────
msg_info "Searching for containers with tag '${TAG_NAME}'..."

# Find all CTIDs that have the specified tag in their configuration
CTIDS=$(grep -lE "^tags:.*${TAG_NAME}" /etc/pve/lxc/*.conf | xargs -n1 basename | cut -d. -f1 || true)

if [ -z "$CTIDS" ]; then
    msg_error "No containers found with tag '${TAG_NAME}'."
    exit 0
fi

for CTID in $CTIDS; do
    NODE_STATUS=$(pct status "$CTID" | awk '{print $2}')
    
    echo -e "\n${YELLOW}Targeting Container ID: $CTID ($NODE_STATUS)${NC}"
    
    if [ "$NODE_STATUS" != "running" ]; then
        msg_info "Container $CTID is not running. Skipping."
        continue
    fi

    # ─── Execute Update Inside Container ────────────────────────────────────
    pct exec "$CTID" -- bash -c "
        set -euo pipefail
        
        # Internal colors
        G='\033[0;32m'
        Y='\033[1;33m'
        R='\033[0;31m'
        NC='\033[0m'

        echo -e \"  \${Y}[INFO]\${NC} Checking installation...\"
        if [[ ! -f /usr/local/bin/yopass-server ]]; then
            echo -e \"  \${R}[ERROR]\${NC} Yopass is not installed in this container (/usr/local/bin/yopass-server not found).\"
            exit 1
        fi

        echo \"\"
        echo \"  ╔══════════════════════════════════════════════════════════╗\"
        echo \"  ║              Yopass – Update ($CTID)                     ║\"
        echo \"  ╚══════════════════════════════════════════════════════════╝\"
        echo \"\"

        echo -e \"  \${Y}[INFO]\${NC} Stopping Yopass service\"
        systemctl stop yopass

        echo -e \"  \${Y}[INFO]\${NC} Updating Yopass binary\"
        wget -qO /usr/local/bin/yopass-server \"${RAW_URL}/bin/yopass-server\"
        chmod +x /usr/local/bin/yopass-server

        echo -e \"  \${Y}[INFO]\${NC} Updating frontend assets\"
        mkdir -p /tmp/yopass_repo
        curl -fsSL \"https://github.com/${GITHUB_USER}/${REPO}/archive/refs/heads/main.tar.gz\" \
          | tar -xz -C /tmp/yopass_repo --strip-components=1
        
        rm -rf /var/www/yopass/assets/*
        cp -r /tmp/yopass_repo/public/* /var/www/yopass/
        rm -rf /tmp/yopass_repo
        chown -R www-data:www-data /var/www/yopass

        echo -e \"  \${Y}[INFO]\${NC} Starting Yopass service\"
        systemctl start yopass

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

msg_ok "All tagged containers have been processed."
