#!/bin/bash
################################################################################
# Script for installing Odoo on Ubuntu 24.04 LTS
# Author: Yenthe Van Ginneken
# Updated by: Niaj Shahriar Shishir
#-------------------------------------------------------------------------------
# This script will install Odoo on your Ubuntu 24.04 server. It can install multiple Odoo instances
# in one Ubuntu because of the different xmlrpc_ports
#-------------------------------------------------------------------------------
# Make a new file:
# sudo nano odoo-install.sh
# Place this content in it and then make the file executable:
# sudo chmod +x odoo-install.sh
# Execute the script to install Odoo:
# ./odoo-install
################################################################################

set -e
set -o pipefail

# Configuration variables
OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"
INSTALL_WKHTMLTOPDF="True"
OE_PORT="8069"
OE_VERSION="18.0"
IS_ENTERPRISE="True"
INSTALL_NGINX="True"
OE_SUPERADMIN="admin"
GENERATE_RANDOM_PASSWORD="True"
OE_CONFIG="${OE_USER}-server"
WEBSITE_NAME="_"
LONGPOLLING_PORT="8072"
ENABLE_SSL="False"
ADMIN_EMAIL="odoo@example.com"
WKHTMLTOX_X64="https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6.1-2/wkhtmltox_0.12.6.1-2.jammy_amd64.deb"
VENV_DIR="/$OE_USER/venv"

# Logging function
log() {
    local LOG_LEVEL=$1
    shift
    local MESSAGE=$@
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [$LOG_LEVEL] $MESSAGE"
}

# Error handling function
handle_error() {
    local EXIT_CODE=$?
    local LINE_NO=$1
    log "ERROR" "Script failed at line $LINE_NO with exit code $EXIT_CODE"
    exit $EXIT_CODE
}
trap 'handle_error $LINENO' ERR

# Update server
update_server() {
    log "INFO" "Updating server"
    echo "deb http://archive.ubuntu.com/ubuntu/ noble main restricted" | sudo tee /etc/apt/sources.list.d/noble.list
    sudo apt-get update
    sudo apt-get upgrade -y
    sudo apt install curl ca-certificates gnupg2 lsb-release ubuntu-keyring -y
}

# Install PostgreSQL
install_postgresql() {
    log "INFO" "Installing PostgreSQL Server"
    sudo curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/apt.postgresql.org.gpg >/dev/null
    sudo sh -c 'echo "deb [arch=amd64] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    sudo apt-get update
    sudo apt-get install postgresql postgresql-server-dev-all postgis -y
    sudo su - postgres -c "createuser -s $OE_USER" 2>/dev/null || true
}

# Install dependencies
install_dependencies() {
    log "INFO" "Installing Python 3 and other dependencies"
    sudo apt install git python3 python3-pip build-essential wget python3-dev python3-venv python3-wheel python3-cffi libssl3 libxslt1-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools libpng-dev libjpeg-dev gdebi -y
    sudo apt install fonts-beng -y
}

# Install Node.js and npm
install_nodejs() {
    log "INFO" "Installing Node.js and npm"
    # curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs npm node-less
}

# Install Wkhtmltopdf
install_wkhtmltopdf() {
    if [ "$INSTALL_WKHTMLTOPDF" = "True" ]; then
        log "INFO" "Installing Wkhtmltopdf"
        if [ "$(getconf LONG_BIT)" == "64" ]; then
            _url=$WKHTMLTOX_X64
        fi
        sudo wget $_url
        sudo gdebi --n $(basename $_url)
        sudo rm -f /usr/bin/wkhtmltopdf
        sudo rm -f /usr/bin/wkhtmltoimage
        sudo ln -s /usr/local/bin/wkhtmltopdf /usr/bin
        sudo ln -s /usr/local/bin/wkhtmltoimage /usr/bin
    else
        log "INFO" "Wkhtmltopdf isn't installed due to the choice of the user!"
    fi
}

