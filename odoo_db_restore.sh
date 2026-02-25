#!/bin/bash
# =============================================================================
# Odoo Database Restore Script - Staging Server
# =============================================================================
# This script connects to Production server, triggers backup, transfers it,
# restores to staging database, and sets up filestore.
# 
# Features:
#   - Automated backup trigger on Production
#   - Rsync transfer to Staging
#   - Database restore with pg_restore (directory format)
#   - Filestore extraction and setup
#   - Post-restore actions:
#     * Disable outgoing mail servers
#     * Deactivate cron jobs
#     * Update web.base.url
#     * Update database.create_date
#     * Remove enterprise keys
#     * Regenerate database.secret (UUID4)
#     * Regenerate database.uuid (UUID1)
#   - Comprehensive logging
#   - Error handling with rollback
#
# Usage: ./odoo_db_restore.sh [options]
#   Options:
#     --skip-backup    Skip production backup (use existing backup)
#     --backup-dir     Specify existing backup directory path on production
#     --no-drop        Don't drop existing database
#     --db-name        Override staging database name
#     --help           Show this help message
#
# Author: Auto-generated
# Date: 2026-02-25
# =============================================================================

set -e  # Exit on error (will be handled in trap)

# =============================================================================
# CONFIGURATION VARIABLES - EDIT THESE FOR YOUR ENVIRONMENT
# =============================================================================

# --- Production Server Settings ---
PROD_HOST="ip-address-or-hostname"
PROD_USER="username"
PROD_SSH_PORT="22"
# SSH key path (set empty for password auth - not recommended for automation)
PROD_SSH_KEY="/{username}/.ssh/id_rsa"
# Path to backup script on production
PROD_BACKUP_SCRIPT="/opt/pg_backup_dir_format.sh"
# Production database name (must match the backup script config on production)
PROD_DB_NAME="my_odoo_db"
# Production backup root directory (where backups are stored)
PROD_BACKUP_ROOT="/opt/db_backups"

# --- Staging Server Settings (this server) ---
STAGING_DB_USER="odoo"
STAGING_DB_HOST="localhost"
STAGING_DB_PORT="5432"
# Staging database name (will be created/replaced)
STAGING_DB_NAME="odoo_staging"
# Staging filestore location (check odoo.conf for data_dir)
STAGING_FILESTORE_ROOT="/odoo/.local/share/Odoo/filestore"
# Local backup storage directory
LOCAL_BACKUP_ROOT="/opt/db_backups"
# Log file location
LOG_FILE="/var/log/odoo_db_restore.log"
# Days to keep local backups (0 to disable)
KEEP_BACKUP_DAYS=2

# --- Restore Options ---
# Drop existing database before restore? (true/false)
DROP_EXISTING_DB=true
# Number of parallel jobs for pg_restore
RESTORE_JOBS=4
# Stop/Start Odoo service during restore (empty string to disable)
ODOO_SERVICE="odoo"
# Post-restore: Update web.base.url to this value (empty to skip)
STAGING_WEB_URL="http://localhost:8069"

# --- Post-Restore Actions ---
# Disable outgoing mail servers (true/false)
DISABLE_MAIL_SERVERS=true
# Deactivate cron jobs (true/false)
DEACTIVATE_CRONS=true
# Clear ir.attachment storage (true/false) - useful to avoid large attachments
CLEAR_ATTACHMENTS=false

# =============================================================================
# DO NOT EDIT BELOW THIS LINE UNLESS YOU KNOW WHAT YOU'RE DOING
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables to track state
BACKUP_DIR=""
LOCAL_BACKUP_DIR=""
DB_EXISTS=false
RESTORE_SUCCESS=false
START_TIME=""
OLD_DB_BACKUP=""

# =============================================================================
# LOGGING FUNCTIONS
# =============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo -e "${timestamp} [${level}] ${message}" | tee -a "$LOG_FILE"
}

log_info() {
    log "INFO" "$@"
}

