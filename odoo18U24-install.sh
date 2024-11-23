#!/bin/bash
################################################################################
# Script for installing Odoo 18.0 on Ubuntu 24.04 LTS
# Author: Claude Assistant
# Based on work by Yenthe Van Ginneken
################################################################################

# Stop script on error
set -e

#--------------------------------------------------
# Variables
#--------------------------------------------------
# Main config
ODOO_USER="odoo"
ODOO_HOME="/opt/${ODOO_USER}"
ODOO_VERSION="18.0"
ODOO_PORT="8069"
LONGPOLLING_PORT="8072"
ODOO_CONFIG="${ODOO_USER}-server"
VENV_PATH="${ODOO_HOME}/venv"
LOG_DIR="/var/log/${ODOO_USER}"
CONFIG_DIR="/etc/${ODOO_USER}"

# PostgreSQL config
POSTGRESQL_VERSION="16"
DB_USER="${ODOO_USER}"
DB_PASSWORD=$(openssl rand -base64 32)

# System resource calculations
TOTAL_MEM_GB=$(free -g | awk '/^Mem:/{print $2}')
TOTAL_MEM_MB=$(free -m | awk '/^Mem:/{print $2}')
CPU_CORES=$(nproc)

# Resource allocation (percentage of total memory)
NGINX_MEM_PERCENT=10      # 10% for Nginx
POSTGRES_MEM_PERCENT=40   # 40% for PostgreSQL
ODOO_MEM_PERCENT=35      # 35% for Odoo
# Remaining 15% for OS and other services

# Calculate memory allocations
NGINX_MEM_MB=$((TOTAL_MEM_MB * NGINX_MEM_PERCENT / 100))
POSTGRES_MEM_MB=$((TOTAL_MEM_MB * POSTGRES_MEM_PERCENT / 100))
ODOO_MEM_MB=$((TOTAL_MEM_MB * ODOO_MEM_PERCENT / 100))

# Nginx worker calculations
NGINX_WORKERS=$((CPU_CORES / 4 > 0 ? CPU_CORES / 4 : 1))
NGINX_WORKER_CONNECTIONS=$((1024 * CPU_CORES))
NGINX_WORKER_RLIMIT=$((NGINX_MEM_MB * 1024 * 1024))

# Calculate PostgreSQL resources (40% of system memory)
POSTGRES_MEM_MB=$((TOTAL_MEM_MB * 40 / 100))
SHARED_BUFFERS_MB=$((POSTGRES_MEM_MB * 25 / 100))
WORK_MEM_MB=$((SHARED_BUFFERS_MB / (2 * CPU_CORES)))
MAINTENANCE_WORK_MEM_MB=$((SHARED_BUFFERS_MB / 8))
EFFECTIVE_CACHE_SIZE_MB=$((TOTAL_MEM_MB * 50 / 100))

# Calculate Odoo workers (considering available memory after PostgreSQL)
ODOO_MEM_PER_WORKER=256  # MB per worker
AVAILABLE_MEM_FOR_ODOO=$((TOTAL_MEM_MB * 45 / 100))  # 45% for Odoo
MAX_WORKERS_BY_RAM=$((AVAILABLE_MEM_FOR_ODOO / ODOO_MEM_PER_WORKER))
MAX_WORKERS_BY_CPU=$((CPU_CORES * 2 + 1))
WORKERS=$(( MAX_WORKERS_BY_RAM < MAX_WORKERS_BY_CPU ? MAX_WORKERS_BY_RAM : MAX_WORKERS_BY_CPU ))

# Git repos
ODOO_REPO="https://github.com/odoo/odoo.git"
ENTERPRISE_REPO="https://github.com/odoo/enterprise.git"

# System dependencies - keep in alphabetical order
SYSTEM_PACKAGES=(
    build-essential
    fonts-noto-cjk
    gcc
    git
    libffi-dev
    libjpeg-dev
    libldap2-dev
    libpq-dev
    libsasl2-dev
    libssl-dev
    libxml2-dev
    libxslt1-dev
    nodejs
    npm
    pkg-config
    python3-dev
    python3-pip
    python3-venv
    wget
)

#--------------------------------------------------
# Logging Functions
#--------------------------------------------------
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ERROR: $1" >&2
    exit 1
}

#--------------------------------------------------
# Check if running as root
#--------------------------------------------------
if [ "$(id -u)" != "0" ]; then
    error "This script must be run as root!"
fi

#--------------------------------------------------
# Update System
#--------------------------------------------------
log "Updating system packages..."
apt-get update && apt-get upgrade -y || error "Failed to update system packages"