# Create Odoo user and directories
create_odoo_user() {
    log "INFO" "Creating Odoo system user"
    sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
    sudo adduser $OE_USER sudo
    if [ ! -d "/var/log/$OE_USER" ]; then
        sudo mkdir /var/log/$OE_USER
    else
        echo " Directory /var/log/$OE_USER exists. Passing..."
    fi
    sudo chown $OE_USER:$OE_USER /var/log/$OE_USER
}

# Create Python virtual environment
create_virtual_environment() {
    log "INFO" "Creating Python virtual environment"
    sudo -u $OE_USER python3 -m venv $VENV_DIR
    sudo chown -R $OE_USER:$OE_USER $VENV_DIR
    sudo -u $OE_USER $VENV_DIR/bin/pip3 install --upgrade pip
    sudo -u $OE_USER $VENV_DIR/bin/pip3 install html2text
}

# Install Odoo
install_odoo() {
    log "INFO" "Installing Odoo Server"
    if [ ! -d "$OE_HOME_EXT" ]; then
        sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/
    else
        echo " Directory $OE_HOME_EXT exists. Passing..."
    fi

    sudo -u $OE_USER $VENV_DIR/bin/pip3 install -r $OE_HOME_EXT/requirements.txt

    if [ "$IS_ENTERPRISE" = "True" ]; then
        log "INFO" "Installing Odoo Enterprise"
        sudo -u $OE_USER $VENV_DIR/bin/pip3 install psycopg2-binary pdfminer.six
        if [ ! -d "$OE_HOME/enterprise" ]; then
            sudo su $OE_USER -c "mkdir $OE_HOME/enterprise"
            sudo su $OE_USER -c "mkdir $OE_HOME/enterprise/addons"
        else
            echo " Directory $OE_HOME/enterprise exists. Passing..."
        fi

        # GITHUB_RESPONSE="False"
        # while [[ $GITHUB_RESPONSE == *"Authentication"* ]]; do
        #     log "WARNING" "Your authentication with Github has failed! Please try again."
        #     GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/enterprise "$OE_HOME/enterprise/addons" 2>&1)
        # done
        # sudo -u $OE_USER $VENV_DIR/bin/pip3 install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL
        sudo npm install -g less
        sudo npm install -g less-plugin-clean-css
    fi

    if [ ! -d "$OE_HOME/custom" ]; then
        sudo su $OE_USER -c "mkdir $OE_HOME/custom"
        sudo su $OE_USER -c "mkdir $OE_HOME/custom/addons"
    else
        echo "$OE_HOME/custom already exists. Passing ..."
    fi

    sudo chown -R $OE_USER:$OE_USER $OE_HOME/*
}

# Create Odoo configuration file
create_config_file() {
    log "INFO" "Creating Odoo configuration file"
    if [ -f /etc/${OE_CONFIG}.conf ]; then
        sudo rm /etc/${OE_CONFIG}.conf
    else
        echo "Odoo configuration file is at /etc/${OE_CONFIG}.conf ..."
    fi
    # sudo cp $OE_HOME_EXT/debian/odoo.conf /etc/${OE_CONFIG}.conf

    sudo touch /etc/${OE_CONFIG}.conf
    sudo su root -c "printf '[options] \n; This is the password that allows database operations:\n' >> /etc/${OE_CONFIG}.conf"
    if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
        log "INFO" "Generating random admin password"
        OE_SUPERADMIN=$(openssl rand -hex 20)
    fi
    sudo su root -c "printf 'admin_passwd = ${OE_SUPERADMIN}\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'http_interface = 127.0.0.1\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'http_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'gevent_port = ${LONGPOLLING_PORT}\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'logfile = /var/log/${OE_USER}/${OE_CONFIG}.log\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf '#limit_memory_hard = 1677721600\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf '#limit_memory_soft = 629145600\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'limit_request = 8192\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'limit_time_cpu = 600\n' >> /etc/${OE_CONFIG}.conf"
    sudo su root -c "printf 'limit_time_real = 1200\n' >> /etc/${OE_CONFIG}.conf"

    if [ "$IS_ENTERPRISE" = "True" ]; then
        sudo su root -c "printf 'addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/enterprise/addons,${OE_HOME}/custom/addons\n' >> /etc/${OE_CONFIG}.conf"
    else
        sudo su root -c "printf 'addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons\n' >> /etc/${OE_CONFIG}.conf"
    fi
    sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
    sudo chmod 640 /etc/${OE_CONFIG}.conf
}

# Create Odoo startup file
create_startup_file() {
    log "INFO" "Creating Odoo startup file"

    if [ -f "$OE_HOME_EXT/start.sh" ]; then

        sudo rm $OE_HOME_EXT/start.sh
    else
        echo "Odoo startup file is at $OE_HOME_EXT/start.sh ..."
    fi

    sudo su root -c "echo '#!/bin/sh' >> $OE_HOME_EXT/start.sh"
    sudo su root -c "echo 'sudo -u $OE_USER $VENV_DIR/bin/python $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf' >> $OE_HOME_EXT/start.sh"
    sudo chmod 755 $OE_HOME_EXT/start.sh
}

# Create Odoo init script
create_init_script() {
    log "INFO" "Creating Odoo init script"
    cat <<EOF >~/$OE_CONFIG
[Unit]
Description=Odoo Server
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=odoo
Group=odoo
WorkingDirectory=$OE_HOME_EXT
Environment="PATH=$VENV_DIR/bin:/usr/bin:/bin"
ExecStart=$VENV_DIR/bin/python3 $OE_HOME_EXT/odoo-bin -c /etc/${OE_CONFIG}.conf
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    if [ -f "/etc/systemd/system/$OE_CONFIG.service" ]; then
        sudo rm /etc/systemd/system/$OE_CONFIG.service
    else
        echo "Odoo init script file is at /etc/systemd/system/$OE_CONFIG.service ..."
    fi

    sudo mv ~/$OE_CONFIG /etc/systemd/system/$OE_CONFIG.service
    sudo chmod 755 /etc/systemd/system/$OE_CONFIG.service
    sudo chown root: /etc/systemd/system/$OE_CONFIG.service
}

# Install and configure Nginx
install_nginx() {
    if [ "$INSTALL_NGINX" = "True" ]; then
        log "INFO" "Installing and setting up Nginx"
        curl https://nginx.org/keys/nginx_signing.key | gpg --dearmor | sudo tee /usr/share/keyrings/nginx-archive-keyring.gpg >/dev/null
        gpg --dry-run --quiet --no-keyring --import --import-options import-show /usr/share/keyrings/nginx-archive-keyring.gpg
        echo "deb [signed-by=/usr/share/keyrings/nginx-archive-keyring.gpg] http://nginx.org/packages/ubuntu $(lsb_release -cs) nginx" | sudo tee /etc/apt/sources.list.d/nginx.list
        sudo apt update
        sudo apt install nginx python3-certbot python3-certbot-nginx -y

        cat <<EOF >~/odoo.conf
  upstream odoo {
    server 127.0.0.1:8069;
}
upstream odoochat {
    server 127.0.0.1:8072;
}
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    '' close;
}

server {
    listen 80;
    server_name $WEBSITE_NAME;
    proxy_read_timeout 720s;
    proxy_connect_timeout 720s;
    proxy_send_timeout 720s;

    # log
    access_log /var/log/nginx/odoo-access.log;
    error_log /var/log/nginx/odoo-error.log;

    # Redirect websocket requests to odoo gevent port
    location /websocket {
        proxy_pass http://odoochat;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;

        #add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
        #proxy_cookie_flags session_id samesite=lax secure;  # requires nginx 1.19.8
    }

    # Redirect requests to odoo backend server
    location / {
        # Add Headers for odoo proxy mode
        proxy_set_header X-Forwarded-Host \$http_host;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_redirect off;
        proxy_pass http://odoo;

        #add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
        #proxy_cookie_flags session_id samesite=lax secure; # requires nginx 1.19.8
    }

    # common gzip
    gzip_types text/css text/scss text/plain text/xml application/xml application/json application/javascript;
    gzip on;
}
EOF
        if [ -f "/etc/nginx/conf.d/odoo.conf" ]; then
            sudo rm /etc/nginx/conf.d/odoo.conf
        else
            echo "Odoo Nginx configuration file is at /etc/nginx/conf.d/odoo.conf ..."
        fi

        if [ -f "/etc/nginx/conf.d/default.conf" ]; then
            sudo rm /etc/nginx/conf.d/default.conf
        fi

        sudo mv ~/odoo.conf /etc/nginx/conf.d/
        # sudo service nginx restart
        sudo su root -c "printf 'proxy_mode = True\n' >> /etc/${OE_CONFIG}.conf"
        sudo su root -c "printf 'workers = 1\n' >> /etc/${OE_CONFIG}.conf"
        sudo su root -c "printf 'max_cron_threads = 1\n' >> /etc/${OE_CONFIG}.conf"
        log "INFO" "Nginx server is up and running. Configuration can be found at /etc/nginx/conf.d/odoo.conf"
    else
        log "INFO" "Nginx isn't installed due to choice of the user!"
    fi
}

# Enable SSL with Certbot
enable_ssl() {
    if [ "$INSTALL_NGINX" = "True" ] && [ "$ENABLE_SSL" = "True" ] && [ "$ADMIN_EMAIL" != "odoo@example.com" ] && [ "$WEBSITE_NAME" != "_" ]; then
        log "INFO" "Enabling SSL with Certbot"
        sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
        sudo service nginx restart
        log "INFO" "SSL/HTTPS is enabled!"
    else
        log "INFO" "SSL/HTTPS isn't enabled due to choice of the user or because of a misconfiguration!"
    fi
}

# Install logrotate
install_logrotate() {
    log "INFO" "Installing logrotate"
    sudo apt-get install -y logrotate
    if [ -f "/etc/logrotate.d/odoo" ]; then
        sudo rm /etc/logrotate.d/odoo
    else
        echo "Odoo logrotate file is at /etc/logrotate.d/odoo ..."
    fi

    cat <<EOF >/etc/logrotate.d/odoo
   /var/log/${OE_USER}/${OE_CONFIG}.log {
        daily
        rotate 7
        missingok
        notifempty
        compress
        delaycompress
        copytruncate
}
EOF
}

# Start Odoo service
start_odoo_service() {
    log "INFO" "Starting Odoo service"
    sudo systemctl daemon-reload
    sudo systemctl enable $OE_CONFIG.service
    sudo systemctl start $OE_CONFIG.service
    log "INFO" "Odoo server is up and running. Specifications:"
    log "INFO" "Port: $OE_PORT"
    log "INFO" "User service: $OE_USER"
    log "INFO" "Configuraton file location: /etc/${OE_CONFIG}.conf"
    log "INFO" "Logfile location: /var/log/$OE_USER"
    log "INFO" "User PostgreSQL: $OE_USER"
    log "INFO" "Code location: $OE_USER"
    log "INFO" "Addons folder: /$OE_USER/custom/addons/"
    log "INFO" "Password superadmin (database): $OE_SUPERADMIN"
    log "INFO" "Start Odoo service: sudo service $OE_CONFIG start"
    log "INFO" "Stop Odoo service: sudo service $OE_CONFIG stop"
    log "INFO" "Restart Odoo service: sudo service $OE_CONFIG restart"
    if [ "$INSTALL_NGINX" = "True" ]; then
        sudo systemctl enable nginx.service
        sudo systemctl start nginx.service
        log "INFO" "Nginx configuration file: /etc/nginx/conf.d/odoo.conf"
    fi
}

# Main function
main() {
    update_server
    install_postgresql
    install_dependencies
    install_nodejs
    install_wkhtmltopdf
    create_odoo_user
    create_virtual_environment
    install_odoo
    create_config_file
    create_startup_file
    create_init_script
    install_nginx
    enable_ssl
    install_logrotate
    start_odoo_service
}

main