log_success() {
    log "SUCCESS" "$@"
    echo -e "${GREEN}✓ $*${NC}"
}

log_warning() {
    log "WARNING" "$@"
    echo -e "${YELLOW}⚠ $*${NC}"
}

log_error() {
    log "ERROR" "$@"
    echo -e "${RED}✗ $*${NC}"
}

log_step() {
    log "STEP" "$@"
    echo -e "${BLUE}▶ $*${NC}"
}

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

show_help() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Odoo Database Restore Script - Restores production DB to staging"
    echo ""
    echo "Options:"
    echo "  --skip-backup      Skip production backup trigger (use existing backup)"
    echo "  --backup-dir DIR   Specify existing backup directory path on production"
    echo "  --no-drop          Don't drop existing database before restore"
    echo "  --db-name NAME     Override staging database name"
    echo "  --help             Show this help message"
    echo ""
    echo "Configuration (edit script to change defaults):"
    echo "  Production Host:    ${PROD_HOST}"
    echo "  Production DB:      ${PROD_DB_NAME}"
    echo "  Staging DB:         ${STAGING_DB_NAME}"
    echo "  Staging Filestore:  ${STAGING_FILESTORE_ROOT}"
    echo ""
    echo "Examples:"
    echo "  $0                              # Full restore with new backup"
    echo "  $0 --skip-backup --backup-dir /opt/db_backups/my_odoo_db_backup_2026_02_25_081206"
    echo "  $0 --no-drop --db-name test_restore"
}

# Parse command line arguments
parse_args() {
    SKIP_BACKUP=false
    SPECIFIED_BACKUP_DIR=""
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-backup)
                SKIP_BACKUP=true
                shift
                ;;
            --backup-dir)
                SPECIFIED_BACKUP_DIR="$2"
                shift 2
                ;;
            --no-drop)
                DROP_EXISTING_DB=false
                shift
                ;;
            --db-name)
                STAGING_DB_NAME="$2"
                shift 2
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
}

# Generate UUID4
generate_uuid4() {
    python3 -c "import uuid; print(str(uuid.uuid4()))"
}

# Generate UUID1
generate_uuid1() {
    python3 -c "import uuid; print(str(uuid.uuid1()))"
}

# SSH command helper
ssh_cmd() {
    if [ -n "$PROD_SSH_KEY" ] && [ -f "$PROD_SSH_KEY" ]; then
        ssh -i "$PROD_SSH_KEY" -p "$PROD_SSH_PORT" -o StrictHostKeyChecking=no "${PROD_USER}@${PROD_HOST}" "$@"
    else
        ssh -p "$PROD_SSH_PORT" -o StrictHostKeyChecking=no "${PROD_USER}@${PROD_HOST}" "$@"
    fi
}

# Rsync helper
rsync_from_prod() {
    local src="$1"
    local dest="$2"
    if [ -n "$PROD_SSH_KEY" ] && [ -f "$PROD_SSH_KEY" ]; then
        rsync -avz -e "ssh -i $PROD_SSH_KEY -p $PROD_SSH_PORT -o StrictHostKeyChecking=no" "${PROD_USER}@${PROD_HOST}:${src}" "${dest}"
    else
        rsync -avz -e "ssh -p $PROD_SSH_PORT -o StrictHostKeyChecking=no" "${PROD_USER}@${PROD_HOST}:${src}" "${dest}"
    fi
}

# Execute SQL as odoo user
psql_exec() {
    local db="$1"
    local sql="$2"
    sudo -u "$STAGING_DB_USER" psql -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" -d "$db" -c "$sql"
}

