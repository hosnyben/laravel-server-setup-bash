# Laravel Server Setup Bash

This Bash script automates the deployment of **Laravel**, **React**, **Meilisearch**, and **phpMyAdmin** applications on a fresh Ubuntu server.  
It configures essential services like **NGINX**, **PHP-FPM**, **MySQL**, **Supervisor**, **Certbot SSL**, **UFW**, and **Redis**, and sets up secure deployments with dedicated users and SSH keys.

---
## Demo video
A real demo of the script usage. [Click here](https://drive.google.com/file/d/1HKQ2rhujpHq9mn9MvBLK74uiD99tYxva/view?usp=sharing)

## Features

- 📦 Auto-installs **NGINX**, **PHP** (custom version), **MySQL**, **Redis**, **Supervisor**, **Certbot**, **Node.js**, and more.
- 🌐 Configures **NGINX** for Laravel, React, and Meilisearch apps.
- 🔐 Automatically issues **SSL certificates** with Let's Encrypt (Certbot).
- 🚀 Supports **automatic cloning** of Git repositories.
- 📈 Configures **Laravel queue workers** with Supervisor.
- 📂 Installs and configures **phpMyAdmin** if needed.
- 🔑 Secures NGINX paths with HTTP authentication (e.g., `/pulse`).
- 📜 Generates a **deployment summary file** with credentials and URLs.
- 🔄 Supports **interactive** and **automatic** modes (`--auto`).

---

## Requirements

- Ubuntu server **(tested on Ubuntu 20.04/22.04/24.04)**
- Root access (`sudo` privileges)
- A domain/subdomain pointing to your server's public IP

---

## Usage

### 1. Prepare Your Server

Make sure your domain/subdomain DNS points to your server **before** running the script.  
You can check using [https://dnschecker.org](https://dnschecker.org).

### 2. Upload the Script

```bash
scp setup-clean.sh root@your_server_ip:/root/setup-clean.sh
```

### 3. Enable script execution using CHMOD

SSH into your server and run:

```bash
chmod +x bash setup.sh
```

Then run the script:

```bash
./setup.sh
```

The script will:

- Update repositories
- Install system packages
- Ask for the PHP version you want **(8.1, 8.2, etc.)**
- Create a secure deployment user with SSH key
- Guide you through setting up apps

## Key notes

### Supported Apps

- Laravel (PHP backend with Redis and queue workers)
- React (Static frontend)
- Meilisearch (Search server)
- phpMyAdmin (MySQL management UI)

### Important Notes

- **SSL:** If you don’t want to automatically install SSL (Certbot), the script allows skipping it.
- **Ports:** The script checks if the desired ports are already in use.
- **Databases:** You can either import an SQL dump or create new empty databases.
- **Supervisor:** Laravel queue workers are managed automatically using Supervisor if selected.

### Files generated

- /etc/nginx/sites-available/{domain}
- /etc/supervisor/conf.d/{domain}_worker.conf
- /home/{deployment_user}/server-setup-summary.txt — credentials and app URLs
- /etc/nginx/.htpasswd — for secured paths like /pulse
- SSH key for deployment user in /home/{deployment_user}/.ssh/

### Example of summary file

```txt
[app.example.com] Laravel App
MySQL User: appuser
MySQL Password: random_generated_password
App URL: https://app.example.com

🔐 Meilisearch master key: abcdef1234567890
phpMyAdmin: https://pma.example.com
```

### Troubleshooting

- **Clone Failed:** If Git clone fails, you’ll be prompted to re-enter the repo URL.
- **SSL Error:** If Certbot fails, check your domain DNS settings and rerun Certbot manually.
- **Supervisor not starting:** Verify /etc/supervisor/supervisord.conf or restart Supervisor service.

### Tips

- **Use a strong deployment server** (minimum 2 vCPU / 4GB RAM recommended).
- **Secure** your server with regular updates (apt update && apt upgrade).
- Always **backup** your summary credentials file: /home/{deployment_user}/server-setup-summary.txt.
- For **Meilisearch**, expose it only internally unless you configure proper access controls.

## Author
![Housni BENABID](https://hosnyben.me/mail-signature/logo_black.png "Housni BENABID")
--
Made with ❤️ by [Hosny BEN](https://hosnyben.me "Housni BENABID")
