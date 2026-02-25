# Odoo Database Restore Scripts

This directory contains scripts for automated Odoo database restoration from Production to Staging server.

## Files

| File | Description |
|------|-------------|
| `odoo_db_restore.sh` | Main restoration script (run on Staging server) |
| `setup_ssh_keys.sh` | Helper script to setup SSH key authentication |
| `pg_backup_dir_format.sh` | Production backup script (run on Production server) |
| `pg_backup_script.sh` | Alternative backup script (zip format) |

## Quick Start

### 1. Setup SSH Keys (First Time Only)

On the **Staging server**, run:

```bash
# Copy scripts to staging server
scp odoo_db_restore.sh setup_ssh_keys.sh root@3.0.60.133:/opt/

# SSH to staging server
ssh root@3.0.60.133

# Make scripts executable
chmod +x /opt/odoo_db_restore.sh /opt/setup_ssh_keys.sh

# Setup SSH keys
/opt/setup_ssh_keys.sh
```

### 2. Configure the Script

Edit `/opt/odoo_db_restore.sh` and update the configuration variables:

```bash
# --- Production Server Settings ---
PROD_HOST="175.41.161.8"              # Production server IP
PROD_USER="root"                       # Production SSH user
PROD_SSH_KEY="/root/.ssh/id_rsa"       # SSH key path
PROD_DB_NAME="my_odoo_db"              # Production database name

# --- Staging Server Settings ---
STAGING_DB_USER="odoo"                 # PostgreSQL user on staging
STAGING_DB_NAME="odoo_staging"         # Target database name
STAGING_FILESTORE_ROOT="/odoo/.local/share/Odoo/filestore"
STAGING_WEB_URL="http://staging.example.com"
```

### 3. Run the Restoration

```bash
# Full restore (trigger backup on production, transfer, restore)
/opt/odoo_db_restore.sh

# Use existing backup (skip production backup)
/opt/odoo_db_restore.sh --skip-backup --backup-dir /opt/db_backups/my_odoo_db_backup_2026_02_25_081206

# Restore to different database name
/opt/odoo_db_restore.sh --db-name test_restore

# Don't drop existing database (will fail if DB exists)
/opt/odoo_db_restore.sh --no-drop
```

## Configuration Reference

### Production Server Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `PROD_HOST` | Production server IP/hostname | `175.41.161.8` |
| `PROD_USER` | SSH user for production | `root` |
| `PROD_SSH_PORT` | SSH port | `22` |
| `PROD_SSH_KEY` | Path to SSH private key | `/root/.ssh/id_rsa` |
| `PROD_BACKUP_SCRIPT` | Path to backup script on production | `/opt/pg_backup_dir_format.sh` |
| `PROD_DB_NAME` | Database name on production | `my_odoo_db` |
| `PROD_BACKUP_ROOT` | Backup directory on production | `/opt/db_backups` |

### Staging Server Settings

| Variable | Description | Default |
|----------|-------------|---------|
| `STAGING_DB_USER` | PostgreSQL user | `odoo` |
| `STAGING_DB_HOST` | PostgreSQL host | `localhost` |
| `STAGING_DB_PORT` | PostgreSQL port | `5432` |
| `STAGING_DB_NAME` | Target database name | `odoo_staging` |
| `STAGING_FILESTORE_ROOT` | Filestore parent directory | `/odoo/.local/share/Odoo/filestore` |
| `LOCAL_BACKUP_ROOT` | Local backup storage | `/opt/db_backups` |
| `LOG_FILE` | Log file path | `/var/log/odoo_db_restore.log` |
| `KEEP_BACKUP_DAYS` | Days to keep backups | `7` |

### Restore Options

| Variable | Description | Default |
|----------|-------------|---------|
| `DROP_EXISTING_DB` | Drop existing database before restore | `true` |
| `RESTORE_JOBS` | Parallel jobs for pg_restore | `4` |
| `ODOO_SERVICE` | Odoo service name (to stop/start) | `odoo` |
| `STAGING_WEB_URL` | Web URL for staging | `http://localhost:8069` |

### Post-Restore Actions