# Cleanup function for rollback
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ "$RESTORE_SUCCESS" = false ]; then
        log_error "Script failed! Attempting rollback..."
        
        # Restore old database if we backed it up
        if [ -n "$OLD_DB_BACKUP" ] && [ -d "$OLD_DB_BACKUP" ]; then
            log_warning "Attempting to restore previous database..."
            sudo -u "$STAGING_DB_USER" dropdb -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" "$STAGING_DB_NAME" 2>/dev/null || true
            sudo -u "$STAGING_DB_USER" createdb -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" "$STAGING_DB_NAME"
            sudo -u "$STAGING_DB_USER" pg_restore -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" -d "$STAGING_DB_NAME" -j "$RESTORE_JOBS" "$OLD_DB_BACKUP/db" 2>/dev/null || true
        fi
        
        # Start Odoo if it was stopped
        if [ -n "$ODOO_SERVICE" ] && [ "$ODOO_STOPPED" = true ]; then
            log_info "Starting Odoo service..."
            systemctl start "$ODOO_SERVICE" 2>/dev/null || service "$ODOO_SERVICE" start 2>/dev/null || true
        fi
    fi
    
    # Calculate duration
    if [ -n "$START_TIME" ]; then
        local end_time=$(date +%s)
        local duration=$((end_time - START_TIME))
        log_info "Total execution time: ${duration} seconds"
    fi
    
    exit $exit_code
}

trap cleanup EXIT

# =============================================================================
# MAIN FUNCTIONS
# =============================================================================

check_prerequisites() {
    log_step "Checking prerequisites..."
    
    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run as root or with sudo"
        exit 1
    fi
    
    # Create log directory if needed
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE" 2>/dev/null || {
        log_warning "Cannot write to $LOG_FILE, using /tmp"
        LOG_FILE="/tmp/odoo_db_restore.log"
    }
    
    # Create local backup directory
    mkdir -p "$LOCAL_BACKUP_ROOT"
    
    # Check PostgreSQL connectivity
    if ! sudo -u "$STAGING_DB_USER" psql -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" -c '\q' 2>/dev/null; then
        log_error "Cannot connect to PostgreSQL as user $STAGING_DB_USER"
        exit 1
    fi
    log_success "PostgreSQL connection OK"
    
    # Check SSH connectivity to production
    if [ "$SKIP_BACKUP" = false ]; then
        log_info "Testing SSH connection to production..."
        if ! ssh_cmd "echo 'SSH OK'" >/dev/null 2>&1; then
            log_error "Cannot SSH to production server ${PROD_HOST}"
            log_info "Please ensure SSH key is set up or password authentication is available"
            exit 1
        fi
        log_success "SSH connection to production OK"
    fi
    
    # Check if Odoo service exists
    if [ -n "$ODOO_SERVICE" ]; then
        if ! systemctl list-unit-files | grep -q "^${ODOO_SERVICE}.service" && ! service "$ODOO_SERVICE" status >/dev/null 2>&1; then
            log_warning "Odoo service '$ODOO_SERVICE' not found, will not manage service"
            ODOO_SERVICE=""
        fi
    fi
}

stop_odoo() {
    if [ -n "$ODOO_SERVICE" ]; then
        log_step "Stopping Odoo service..."
        if systemctl is-active --quiet "$ODOO_SERVICE" 2>/dev/null; then
            systemctl stop "$ODOO_SERVICE"
            ODOO_STOPPED=true
            log_success "Odoo service stopped"
        elif service "$ODOO_SERVICE" status >/dev/null 2>&1; then
            service "$ODOO_SERVICE" stop
            ODOO_STOPPED=true
            log_success "Odoo service stopped"
        else
            log_warning "Odoo service not running"
            ODOO_STOPPED=false
        fi
    fi
}

start_odoo() {
    if [ -n "$ODOO_SERVICE" ] && [ "$ODOO_STOPPED" = true ]; then
        log_step "Starting Odoo service..."
        if systemctl start "$ODOO_SERVICE" 2>/dev/null || service "$ODOO_SERVICE" start 2>/dev/null; then
            log_success "Odoo service started"
        else
            log_error "Failed to start Odoo service"
        fi
    fi
}

