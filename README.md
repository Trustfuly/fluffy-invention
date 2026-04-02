# Yopass – Proxmox LXC Install Script

Скрипт у стилі [community-scripts/ProxmoxVE](https://github.com/community-scripts/ProxmoxVE)
для розгортання [Yopass](https://github.com/jhaals/yopass) в LXC-контейнері на Proxmox.

## Структура файлів

```
ct/yopass.sh              ← запускається на хості Proxmox (створює LXC)
install/yopass-install.sh ← запускається всередині LXC (встановлює додаток)
```

## Встановлення

Запустити в Proxmox Shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/YOUR_REPO/main/ct/yopass.sh)"
```

## Що встановлюється

| Компонент       | Версія        | Деталь                             |
|-----------------|---------------|------------------------------------|
| yopass-server   | latest GitHub | бінарник, слухає 127.0.0.1:1337    |
| memcached       | apt           | слухає 127.0.0.1:11211             |
| nginx           | apt           | реверс-проксі, порти 80 + 443      |
| certbot         | apt           | опціонально, Let's Encrypt         |

## Let's Encrypt (після встановлення)

```bash
bash /opt/yopass-certbot.sh
```

Потребує:
- DNS A-запис, що вказує на IP контейнера
- Відкриті порти 80 та 443 ззовні

## Оновлення

Повторний запуск `ct/yopass.sh` → вибрати "Update"

## Дефолтні ресурси LXC

- OS: Debian 12
- CPU: 1 core
- RAM: 256 MB
- Disk: 2 GB
- Unprivileged: так
