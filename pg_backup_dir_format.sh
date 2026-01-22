#!/bin/bash
set -e

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Date format for backup directory
TODAY=$(date +"%Y_%m_%d_%H%M%S")

# Database configuration
DB_NAME="my_odoo_db"       # Replace with your database name
DB_USER="odoo"             # Replace with your database user

# Paths
# Location where Odoo stores files (check your odoo.conf for 'data_dir')
SRC_FILESTORE_LOC="/odoo/.local/share/Odoo/filestore/${DB_NAME}"

# Base directory where backups will be stored
BACKUP_ROOT_DIR="/opt/db_backups"
CURRENT_BACKUP_DIR="${BACKUP_ROOT_DIR}/${DB_NAME}_backup_${TODAY}"

# Number of days to keep backups (0 to disable deletion)
KEEP_DAYS=2

# Number of parallel jobs for pg_dump (faster for directory format)
JOBS=4

# -----------------------------------------------------------------------------
# Preparation
# -----------------------------------------------------------------------------

echo "Starting backup for database: ${DB_NAME} at ${TODAY}"

# Create backup root directory if it doesn't exist
if [ ! -d "${BACKUP_ROOT_DIR}" ]; then
   echo "Creating backup root directory: ${BACKUP_ROOT_DIR}"
   mkdir -p "${BACKUP_ROOT_DIR}"
else
    # -----------------------------------------------------------------------------
    # Cleanup Old Backups
    # -----------------------------------------------------------------------------
    if [ "${KEEP_DAYS}" -gt 0 ]; then
        echo "Cleaning up backups older than ${KEEP_DAYS} days in ${BACKUP_ROOT_DIR}..."
        find "${BACKUP_ROOT_DIR}" -maxdepth 1 -type d -name "${DB_NAME}_backup_*" -mtime +"${KEEP_DAYS}" -exec rm -rf {} +
        echo "Cleanup complete."
    fi
fi

# Create directory for this specific backup run
echo "Creating directory for this backup: ${CURRENT_BACKUP_DIR}"
mkdir -p "${CURRENT_BACKUP_DIR}"

# -----------------------------------------------------------------------------
# Database Backup (Directory Format)
# -----------------------------------------------------------------------------

echo "Dumping database in Directory format (-Fd) with ${JOBS} jobs..."

# Dump to a 'db' subdirectory inside the current backup folder
sudo -u "${DB_USER}" pg_dump -F d -j "${JOBS}" --no-owner --no-privileges -f "${CURRENT_BACKUP_DIR}/db" "${DB_NAME}"

if [ $? -eq 0 ]; then
    echo "Database dump successful."
else
    echo "Database dump failed!"
    exit 1
fi

# -----------------------------------------------------------------------------
# Filestore Backup
# -----------------------------------------------------------------------------

if [ -d "${SRC_FILESTORE_LOC}" ]; then
    echo "Backing up filestore from ${SRC_FILESTORE_LOC}..."
    
    # Compress the filestore using tar
    # We cd to the directory to avoid storing full paths
    pushd "${SRC_FILESTORE_LOC}" > /dev/null
    tar -czf "${CURRENT_BACKUP_DIR}/filestore.tar.gz" .
    popd > /dev/null
    
    echo "Filestore backup successful (tar.gz)."
else
    echo "WARNING: Filestore directory ${SRC_FILESTORE_LOC} not found. Skipping filestore backup."
fi

echo "----------------------------------------------------------------"
echo "Backup process finished successfully."
echo "Location: ${CURRENT_BACKUP_DIR}"
echo "Contains: 'db' (directory dump) and 'filestore.tar.gz' (compressed filestore)"
echo "----------------------------------------------------------------"