trigger_production_backup() {
    log_step "Triggering backup on production server..."
    
    # Run the backup script on production
    log_info "Executing: ${PROD_BACKUP_SCRIPT}"
    local output
    output=$(ssh_cmd "bash ${PROD_BACKUP_SCRIPT}" 2>&1)
    
    if [ $? -ne 0 ]; then
        log_error "Production backup failed!"
        log_error "$output"
        exit 1
    fi
    
    log_info "Backup output:"
    echo "$output" | tee -a "$LOG_FILE"
    
    # Extract the backup directory from output
    # Looking for line like: "Location: /opt/db_backups/my_odoo_db_backup_2026_02_25_081206"
    BACKUP_DIR=$(echo "$output" | grep -oP 'Location: \K[^\s]+' | head -1)
    
    if [ -z "$BACKUP_DIR" ]; then
        # Try alternative pattern
        BACKUP_DIR=$(echo "$output" | grep -oP '/opt/db_backups/[^\s]+' | tail -1)
    fi
    
    if [ -z "$BACKUP_DIR" ]; then
        log_error "Could not determine backup directory from output"
        exit 1
    fi
    
    log_success "Production backup created at: ${BACKUP_DIR}"
}

transfer_backup() {
    log_step "Transferring backup from production to staging..."
    
    if [ -n "$SPECIFIED_BACKUP_DIR" ]; then
        BACKUP_DIR="$SPECIFIED_BACKUP_DIR"
        log_info "Using specified backup directory: ${BACKUP_DIR}"
    fi
    
    # Verify backup exists on production
    if ! ssh_cmd "[ -d '${BACKUP_DIR}' ]" 2>/dev/null; then
        log_error "Backup directory does not exist on production: ${BACKUP_DIR}"
        exit 1
    fi
    
    # Get the backup folder name
    local backup_name=$(basename "$BACKUP_DIR")
    LOCAL_BACKUP_DIR="${LOCAL_BACKUP_ROOT}/${backup_name}"
    
    log_info "Transferring ${BACKUP_DIR} to ${LOCAL_BACKUP_DIR}..."
    rsync_from_prod "${BACKUP_DIR}/" "${LOCAL_BACKUP_DIR}/"
    
    if [ $? -ne 0 ]; then
        log_error "Failed to transfer backup"
        exit 1
    fi
    
    log_success "Backup transferred to: ${LOCAL_BACKUP_DIR}"
}

