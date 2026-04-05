# Yopass – Proxmox LXC Install Script

> Install [Yopass](https://github.com/jhaals/yopass) as a native LXC container on Proxmox VE — no Docker required.  
> Built in the style of [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE).  
> Includes Ukrainian language support.

---

## Quick Start

Run this command in your **Proxmox VE Shell**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/ct/yopass.sh)"
```

The script will:
1. Create an LXC container with default settings
2. Ask you to choose an installation mode
3. Install and configure everything automatically

---

## Installation Modes

### Mode 1 — Public (Standalone + Certbot)
- Requires a domain name pointing to your server
- Automatically issues a **Let's Encrypt** TLS certificate
- Ports **80** and **443** must be reachable from the internet

### Mode 2 — Behind Proxy (NPM / Traefik)
- Uses a **self-signed certificate** (browser warning expected)
- TLS is handled by your reverse proxy (Nginx Proxy Manager, Traefik, etc.)
- Point your reverse proxy to `https://<container-ip>:443`

---

## Updating

Re-run the same command from the Proxmox Shell:
```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/ct/yopass.sh)"
```

If existing Yopass containers are detected, the script will automatically offer to update them instead of creating a new one.

The update will:
- Stop the Yopass service
- Replace the `yopass-server` binary
- Redeploy frontend assets from this repo
- Restart Yopass and Nginx

---

## Building a New Release

When a new version of Yopass is released, rebuild the frontend and binary with:

```bash
# Clone this repo and run the build script
git clone https://github.com/Trustfuly/fluffy-invention.git
cd fluffy-invention
bash build.sh --push
```

Requirements: `git`, `node >= 18`, `npm`, `go`

The build script will:
- Clone the latest `jhaals/yopass` source
- Add Ukrainian translation and set it as default
- Remove Russian language
- Build the frontend
- Build the `yopass-server` binary
- Commit and push `public/` and `bin/` to this repo

---

## What Gets Installed

| Component       | Source                     | Details                                    |
|-----------------|----------------------------|--------------------------------------------|
| `yopass-server` | Trustfuly/fluffy-invention | Custom binary, listens on `127.0.0.1:1337` |
| `memcached`     | apt                        | Listens on `127.0.0.1:11211`               |
| `nginx`         | apt                        | Reverse proxy, ports 80 + 443              |
| `certbot`       | apt                        | Mode 1 only – Let's Encrypt TLS            |

---

## Repository Structure

```
fluffy-invention/
├── bin/
│   └── yopass-server         ← Pre-built binary
├── ct/
│   └── yopass.sh             ← Run on the Proxmox host — creates the LXC
├── install/
│   └── yopass-install.sh     ← Runs inside the LXC — installs the app
├── public/                   ← Frontend assets (React SPA, Ukrainian UI)
│   ├── assets/
│   ├── index.html
│   └── ...
├── LICENSE                   ← MIT License
├── README.md
├── build.sh                  ← Rebuild frontend + binary from latest yopass 
└── update.sh                 ← Update existing container
```

---

## Default LXC Resources

| Setting      | Value       |
|--------------|-------------|
| OS           | Debian 12   |
| CPU          | 1 core      |
| RAM          | 256 MB      |
| Disk         | 2 GB        |
| Unprivileged | Yes         |
| Port         | 443 (HTTPS) |

---

## Container Access

| Setting  | Value                     |
|----------|---------------------------|
| Login    | `root`                    |
| Password | none (auto-login enabled) |

Auto-login is configured on `tty1` — opening the console in Proxmox UI will drop you directly into a root shell.

---

## Manual Install (without the ct/ script)

If you already have an LXC container, run the install script directly inside it:

```bash
curl -fsSL https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/install/yopass-install.sh -o /tmp/yopass-install.sh
INSTALL_MODE=2 bash /tmp/yopass-install.sh
```

For standalone mode with Certbot:

```bash
INSTALL_MODE=1 APP_DOMAIN=secrets.example.com APP_EMAIL=you@example.com bash /tmp/yopass-install.sh
```

---

## Service Management

```bash
systemctl status yopass
systemctl restart yopass
systemctl stop yopass
```

## Config Files

```
/etc/systemd/system/yopass.service
/etc/nginx/sites-available/yopass
/etc/memcached.conf
```

---

## License

MIT — see [LICENSE](LICENSE)
