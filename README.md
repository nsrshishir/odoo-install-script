# Odoo Installation and Management Scripts

This repository provides a collection of comprehensive shell scripts to automate the installation, configuration, and maintenance of Odoo on Ubuntu servers. These scripts follow official Odoo recommendations and best practices to ensure a stable and production-ready environment.

## 🚀 Features

- **Automated Installation**: One-click setup for multiple Odoo versions (14.0 to 19.0).
- **Dependency Management**: Installs all required Python libraries, PostgreSQL, Wkhtmltopdf, and Node.js dependencies.
- **Reverse Proxy**: Optional automated Nginx setup with SSL/HTTPS support via Certbot.
- **Multiple Instances**: Support for running multiple Odoo instances on the same server using different ports.
- **Database Backups**: Robust scripts for backing up PostgreSQL databases and Odoo filestores with remote sync capabilities.
- **System Monitoring**: Includes a basic system benchmark script.

## 🛠 Usage

### 1. Install Odoo

To install Odoo 19.0 on Ubuntu 24.04:

```bash
# Move to the opt directory
cd /opt/

# Download the script
sudo wget https://raw.githubusercontent.com/nsrshishir/odoo-install-script/main/odoo19_ubuntu_24.04.sh

# Make it executable
sudo chmod +x odoo19_ubuntu_24.04.sh

# Run the script
sudo ./odoo19_ubuntu_24.04.sh
```

**Customization**: Before running, you can edit the script to change configuration variables like `OE_USER`, `OE_PORT`, `IS_ENTERPRISE`, etc.

### 2. Database Backups

The `pg_backup_script.sh` handles automated backups of your Odoo data.

```bash
# Edit the configuration section in the script
sudo nano pg_backup_script.sh

# Run the backup manually or add to crontab
sudo ./pg_backup_script.sh
```

## 📂 Available Scripts

| Script Name | Purpose | Target OS |
| :--- | :--- | :--- |
| `odoo19_ubuntu_24.04.sh` | Install Odoo 19.0 (Community/Enterprise) | Ubuntu 24.04 |
| `odoo18_ubuntu_24.04.sh` | Install Odoo 18.0 (Community/Enterprise) | Ubuntu 24.04 |
| `odoo17_ubuntu_24.04.sh` | Install Odoo 17.0 (Community/Enterprise) | Ubuntu 24.04 |
| `yenthee_odoo17C_U22install.sh` | Yenthe's Odoo 17 Community installer | Ubuntu 22.04 |
| `pg_backup_script.sh` | PostgreSQL & Filestore backup script | General Linux |
| `pg_backup_script_zip.sh` | Zipped version of the backup script | General Linux |
| `system_benchmark.sh` | Simple system performance benchmark | General Linux |

## ⚙️ Configuration

The installation scripts contain a configuration section at the top. You can customize the following:

- `OE_USER`: System user for Odoo.
- `OE_PORT`: The port Odoo will listen on (default: 8069).
- `IS_ENTERPRISE`: Set to `True` to install Enterprise addons (requires Odoo Enterprise source access).
- `INSTALL_NGINX`: Set to `True` to install and configure Nginx as a reverse proxy.
- `ENABLE_SSL`: Enable SSL/HTTPS via Let's Encrypt (requires a domain name).

## ⚠️ Important Notes

- **Sudo Privileges**: All scripts must be run with `sudo` or as the `root` user.
- **Fresh Install**: It is highly recommended to run these scripts on a fresh Ubuntu installation.
- **Production Use**: While these scripts are robust, always review the configuration and test on a staging environment before using in production.

## 👤 Author

- **Yenthe Van Ginneken** (Original Author)
- **Niaj Shahriar Shishir** (Updated and Maintained)

## 📄 License

This project is open-source. Please refer to the script headers for specific licensing information where applicable.