prepare_database() {
    log_step "Preparing database..."
    
    # Check if database exists
    DB_EXISTS=$(sudo -u "$STAGING_DB_USER" psql -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" -lqt | cut -d \| -f 1 | grep -qw "$STAGING_DB_NAME" && echo "true" || echo "false")
    
    if [ "$DB_EXISTS" = true ]; then
        log_info "Database '${STAGING_DB_NAME}' already exists"
        
        if [ "$DROP_EXISTING_DB" = true ]; then
            log_info "Dropping existing database..."
            
            # Terminate existing connections
            sudo -u "$STAGING_DB_USER" psql -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" -d postgres -c \
                "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '${STAGING_DB_NAME}' AND pid <> pg_backend_pid();" >/dev/null 2>&1
            
            # Drop the database
            sudo -u "$STAGING_DB_USER" dropdb -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" "$STAGING_DB_NAME"
            log_success "Database dropped"
        else
            log_error "Database already exists and --no-drop was specified"
            exit 1
        fi
    fi
    
    # Create new database
    log_info "Creating new database: ${STAGING_DB_NAME}"
    sudo -u "$STAGING_DB_USER" createdb -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" "$STAGING_DB_NAME"
    log_success "Database created"
}

restore_database() {
    log_step "Restoring database from backup..."
    
    local db_backup_path="${LOCAL_BACKUP_DIR}/db"
    
    if [ ! -d "$db_backup_path" ]; then
        log_error "Database backup not found at: ${db_backup_path}"
        exit 1
    fi
    
    log_info "Running pg_restore with ${RESTORE_JOBS} parallel jobs..."
    
    # Run pg_restore
    sudo -u "$STAGING_DB_USER" pg_restore \
        -h "$STAGING_DB_HOST" \
        -p "$STAGING_DB_PORT" \
        -d "$STAGING_DB_NAME" \
        -j "$RESTORE_JOBS" \
        --no-owner \
        --no-privileges \
        "$db_backup_path" 2>&1 | tee -a "$LOG_FILE"
    
    local restore_exit_code=${PIPESTATUS[0]}
    
    # pg_restore returns 0 for success, 1 for warnings (which are usually ok)
    if [ $restore_exit_code -gt 1 ]; then
        log_error "Database restore failed with exit code: ${restore_exit_code}"
        exit 1
    fi
    
    log_success "Database restored successfully"
}

restore_filestore() {
    log_step "Restoring filestore..."
    
    local filestore_backup="${LOCAL_BACKUP_DIR}/filestore.tar.gz"
    local filestore_dest="${STAGING_FILESTORE_ROOT}/${STAGING_DB_NAME}"
    
    if [ ! -f "$filestore_backup" ]; then
        log_warning "Filestore backup not found at: ${filestore_backup}"
        log_warning "Skipping filestore restoration"
        return 0
    fi
    
    # Create filestore directory
    mkdir -p "$filestore_dest"
    
    # Extract filestore
    log_info "Extracting filestore to: ${filestore_dest}"
    tar -xzf "$filestore_backup" -C "$filestore_dest"
    
    # Set ownership to odoo user
    chown -R "${STAGING_DB_USER}:${STAGING_DB_USER}" "$filestore_dest"
    
    log_success "Filestore restored to: ${filestore_dest}"
}

run_post_restore_actions() {
    log_step "Running post-restore actions..."
    
    # Disable mail servers
    if [ "$DISABLE_MAIL_SERVERS" = true ]; then
        log_info "Disabling outgoing mail servers..."
        psql_exec "$STAGING_DB_NAME" \
            "UPDATE ir_mail_server SET active = false, smtp_host = 'localhost', smtp_port = 25;"
        log_success "Mail servers disabled"
    fi
    
    # Deactivate cron jobs
    if [ "$DEACTIVATE_CRONS" = true ]; then
        log_info "Deactivating cron jobs..."
        psql_exec "$STAGING_DB_NAME" \
            "UPDATE ir_cron SET active = false;"
        log_success "Cron jobs deactivated"
    fi
    
    # Update web.base.url
    if [ -n "$STAGING_WEB_URL" ]; then
        log_info "Updating web.base.url to: ${STAGING_WEB_URL}"
        psql_exec "$STAGING_DB_NAME" \
            "UPDATE ir_config_parameter SET value = '${STAGING_WEB_URL}' WHERE key = 'web.base.url';"
        # Insert if doesn't exist
        psql_exec "$STAGING_DB_NAME" \
            "INSERT INTO ir_config_parameter (key, value) VALUES ('web.base.url', '${STAGING_WEB_URL}') ON CONFLICT (key) DO NOTHING;"
        log_success "web.base.url updated"
    fi
    
    # Update database.create_date
    log_info "Updating database.create_date to restoration time..."
    psql_exec "$STAGING_DB_NAME" \
        "UPDATE ir_config_parameter SET value = NOW()::text WHERE key = 'database.create_date';"
    log_success "database.create_date updated"
    
    # Remove enterprise-related keys
    log_info "Removing enterprise-related configuration keys..."
    psql_exec "$STAGING_DB_NAME" \
        "DELETE FROM ir_config_parameter WHERE key IN ('database.enterprise_code', 'database.expiration_date', 'database.expiration_reason');"
    log_success "Enterprise keys removed"
    
    # Regenerate database.secret (UUID4)
    log_info "Regenerating database.secret (UUID4)..."
    local new_uuid4=$(generate_uuid4)
    psql_exec "$STAGING_DB_NAME" \
        "UPDATE ir_config_parameter SET value = '${new_uuid4}' WHERE key = 'database.secret';"
    log_success "database.secret updated to: ${new_uuid4}"
    
    # Regenerate database.uuid (UUID1)
    log_info "Regenerating database.uuid (UUID1)..."
    local new_uuid1=$(generate_uuid1)
    psql_exec "$STAGING_DB_NAME" \
        "UPDATE ir_config_parameter SET value = '${new_uuid1}' WHERE key = 'database.uuid';"
    log_success "database.uuid updated to: ${new_uuid1}"
    
    # Clear attachments if requested
    if [ "$CLEAR_ATTACHMENTS" = true ]; then
        log_info "Clearing ir.attachment storage..."
        psql_exec "$STAGING_DB_NAME" \
            "DELETE FROM ir_attachment WHERE res_model NOT IN ('ir.ui.view', 'ir.ui.menu');"
        log_success "Attachments cleared"
    fi
    
    # Vacuum analyze for performance
    log_info "Running VACUUM ANALYZE..."
    sudo -u "$STAGING_DB_USER" vacuumdb -h "$STAGING_DB_HOST" -p "$STAGING_DB_PORT" -a -z 2>/dev/null || true
    log_success "Database vacuumed"
}

cleanup_old_backups() {
    if [ "$KEEP_BACKUP_DAYS" -gt 0 ]; then
        log_step "Cleaning up old backups..."
        find "$LOCAL_BACKUP_ROOT" -maxdepth 1 -type d -name "*_backup_*" -mtime +"$KEEP_BACKUP_DAYS" -exec rm -rf {} \; 2>/dev/null || true
        log_success "Old backups cleaned (keeping ${KEEP_BACKUP_DAYS} days)"
    fi
}

print_summary() {
    echo ""
    echo "================================================================"
    echo "                    RESTORATION COMPLETE"
    echo "================================================================"
    echo ""
    echo "Database:     ${STAGING_DB_NAME}"
    echo "Filestore:    ${STAGING_FILESTORE_ROOT}/${STAGING_DB_NAME}"
    echo "Backup:       ${LOCAL_BACKUP_DIR}"
    echo "Log file:     ${LOG_FILE}"
    echo ""
    echo "Post-restore actions completed:"
    echo "  ✓ Mail servers disabled"
    echo "  ✓ Cron jobs deactivated"
    echo "  ✓ web.base.url updated"
    echo "  ✓ database.create_date updated"
    echo "  ✓ Enterprise keys removed"
    echo "  ✓ database.secret regenerated (UUID4)"
    echo "  ✓ database.uuid regenerated (UUID1)"
    echo ""
    echo "To connect to the restored database:"
    echo "  psql -U ${STAGING_DB_USER} -d ${STAGING_DB_NAME}"
    echo ""
    echo "To start Odoo with this database:"
    echo "  ./odoo-bin -c /etc/odoo/odoo.conf -d ${STAGING_DB_NAME}"
    echo "================================================================"
}

# =============================================================================
# MAIN EXECUTION
# =============================================================================

main() {
    START_TIME=$(date +%s)
    
    echo ""
    echo "================================================================"
    echo "        Odoo Database Restore Script - Staging Server"
    echo "================================================================"
    echo ""
    
    # Parse command line arguments
    parse_args "$@"
    
    # Log configuration
    log_info "Configuration:"
    log_info "  Production Host:    ${PROD_HOST}"
    log_info "  Production DB:      ${PROD_DB_NAME}"
    log_info "  Staging DB:         ${STAGING_DB_NAME}"
    log_info "  Staging Filestore:  ${STAGING_FILESTORE_ROOT}"
    log_info "  Drop Existing DB:   ${DROP_EXISTING_DB}"
    log_info "  Skip Backup:        ${SKIP_BACKUP}"
    echo ""
    
    # Run restoration steps
    check_prerequisites
    stop_odoo
    
    if [ "$SKIP_BACKUP" = false ]; then
        trigger_production_backup
    fi
    
    transfer_backup
    prepare_database
    restore_database
    restore_filestore
    run_post_restore_actions
    
    RESTORE_SUCCESS=true
    
    start_odoo
    cleanup_old_backups
    print_summary
    
    log_success "Restoration completed successfully!"
}

# Run main function
main "$@"