#--------------------------------------------------
# Install PostgreSQL
#--------------------------------------------------
log "Installing PostgreSQL ${POSTGRESQL_VERSION}..."
sh -c "echo 'deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main' > /etc/apt/sources.list.d/pgdg.list"
wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
apt-get update
apt-get install -y postgresql-${POSTGRESQL_VERSION} || error "Failed to install PostgreSQL"

log "Configuring PostgreSQL..."
cat <<EOF > /etc/postgresql/${POSTGRESQL_VERSION}/main/conf.d/odoo.conf
# Memory Configuration
shared_buffers = ${SHARED_BUFFERS_MB}MB         # 25% of PostgreSQL memory
work_mem = ${WORK_MEM_MB}MB                     # Per-operation memory
maintenance_work_mem = ${MAINTENANCE_WORK_MEM_MB}MB  # For maintenance operations
effective_cache_size = ${EFFECTIVE_CACHE_SIZE_MB}MB  # Expected disk cache size

# Checkpoints
checkpoint_completion_target = 0.9
checkpoint_timeout = 1h
max_wal_size = 2GB
min_wal_size = 1GB

# Query Planner
random_page_cost = 1.1       # Assuming SSD storage
effective_io_concurrency = 200  # Concurrent I/O operations
default_statistics_target = 100

# Write Ahead Log
wal_buffers = 16MB
synchronous_commit = off     # Improves performance, slight risk of data loss
wal_writer_delay = 200ms

# Background Writer
bgwriter_delay = 200ms
bgwriter_lru_maxpages = 100
bgwriter_lru_multiplier = 2.0

# Parallel Query
max_parallel_workers_per_gather = $((CPU_CORES / 2))
max_parallel_workers = ${CPU_CORES}
max_worker_processes = $((CPU_CORES * 2))

# Connection Settings
max_connections = $((WORKERS * 2 + 20))  # 2 connections per worker + extra
EOF

# Set PostgreSQL kernel parameters
cat <<EOF > /etc/sysctl.d/20-postgresql.conf
# Kernel Parameters for PostgreSQL
vm.swappiness = 10                     # Reduce swapping
vm.overcommit_memory = 2               # Memory overcommit mode
vm.overcommit_ratio = 80               # Memory overcommit ratio
kernel.shmmax = $((TOTAL_MEM_MB * 1024 * 1024))  # Maximum shared memory segment
kernel.shmall = $((TOTAL_MEM_MB * 1024 * 1024))  # Total shared memory
kernel.sem = 50100 64128000 50100 1280  # Semaphores
net.core.rmem_max = 4194304            # Maximum socket receive buffer
net.core.wmem_max = 4194304            # Maximum socket send buffer
net.ipv4.tcp_timestamps = 0            # Disable TCP timestamps
EOF

# Apply sysctl settings
sysctl -p /etc/sysctl.d/20-postgresql.conf

log "Creating PostgreSQL user..."
su - postgres -c "createuser -s ${DB_USER}" 2>/dev/null || true

# Restart PostgreSQL to apply changes
systemctl restart postgresql

#--------------------------------------------------
# Install System Dependencies
#--------------------------------------------------
log "Installing system dependencies..."
apt-get install -y "${SYSTEM_PACKAGES[@]}" || error "Failed to install system packages"

#--------------------------------------------------
# Install wkhtmltopdf
#--------------------------------------------------
log "Installing wkhtmltopdf..."
WKHTMLTOPDF_URL="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
wget ${WKHTMLTOPDF_URL}
dpkg -i $(basename ${WKHTMLTOPDF_URL})
apt-get install -f -y
rm $(basename ${WKHTMLTOPDF_URL})

#--------------------------------------------------
# Create Odoo User
#--------------------------------------------------
log "Creating Odoo user..."
useradd -m -d ${ODOO_HOME} -U -r -s /bin/bash ${ODOO_USER} || true

#--------------------------------------------------
# Create Directory Structure
#--------------------------------------------------
log "Creating directory structure..."
mkdir -p ${ODOO_HOME}/{custom-addons,enterprise,server}
mkdir -p ${LOG_DIR}
mkdir -p ${CONFIG_DIR}
chown -R ${ODOO_USER}:${ODOO_USER} ${ODOO_HOME}
chown -R ${ODOO_USER}:${ODOO_USER} ${LOG_DIR}

#--------------------------------------------------
# Install Odoo
#--------------------------------------------------
log "Cloning Odoo repository..."
su - ${ODOO_USER} -c "git clone --depth 1 --branch ${ODOO_VERSION} ${ODOO_REPO} ${ODOO_HOME}/server"

