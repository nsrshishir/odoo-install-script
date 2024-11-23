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
    sudo apt-get install git python3 python3-pip build-essential wget python3-dev python3-venv python3-wheel python3-cffi libssl3 libxslt1-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools libpng-dev libjpeg-dev gdebi -y
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
    sudo cp $OE_HOME_EXT/debian/odoo.conf /etc/${OE_CONFIG}.conf

    # sudo touch /etc/${OE_CONFIG}.conf
    # sudo su root -c "printf '[options] \n; This is the password that allows database operations:\n' >> /etc/${OE_CONFIG}.conf"
    if [ "$GENERATE_RANDOM_PASSWORD" = "True" ]; then
        log "INFO" "Generating random admin password"
        OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
    fi
    sudo su root -c "printf 'admin_passwd = ${OE_SUPERADMIN}\n' >> /etc/${OE_CONFIG}.conf"
    # if [ "$OE_VERSION" ] >"11.0"; then
    #     sudo su root -c "printf 'http_interface = 127.0.0.1\n' >> /etc/${OE_CONFIG}.conf"
    #     sudo su root -c "printf 'http_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
    #     sudo su root -c "printf 'gevent_port = ${LONGPOLLING_PORT}\n' >> /etc/${OE_CONFIG}.conf"
    # else
    #     sudo su root -c "printf 'xmlrpc_port = ${OE_PORT}\n' >> /etc/${OE_CONFIG}.conf"
    # fi
    sudo su root -c "printf 'logfile = /var/log/${OE_USER}/${OE_CONFIG}.log\n' >> /etc/${OE_CONFIG}.conf"

    if [ "$IS_ENTERPRISE" = "True" ]; then
        sudo su root -c "printf 'addons_path=${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons\n' >> /etc/${OE_CONFIG}.conf"
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
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$remote_fs \$syslog
# Required-Stop: \$remote_fs \$syslog
# Should-Start: \$network
# Should-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Enterprise Business Applications
# Description: ODOO Business Applications
### END INIT INFO
PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
DAEMON=$VENV_DIR/bin/python $OE_HOME_EXT/odoo-bin
NAME=$OE_CONFIG
DESC=$OE_CONFIG
# Specify the user name (Default: odoo).
USER=$OE_USER
# Specify an alternate config file (Default: /etc/openerp-server.conf).
CONFIGFILE="/etc/${OE_CONFIG}.conf"
# pidfile
PIDFILE=/var/run/\${NAME}.pid
# Additional options that are passed to the Daemon.
DAEMON_OPTS="-c \$CONFIGFILE"
[ -x \$DAEMON ] || exit 0
[ -f \$CONFIGFILE ] || exit 0
checkpid() {
[ -f \$PIDFILE ] || return 1
pid=\`cat \$PIDFILE\`
[ -d /proc/\$pid ] && return 0
return 1
}
case "\${1}" in
start)
echo -n "Starting \${DESC}: "
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- \$DAEMON_OPTS
echo "\${NAME}."
;;
stop)
echo -n "Stopping \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
echo "\${NAME}."
;;
restart|force-reload)
echo -n "Restarting \${DESC}: "
start-stop-daemon --stop --quiet --pidfile \$PIDFILE \
--oknodo
sleep 1
start-stop-daemon --start --quiet --pidfile \$PIDFILE \
--chuid \$USER --background --make-pidfile \
--exec \$DAEMON -- \$DAEMON_OPTS
echo "\${NAME}."
;;
*)
N=/etc/init.d/\$NAME
echo "Usage: \$NAME {start|stop|restart|force-reload}" >&2
exit 1
;;
esac
exit 0
EOF

    if [ -f "/etc/init.d/$OE_CONFIG" ]; then
        sudo rm /etc/init.d/$OE_CONFIG
    else
        echo "Odoo init script file is at /etc/init.d/$OE_CONFIG ..."
    fi

    sudo mv ~/$OE_CONFIG /etc/init.d/$OE_CONFIG
    sudo chmod 755 /etc/init.d/$OE_CONFIG
    sudo chown root: /etc/init.d/$OE_CONFIG
    sudo update-rc.d $OE_CONFIG defaults
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
  upstream odooserver {
      server 127.0.0.1:$OE_PORT;
  }
  upstream odoolongpoll {
      server 127.0.0.1:$LONGPOLLING_PORT;
  }
  map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
  }

  server {
  listen 80;

  # set proper server name after domain set
  server_name $WEBSITE_NAME;

  # Add Headers for odoo proxy mode
  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Real-IP \$remote_addr;

  #   odoo    log files
  access_log  /var/log/nginx/$OE_USER-access.log;
  error_log   /var/log/nginx/$OE_USER-error.log;

  #   increase    proxy   buffer  size
  proxy_buffers   16  64k;
  proxy_buffer_size   128k;

  proxy_read_timeout 900s;
  proxy_connect_timeout 900s;
  proxy_send_timeout 900s;

  #   force   timeouts    if  the backend dies
  proxy_next_upstream error   timeout invalid_header  http_500    http_502
  http_503;

  types {
  text/less less;
  text/scss scss;
  }

  #   enable  data    compression
  gzip    on;
  gzip_min_length 1100;
  gzip_buffers    4   32k;
  gzip_types  text/css text/scss text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png image/webp;
  gzip_vary   on;
  client_header_buffer_size 4k;
  large_client_header_buffers 4 64k;
  client_max_body_size 0;

  location / {
  proxy_pass http://odooserver;
  # by default, do not forward anything
  proxy_redirect off;
  # proxy_cookie_path / "/; secure; HttpOnly; SameSite=None; Secure";
  # add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";

  }

  location /websocket {
  proxy_pass http://odoolongpoll;
  proxy_redirect off;
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header Connection \$connection_upgrade;

  }
  location ~* .(js|css|png|jpg|jpeg|gif|ico)$ {
  expires 2d;
  proxy_pass http://odooserver;
  add_header Cache-Control "public, no-transform";
  }
  # cache some static data in memory for 60mins.
  location ~ /[a-zA-Z0-9_-]*/static/ {
  proxy_cache_valid 200 302 60m;
  proxy_cache_valid 404      1m;
  proxy_buffering    on;
  expires 864000;
  proxy_pass http://odooserver;
  }
  }
EOF
        if [ -f "/etc/nginx/conf.d/odoo.conf" ]; then
            sudo rm /etc/nginx/conf.d/odoo.conf
        else
            echo "Odoo Nginx configuration file is at /etc/nginx/conf.d/odoo.conf ..."
        fi

        sudo mv ~/odoo.conf /etc/nginx/conf.d/
        sudo rm /etc/nginx/conf.d/default.conf
        sudo service nginx reload
        sudo su root -c "printf 'proxy_mode = True\n' >> /etc/${OE_CONFIG}.conf"
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
        sudo service nginx reload
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
    sudo su root -c "/etc/init.d/$OE_CONFIG start"
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
