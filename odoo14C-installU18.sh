echo "This Script is for Ubuntu 18.04 and Odoo 14.0 Community Edition"

echo "press CTRL+c is want to cancel installation"
echo "Enter Domain Name 'localhost' if installing in local server"

read -p 'Website Domain Name: ' WEBSITE_NAME
read -p 'Website Admin Email: ' ADMIN_EMAIL
echo .
echo .
echo .
echo "Updating Server"
echo .
echo .
echo .

sudo apt update && sudo apt upgrade -y

# echo "Installing python3.8"
# echo .
# echo .
# echo .
# sudo apt install python3.8 python3.8-dev python3.8-dbg -y
# sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8
# sudo update-alternatives --config python3


echo .
echo .
echo .
echo "Postgresql Installation Started"
echo .
echo .
echo .
sudo apt -yq install postgresql postgis

echo "postgresql installation successfull"

echo .
echo .
echo .


echo "Installing Odoo 14.0 Community Edition"

sudo wget -O - https://nightly.odoo.com/odoo.key | apt-key add -
sudo echo "deb http://nightly.odoo.com/14.0/nightly/deb/ ./" >> /etc/apt/sources.list.d/odoo.list
sudo apt-get update && sudo apt-get -yq install odoo

sudo apt install python3-pip -y
sudo pip3 install xlwt
sudo pip3 install num2words
echo .
echo .
echo .


echo "Installing wkhtmltopdf"
sudo mkdir /tmp
sudo wget https://github.com/wkhtmltopdf/packaging/releases/download/0.12.6-1/wkhtmltox_0.12.6-1.bionic_amd64.deb -P /tmp
sudo apt install /tmp/wkhtmltox_0.12.6-1.bionic_amd64.deb -y

echo .
echo .
echo .


echo "Installing nginx"

sudo apt install nginx -y



cat <<EOF > /tmp/odoo
  upstream odooserver {
 server 127.0.0.1:8069;
}

server {
    listen      80;
    listen [::]:80;
    server_name $WEBSITE_NAME;

    proxy_buffers 16 64k;
    proxy_buffer_size 128k;

    proxy_next_upstream error timeout invalid_header http_500 http_502 http_503 http_504;

    location / {
        proxy_pass  http://odooserver;
    }

    location ~* /web/static/ {
        proxy_cache_valid 200 60m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odooserver;
    }

    location ~* /website/image/ir.attachment/ {
        proxy_cache_valid 200 60m;
        proxy_buffering on;
        expires 864000;
        proxy_pass http://odooserver;
    }

    gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript;
    gzip on;
}

EOF


  sudo mv /tmp/odoo /etc/nginx/sites-available/
  sudo ln -s /etc/nginx/sites-available/odoo /etc/nginx/sites-enabled/odoo
  sudo rm /etc/nginx/sites-enabled/default
  sudo service nginx reload
  sudo su root -c "printf 'proxy_mode = True\n' >> /etc/odoo/odoo.conf"
  echo "Done! The Nginx server is up and running. Configuration can be found at /etc/nginx/sites-available/odoo"

sudo add-apt-repository ppa:certbot/certbot -y && sudo apt-get update -y
sudo apt-get install python3-certbot-nginx -y
if [ $WEBSITE_NAME == "localhost" ]
then
   echo "$WEBSITE_NAME is not valid for issueing SSL certificate"
   echo .
   echo .
   echo .
   echo "But we can access odoo via $WEBSITE_NAME:8069"
else
    sudo certbot --nginx -d $WEBSITE_NAME --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect ; sudo service nginx reload
   echo "Success!!"
   echo "A SSL certificate has been issued to $WEBSITE_NAME"
   echo .
   echo .
   echo .
   echo "Now we can access odoo via $WEBSITE_NAME"
fi