| Variable | Description | Default |
|----------|-------------|---------|
| `DISABLE_MAIL_SERVERS` | Disable outgoing mail servers | `true` |
| `DEACTIVATE_CRONS` | Deactivate all cron jobs | `true` |
| `CLEAR_ATTACHMENTS` | Clear attachments (except views/menus) | `false` |

## Post-Restore Actions

The script automatically performs these actions after database restoration:

### 1. Disable Mail Servers
```sql
UPDATE ir_mail_server SET active = false, smtp_host = 'localhost', smtp_port = 25;
```

### 2. Deactivate Cron Jobs
```sql
UPDATE ir_cron SET active = false;
```

### 3. Update web.base.url
```sql
UPDATE ir_config_parameter SET value = 'http://staging.example.com' WHERE key = 'web.base.url';
```

### 4. Update database.create_date
```sql
UPDATE ir_config_parameter SET value = NOW()::text WHERE key = 'database.create_date';
```

### 5. Remove Enterprise Keys
```sql
DELETE FROM ir_config_parameter WHERE key IN (
    'database.enterprise_code',
    'database.expiration_date',
    'database.expiration_reason'
);
```

### 6. Regenerate database.secret (UUID4)
```sql
UPDATE ir_config_parameter SET value = '<new_uuid4>' WHERE key = 'database.secret';
```

### 7. Regenerate database.uuid (UUID1)
```sql
UPDATE ir_config_parameter SET value = '<new_uuid1>' WHERE key = 'database.uuid';
```

## Command Line Options

```
Usage: ./odoo_db_restore.sh [options]

Options:
  --skip-backup      Skip production backup trigger (use existing backup)
  --backup-dir DIR   Specify existing backup directory path on production
  --no-drop          Don't drop existing database before restore
  --db-name NAME     Override staging database name
  --help             Show help message
```

## Examples

### Example 1: Full Automated Restore
```bash
# Triggers backup on production, transfers to staging, restores
/opt/odoo_db_restore.sh
```

### Example 2: Use Existing Backup
```bash
# Skip backup step, use existing backup directory
/opt/odoo_db_restore.sh --skip-backup --backup-dir /opt/db_backups/my_odoo_db_backup_2026_02_25_081206
```

### Example 3: Restore to Test Database
```bash
# Restore to a different database name for testing
/opt/odoo_db_restore.sh --db-name test_restore_$(date +%Y%m%d)
```

## Prerequisites

### On Production Server
1. PostgreSQL installed with `pg_dump` command
2. Backup script at `/opt/pg_backup_dir_format.sh`
3. Proper permissions for database user

### On Staging Server
1. PostgreSQL installed with `pg_restore` command
2. SSH client installed
3. `rsync` installed
4. Python 3 (for UUID generation)
5. Root or sudo access

## Troubleshooting

### SSH Connection Failed
```bash
# Test SSH connection manually
ssh -i /root/.ssh/id_rsa root@175.41.161.8

# Check SSH key permissions
chmod 600 /root/.ssh/id_rsa
chmod 644 /root/.ssh/id_rsa.pub
```

### PostgreSQL Connection Failed
```bash
# Test PostgreSQL connection
sudo -u odoo psql -c '\q'

# Check PostgreSQL is running
systemctl status postgresql
```

### Permission Denied
```bash
# Ensure script is executable
chmod +x /opt/odoo_db_restore.sh

# Run as root
sudo /opt/odoo_db_restore.sh
```

### Check Logs
```bash
# View restoration log
tail -f /var/log/odoo_db_restore.log
```

## Security Notes

1. **SSH Keys**: Use SSH key authentication for automated/cron execution
2. **Passwords**: Never store passwords in the script
3. **File Permissions**: Keep scripts readable only by root (`chmod 700`)
4. **Network**: Consider using VPN or private network between servers
5. **Data Privacy**: Staging database contains production data - secure it appropriately

## Automation (Cron)

To run automatically (e.g., daily at 2 AM):

```bash
# Edit crontab
crontab -e

# Add this line
0 2 * * * /opt/odoo_db_restore.sh >> /var/log/odoo_db_restore.log 2>&1
```

## Support

For issues or questions, check:
1. Log file: `/var/log/odoo_db_restore.log`
2. PostgreSQL logs: `/var/log/postgresql/`
3. Odoo logs: `/var/log/odoo/`