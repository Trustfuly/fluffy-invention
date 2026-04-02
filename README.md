# Yopass – Proxmox LXC Install Script

> Install [Yopass](https://github.com/jhaals/yopass) as a native LXC container on Proxmox VE — no Docker required.  
> Built in the style of [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE).

---

## Quick Start

Run this command in your **Proxmox VE Shell**:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/ct/yopass.sh)"
```

Follow the interactive prompts (or press Enter to accept defaults).  
When finished, Yopass will be available at `https://<container-ip>`.

---

## What Gets Installed

| Component       | Source         | Details                               |
|-----------------|----------------|---------------------------------------|
| `yopass-server` | GitHub release | Binary, listens on `127.0.0.1:1337`   |
| `memcached`     | apt            | Listens on `127.0.0.1:11211`          |
| `nginx`         | apt            | Reverse proxy, ports 80 + 443         |
| `certbot`       | apt            | Optional – Let's Encrypt TLS          |

---

## Repository Structure

```
fluffy-invention/
├── ct/
│   └── yopass.sh             ← Run on the Proxmox host — creates the LXC
├── install/
│   └── yopass-install.sh     ← Runs inside the LXC — installs the app
└── README.md
```

---

## Let's Encrypt (after install)

By default the installer creates a **self-signed certificate** so Yopass starts immediately.  
To replace it with a trusted Let's Encrypt certificate, run inside the container:

```bash
bash /opt/yopass-certbot.sh
```

Requirements:
- Ports **80** and **443** must be reachable from the internet
- A DNS **A-record** must point to the container's IP address

---

## Updating

Re-run the same command from the Proxmox shell and select **Update** when prompted.  
The script will fetch the latest release from GitHub and restart the service.

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

## Manual Install (without the ct/ script)

If you already have an LXC container, you can run the install script directly inside it:

```bash
# Inside the container
curl -fsSL https://raw.githubusercontent.com/Trustfuly/fluffy-invention/main/install/yopass-install.sh | bash
```

---

## License

MIT — see [LICENSE](LICENSE)
