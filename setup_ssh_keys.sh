#!/bin/bash
# =============================================================================
# SSH Key Setup Helper Script
# =============================================================================
# This script sets up SSH key-based authentication from Staging to Production
# for automated database restoration.
#
# Usage: ./setup_ssh_keys.sh
#
# Prerequisites:
#   - SSH access to production server with password
#   - Root or sudo access on both servers
# =============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# CONFIGURATION - Edit these if needed
# =============================================================================

PROD_HOST="ip-address-or-hostname"
PROD_USER="username"
PROD_SSH_PORT="22"
SSH_KEY_PATH="/{username}/.ssh/id_rsa"
SSH_KEY_COMMENT="staging-to-production-$(hostname)"

# =============================================================================
# FUNCTIONS
# =============================================================================

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# =============================================================================
# MAIN SCRIPT
# =============================================================================

echo ""
echo "================================================================"
echo "        SSH Key Setup for Odoo DB Restore Script"
echo "================================================================"
echo ""
echo "This script will:"
echo "  1. Generate SSH key pair (if not exists)"
echo "  2. Copy public key to production server"
echo "  3. Test SSH connection"
echo ""
echo "Production Server: ${PROD_HOST}"
echo "SSH Key Path: ${SSH_KEY_PATH}"
echo ""

read -p "Continue? (y/n): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Step 1: Check if SSH key already exists
echo ""
log_info "Checking for existing SSH key..."

if [ -f "$SSH_KEY_PATH" ]; then
    log_warning "SSH key already exists at ${SSH_KEY_PATH}"
    read -p "Use existing key? (y/n): " use_existing
    if [[ ! "$use_existing" =~ ^[Yy]$ ]]; then
        read -p "Backup existing key and generate new one? (y/n): " backup_key
        if [[ "$backup_key" =~ ^[Yy]$ ]]; then
            mv "$SSH_KEY_PATH" "${SSH_KEY_PATH}.backup.$(date +%Y%m%d%H%M%S)"
            mv "${SSH_KEY_PATH}.pub" "${SSH_KEY_PATH}.pub.backup.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
        else
            echo "Aborted."
            exit 0
        fi
    else
        log_success "Using existing SSH key"
        # Skip to step 2
        SSH_KEY_EXISTS=true
    fi
fi

# Generate new SSH key if needed
if [ "$SSH_KEY_EXISTS" != true ]; then
    log_info "Generating new SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY_PATH" -N "" -C "$SSH_KEY_COMMENT"
    
    if [ $? -eq 0 ]; then
        log_success "SSH key generated successfully"
    else
        log_error "Failed to generate SSH key"
        exit 1
    fi
fi

# Step 2: Copy public key to production server
echo ""
log_info "Copying public key to production server..."
log_info "You will be prompted for the production server password."
echo ""

# Use ssh-copy-id if available
if command -v ssh-copy-id &> /dev/null; then
    ssh-copy-id -i "${SSH_KEY_PATH}.pub" -p "$PROD_SSH_PORT" "${PROD_USER}@${PROD_HOST}"
else
    # Manual copy if ssh-copy-id not available
    cat "${SSH_KEY_PATH}.pub" | ssh -p "$PROD_SSH_PORT" "${PROD_USER}@${PROD_HOST}" \
        "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
fi

if [ $? -eq 0 ]; then
    log_success "Public key copied to production server"
else
    log_error "Failed to copy public key"
    exit 1
fi

# Step 3: Test SSH connection
echo ""
log_info "Testing SSH connection to production server..."

if ssh -i "$SSH_KEY_PATH" -p "$PROD_SSH_PORT" -o StrictHostKeyChecking=no "${PROD_USER}@${PROD_HOST}" "echo 'SSH connection successful!'" 2>/dev/null; then
    log_success "SSH key authentication is working!"
else
    log_error "SSH connection test failed"
    exit 1
fi

# Step 4: Print summary
echo ""
echo "================================================================"
echo "                    SETUP COMPLETE"
echo "================================================================"
echo ""
echo "SSH key-based authentication is now configured!"
echo ""
echo "Details:"
echo "  Private Key:  ${SSH_KEY_PATH}"
echo "  Public Key:   ${SSH_KEY_PATH}.pub"
echo "  Target Host:  ${PROD_HOST}"
echo "  Target User:  ${PROD_USER}"
echo ""
echo "You can now run the odoo_db_restore.sh script without password prompts."
echo ""
echo "Test command:"
echo "  ssh -i ${SSH_KEY_PATH} ${PROD_USER}@${PROD_HOST} 'hostname'"
echo ""
echo "================================================================"