#--------------------------------------------------
# Setup Python Virtual Environment
#--------------------------------------------------
log "Setting up Python virtual environment..."
su - ${ODOO_USER} -c "python3 -m venv ${VENV_PATH}"
su - ${ODOO_USER} -c "${VENV_PATH}/bin/pip install --upgrade pip"
su - ${ODOO_USER} -c "${VENV_PATH}/bin/pip install wheel"
su - ${ODOO_USER} -c "${VENV_PATH}/bin/pip install -r ${ODOO_HOME}/server/requirements.txt"

# Additional Python packages for better performance and security
su - ${ODOO_USER} -c "${VENV_PATH}/bin/pip install psycopg2-binary watchdog pyOpenSSL cryptography"

#--------------------------------------------------
# Configure Odoo
#--------------------------------------------------
log "Creating Odoo configuration..."
cat <<EOF > ${CONFIG_DIR}/${ODOO_CONFIG}.conf
[options]
; Basic Configuration
admin_passwd = ${DB_PASSWORD}
db_host = False
db_port = False
db_user = ${DB_USER}
db_password = False
http_port = ${ODOO_PORT}
longpolling_port = ${LONGPOLLING_PORT}

; Performance Optimization
# Calculate number of workers based on CPU cores
# Format: (CPU cores) or (CPU cores * 2 + 1) depending on available RAM
CPU_CORES=$(nproc)
if [ $(free -g | awk '/^Mem:/{print $2}') -gt 8 ]; then
    # If system has more than 8GB RAM, use more workers
    WORKERS=$((CPU_CORES * 2 + 1))
else
    # For systems with less RAM, use one worker per CPU core
    WORKERS=$CPU_CORES
fi
workers = ${WORKERS}
max_cron_threads = 2
limit_memory_hard = 2684354560
limit_memory_soft = 2147483648
limit_request = 8192
limit_time_cpu = 600
limit_time_real = 1200

; Security
logfile = ${LOG_DIR}/${ODOO_CONFIG}.log
logrotate = True
proxy_mode = True

; Addons Path
addons_path = ${ODOO_HOME}/server/addons,${ODOO_HOME}/custom-addons

; Advanced Features
gevent_port = ${LONGPOLLING_PORT}
xmlrpc = True
xmlrpc_interface = 127.0.0.1
EOF

chown ${ODOO_USER}:${ODOO_USER} ${CONFIG_DIR}/${ODOO_CONFIG}.conf
chmod 640 ${CONFIG_DIR}/${ODOO_CONFIG}.conf

#--------------------------------------------------
# Create Systemd Service
#--------------------------------------------------
log "Creating systemd service..."
cat <<EOF > /etc/systemd/system/${ODOO_USER}.service
[Unit]
Description=Odoo Open Source ERP and CRM
After=network.target postgresql.service

[Service]
Type=simple
User=${ODOO_USER}
Group=${ODOO_USER}
ExecStart=${VENV_PATH}/bin/python3 ${ODOO_HOME}/server/odoo-bin -c ${CONFIG_DIR}/${ODOO_CONFIG}.conf
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

#--------------------------------------------------
# Configure Log Rotation
#--------------------------------------------------
log "Configuring log rotation..."
cat <<EOF > /etc/logrotate.d/${ODOO_USER}
${LOG_DIR}/${ODOO_CONFIG}.log {
    daily
    rotate 7
    missingok
    notifempty
    compress
    delaycompress
    create 640 ${ODOO_USER} ${ODOO_USER}
    copytruncate
}
EOF

#--------------------------------------------------
# Start Odoo Service
#--------------------------------------------------
log "Starting Odoo service..."
systemctl daemon-reload
systemctl enable ${ODOO_USER}
systemctl start ${ODOO_USER}

#--------------------------------------------------
# Summary
#--------------------------------------------------
echo "-----------------------------------------------------------"
echo "Odoo installation completed successfully!"
echo "-----------------------------------------------------------"
echo "Odoo configuration:"
echo "    User: ${ODOO_USER}"
echo "    Home: ${ODOO_HOME}"
echo "    Config file: ${CONFIG_DIR}/${ODOO_CONFIG}.conf"
echo "    Log file: ${LOG_DIR}/${ODOO_CONFIG}.log"
echo "    Database user: ${DB_USER}"
echo "    Admin password: ${DB_PASSWORD}"
echo ""
echo "Service management:"
echo "    Start: systemctl start ${ODOO_USER}"
echo "    Stop: systemctl stop ${ODOO_USER}"
echo "    Restart: systemctl restart ${ODOO_USER}"
echo "    Status: systemctl status ${ODOO_USER}"
echo ""
echo "Installation path: ${ODOO_HOME}"
echo "Custom addons path: ${ODOO_HOME}/custom-addons"
echo "Virtual environment: ${VENV_PATH}"
echo "-----------------------------------------------------------"
