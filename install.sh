#!/bin/bash
PHP_VERSION='7.3'
MCRYPT_VERSION='1.0.2'
PMA_VERSION='4.8.4'

MY_PASSWORD_ROOT='ROOTPASSWORD'
MY_PASSWORD_FTP='FTPPASSWORD'
MY_DOMAINS=(samplewebsite.com)
MY_EMAIL='sample@test.com'
MY_PUBLIC_IP=''

cd

## UPDATE SYSTEM ##

sudo apt-get update
sudo apt-get upgrade -y

## ADD ADDITIONAL SOURCES ##

echo "deb http://ftp.debian.org/debian stretch-backports main" | sudo tee -a /etc/apt/sources.list
echo "deb http://nginx.org/packages/mainline/debian/ stretch nginx" | sudo tee -a /etc/apt/sources.list

sudo wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/php${PHP_VERSION}.list

sudo apt-get update
sudo apt-get install lsb-release apt-transport-https ca-certificates -y

## INSTALL NGINX ##

sudo wget http://nginx.org/keys/nginx_signing.key
sudo apt-key add nginx_signing.key

sudo apt-get install nginx -y
sudo systemctl enable nginx

sudo sed -i "s/user  nginx/user  www-data/g" /etc/nginx/nginx.conf

## INSTALL MODULES ##

sudo apt-get install git curl unzip build-essential apache2-utils locales zlib1g-dev libpcre3 libpcre3-dev libmcrypt-dev libjpeg62-turbo-dev libpng-dev libmcrypt-dev libssh2-1 libssh2-1-dev libmagickwand-dev libmagickcore-dev -y

## INSTALL REDIS ##

sudo apt-get install redis-server -y
sudo systemctl start redis-server
sudo systemctl enable redis-server

## INSTALL PHP ##

sudo apt-get install php${PHP_VERSION} php${PHP_VERSION}-cli php${PHP_VERSION}-curl php${PHP_VERSION}-dev php${PHP_VERSION}-fpm php${PHP_VERSION}-gd php${PHP_VERSION}-mysql php${PHP_VERSION}-opcache php${PHP_VERSION}-xml -y

if [ ! -f /etc/php/${PHP_VERSION}/fpm/php.ini.backup ]
then
    sudo cp /etc/php/${PHP_VERSION}/fpm/php.ini /etc/php/${PHP_VERSION}/fpm/php.ini.backup
fi
sudo sed -i "s/session.gc_maxlifetime = 1440/session.gc_maxlifetime = 14400/g" /etc/php/${PHP_VERSION}/fpm/php.ini
sudo sed -i "s/max_execution_time = 30/max_execution_time = 90/g" /etc/php/${PHP_VERSION}/fpm/php.ini


if [ ! -f /etc/php/${PHP_VERSION}/cli/php.ini.backup ]
then
    sudo cp /etc/php/${PHP_VERSION}/cli/php.ini /etc/php/${PHP_VERSION}/cli/php.ini.backup
fi
sudo sed -i "s/session.gc_maxlifetime = 1440/session.gc_maxlifetime = 14400/g" /etc/php/${PHP_VERSION}/cli/php.ini
sudo sed -i "s/max_execution_time = 30/max_execution_time = 90/g" /etc/php/${PHP_VERSION}/cli/php.ini

if [ ! -f /etc/php/${PHP_VERSION}/fpm/conf.d/mcrypt.ini ]
then
printf "\n" | sudo pecl install mcrypt-${MCRYPT_VERSION} -y

echo 'extension=mcrypt.so' | sudo tee -a /etc/php/${PHP_VERSION}/fpm/conf.d/mcrypt.ini
fi

if [ ! -f /etc/php/${PHP_VERSION}/fpm/conf.d/ssh2.ini ]
then
cd
git clone https://github.com/php/pecl-networking-ssh2.git
cd pecl-networking-ssh2
sudo phpize
sudo ./configure
sudo make
sudo make install

echo 'extension=ssh2.so' | sudo tee -a /etc/php/${PHP_VERSION}/fpm/conf.d/ssh2.ini
fi

if [ ! -f /etc/php/${PHP_VERSION}/fpm/conf.d/imagick.ini ]
then
cd 
git clone https://github.com/mkoppanen/imagick.git 
cd imagick
sudo phpize
sudo ./configure
sudo make
sudo make install 

echo 'extension=imagick.so' | sudo tee -a /etc/php/${PHP_VERSION}/fpm/conf.d/imagick.ini
fi

if [ ! -f /etc/php/${PHP_VERSION}/fpm/conf.d/redis.ini ]
then
cd
git clone https://github.com/phpredis/phpredis.git
cd phpredis
sudo phpize
sudo ./configure
sudo make
sudo make install 

echo 'extension=redis.so' | sudo tee -a /etc/php/${PHP_VERSION}/fpm/conf.d/redis.ini
fi

if [ ! -f /etc/php/${PHP_VERSION}/fpm/conf.d/mecab.ini ]
then
cd 
wget 'https://drive.google.com/uc?export=download&id=0B4y35FiV1wh7cENtOXlicTFaRUE' -Omecab-0.996.tar.gz
tar xvf mecab-0.996.tar.gz
cd mecab-0.996
sudo ./configure --with-charset=utf8 --enable-utf8-only
sudo make
sudo make check
sudo make install
sudo ldconfig
cd
wget 'https://drive.google.com/uc?export=download&id=0B4y35FiV1wh7MWVlSDBCSXZMTXM' -Omecab-ipadic-2.7.0-20070801.tar.gz
tar xvf mecab-ipadic-2.7.0-20070801.tar.gz
cd mecab-ipadic-2.7.0-20070801
sudo ./configure --with-charset=utf8
sudo make
sudo make check
sudo make install
cd
git clone https://github.com/rsky/php-mecab.git
cd php-mecab/mecab
sudo phpize
sudo ./configure
sudo make
sudo make install 

echo 'extension=mecab.so' | sudo tee -a /etc/php/${PHP_VERSION}/fpm/conf.d/mecab.ini
fi

sudo systemctl restart php${PHP_VERSION}-fpm
sudo systemctl enable php${PHP_VERSION}-fpm

## INSTALL MYSQL ##

sudo apt-get install mariadb-server mariadb-client -y

sudo mysql -u root << _EOF_
  DELETE FROM mysql.user WHERE User='';
  DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
  DROP DATABASE IF EXISTS test;
  DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
  CREATE USER 'admin'@'localhost' IDENTIFIED BY '${MY_PASSWORD_ROOT}';
  GRANT ALL PRIVILEGES ON * . * TO 'admin'@'localhost';
  FLUSH PRIVILEGES;
_EOF_

if [ -f /etc/mysql/conf.d/mysql.cnf ]
then
    sudo rm /etc/mysql/conf.d/mysql.cnf
fi

sudo tee -a /etc/mysql/conf.d/mysql.cnf << _EOF_
default-character-set = utf8mb4
[client]
default-character-set = utf8mb4
[mysqld]
skip-name-resolve
character-set-server = utf8mb4
collation-server = utf8mb4_general_ci
character-set-client-handshake = FALSE
init-connect='SET NAMES utf8mb4'
_EOF_

sudo systemctl restart mysql

## ADD NGINX TEMPLATE CONF ##
if [ -d /etc/nginx/template ]
then
    cd /etc/nginx/
    sudo rm -Rf template
fi

sudo mkdir /etc/nginx/template

sudo tee -a /etc/nginx/template/params.conf << _EOF_
fastcgi_buffers 16 16k;
fastcgi_buffer_size 32k;
fastcgi_cache_key "\$scheme\$request_method\$host\$request_uri";
set_real_ip_from 127.0.0.1;
real_ip_header X-Forwarded-For;
port_in_redirect off;
tcp_nopush on;
tcp_nodelay on;
types_hash_max_size 2048;
server_tokens off;
client_max_body_size 10m;

gzip on;
gzip_disable "msie6";
gzip_vary on;
gzip_proxied any;
gzip_comp_level 6;
gzip_min_length 256;
gzip_buffers 16 8k;
gzip_http_version 1.1;
gzip_types
	application/atom+xml
	application/ecmascript
	application/javascript
	application/postscript
	application/x-javascript
	application/json
	application/ld+json
	application/manifest+json
	application/rss+xml
	application/vnd.geo+json
	application/vnd.ms-fontobject
	application/x-font-ttf
	application/x-web-app-manifest+json
	application/xhtml+xml
	application/xml
	application/xml+rss
	font/opentype
	image/bmp
	image/svg+xml
	image/x-icon
	text/cache-manifest
	text/css
	text/csv
	text/plain
	text/vcard
	text/vnd.rim.location.xloc
	text/vtt
	text/x-component
	text/x-cross-domain-policy;
_EOF_

sudo tee -a /etc/nginx/template/php.conf << _EOF_
location ~ \.php$ {
    try_files \$uri =404;
    fastcgi_pass unix:/run/php/php${PHP_VERSION}-fpm.sock;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    fastcgi_param SCRIPT_NAME \$fastcgi_script_name;
    include fastcgi_params;
}
_EOF_

sudo tee -a /etc/nginx/template/exploit.conf << _EOF_
    add_header Strict-Transport-Security "max-age=31536000; includeSubdomains; preload";
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Frame-Options "SAMEORIGIN";

    ## Block SQL injections
    set \$block_sql_injections 0;
    if (\$query_string ~ "union.*select.*\(") {
        set \$block_sql_injections 1;
    }
    if (\$query_string ~ "union.*all.*select.*") {
        set \$block_sql_injections 1;
    }
    if (\$query_string ~ "concat.*\(") {
        set \$block_sql_injections 1;
    }
    if (\$block_sql_injections = 1) {
        return 403;
    }

    ## Block user agents
    set \$block_user_agents 0;

    # Disable Akeeba Remote Control 2.5 and earlier
    if (\$http_user_agent ~ "Indy Library") {
        set \$block_user_agents 1;
    }

    # Common bandwidth hoggers and hacking tools.
    if (\$http_user_agent ~ "libwww-perl") {
        set \$block_user_agents 1;
    }
    if (\$http_user_agent ~ "GetRight") {
        set \$block_user_agents 1;
    }
    if (\$http_user_agent ~ "GetWeb!") {
        set \$block_user_agents 1;
    }
    if (\$http_user_agent ~ "Go!Zilla") {
        set \$block_user_agents 1;
    }
    if (\$http_user_agent ~ "Download Demon") {
        set \$block_user_agents 1;
    }
    if (\$http_user_agent ~ "Go-Ahead-Got-It") {
        set \$block_user_agents 1;
    }
    if (\$http_user_agent ~ "TurnitinBot") {
        set \$block_user_agents 1;
    }
    if (\$http_user_agent ~ "GrabNet") {
        set \$block_user_agents 1;
    }

    if (\$block_user_agents = 1) {
        return 403;
    }
_EOF_

sudo tee -a /etc/nginx/template/expire.conf << _EOF_
location ~* \.(jpg|jpeg|gif|png|css|js|ico|svg)$ {
	access_log        off;
	log_not_found     off;
	expires           30d;
}
_EOF_

sudo tee -a /etc/nginx/template/wp_sitemap.conf << _EOF_
location ~ ([^/]*)sitemap(.*)\.x(m|s)l\$ {
    rewrite ^/sitemap\.xml\$ /index.php?sitemap=1 last;
    rewrite ^/([a-z]+)?-?sitemap\.xsl\$ /index.php?xsl=\$1 last;
    rewrite ^/sitemap_index\.xml\$ /index.php?sitemap=1 last;
    rewrite ^/([^/]+?)-sitemap([0-9]+)?\.xml\$ /index.php?sitemap=\$1&sitemap_n=\$2 last;

    ## following lines are options. Needed for wordpress-seo addons
    rewrite ^/news_sitemap\.xml\$ /index.php?sitemap=wpseo_news last;
    rewrite ^/locations\.kml\$ /index.php?sitemap=wpseo_local_kml last;
    rewrite ^/geo_sitemap\.xml\$ /index.php?sitemap=wpseo_local last;
    rewrite ^/video-sitemap\.xsl\$ /index.php?xsl=video last;
    access_log off;
}
_EOF_

## MAKE WEB DIRECTORIES ##
if [ -f /etc/nginx/conf.d/default.conf ]
then
    sudo rm /etc/nginx/conf.d/default.conf
fi

if [ -f /etc/nginx/conf.d/0default.conf ]
then
    sudo rm /etc/nginx/conf.d/0default.conf
fi

sudo tee -a /etc/nginx/conf.d/0default.conf << _EOF_
server {
    listen 80 default_server;

    root /var/www/root;

    index index.php index.html index.htm;

    server_name _;

    location / {
        auth_basic "Administrator Login";
        auth_basic_user_file /var/password/.htpasswd;

        try_files \$uri \$uri/ \$uri.php;
    }
    
    include template/php.conf;
}
_EOF_

if [ -d /var/www/root ]
then
    cd /var/www/
    sudo rm -Rf root
fi

sudo mkdir -p /var/www/root/

echo '<?php phpinfo(); ?>' | sudo tee -a /var/www/root/index.php


if [ -d /var/password ]
then
    cd /var/
    sudo rm -Rf password
fi

sudo mkdir -p /var/password/

sudo htpasswd -b -c /var/password/.htpasswd root ${MY_PASSWORD_ROOT}

if [ ! -d /var/www/sites ]
then
    sudo mkdir -p /var/www/sites
fi

for domain in ${MY_DOMAINS[*]}
do
    if [ ! -d /var/www/${domain} ]
    then
        sudo mkdir -p /var/www/sites/${domain}/public_html/
    fi

    if [ -f /etc/nginx/conf.d/${domain}.conf ]
    then
        sudo rm /etc/nginx/conf.d/${domain}.conf
    fi

sudo tee -a /etc/nginx/conf.d/${domain}.conf << _EOF_
server {
    listen 80;

    root /var/www/sites/${domain}/public_html;
    index index.php index.html index.htm;

    server_name ${domain}
                www.${domain};

    include template/php.conf;

    location / {
        try_files \$uri \$uri/ /index.php?q=\$uri&\$args;
    }
}
_EOF_

done

sudo systemctl reload nginx

sudo apt-get install python-certbot-nginx -t stretch-backports -y

for domain in ${MY_DOMAINS[*]}
do

    sudo certbot certonly -n --keep-until-expiring --agree-tos --nginx -m ${MY_EMAIL} -d ${domain} -d www.${domain}
    sudo rm /etc/nginx/conf.d/${domain}.conf

sudo tee -a /etc/nginx/conf.d/${domain}.conf << _EOF_
include template/params.conf;

server {
    listen 443 ssl http2;

    root /var/www/sites/${domain}/public_html;
    index index.php index.html index.htm;

    server_name ${domain}
                www.${domain};

    include template/php.conf;
    include template/exploit.conf;
    include template/wp_sitemap.conf;

    location / {
        try_files \$uri \$uri/ /index.php?q=\$uri&\$args;
    }

    rewrite /wp-admin$ \$scheme://\$host\$uri/ permanent;

    listen 443 ssl; # managed by Certbot
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem; # managed by Certbot
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem; # managed by Certbot
    include /etc/letsencrypt/options-ssl-nginx.conf; # managed by Certbot
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem; # managed by Certbot
}

server {
    listen 80;
    server_name ${domain} www.${domain};
    return 301 https://www.${domain}$request_uri;
}
_EOF_

done


## ADD PHPMYDADMIN ##

cd /var/www/root/

sudo wget https://files.phpmyadmin.net/phpMyAdmin/${PMA_VERSION}/phpMyAdmin-${PMA_VERSION}-all-languages.zip

sudo unzip phpMyAdmin-${PMA_VERSION}-all-languages.zip
sudo mv phpMyAdmin-${PMA_VERSION}-all-languages phpmyadmin

## ATTRIBUTE OWNER FOR WEB DIRECTORIES ##

cd /var/www/

sudo chown www-data:www-data -Rf root
sudo chown www-data:www-data -Rf sites

sudo systemctl reload nginx

## INSTALL FTPS ##

if [ ! -d /home/ftpuser ]
then
    sudo useradd -m ftpuser
    echo "ftpuser:${MY_PASSWORD_FTP}" | sudo chpasswd
fi

sudo apt-get install vsftpd -y
sudo systemctl enable vsftpd
sudo systemctl start vsftpd

if [ -d /var/ssl ]
then
    cd /var/
    sudo rm -Rf ssl
fi
sudo mkdir -p /var/ssl

sudo openssl req -x509 -nodes -days 36500 -subj "/C=XX/ST=Country/L=City/CN=default" -newkey rsa:2048 -keyout /var/ssl/vsftpd.pem -out /var/ssl/vsftpd.pem

sudo chmod 600 /var/ssl/vsftpd.pem

if [ -f /etc/vsftpd.chroot_list ]
then
    sudo rm /etc/vsftpd.chroot_list
fi
echo "ftpuser" | sudo tee -a /etc/vsftpd.chroot_list

if [ ! -f /etc/vsftpd.conf.backup ]
then
    sudo mv /etc/vsftpd.conf /etc/vsftpd.conf.backup
else
    sudo rm /etc/vsftpd.conf
fi

sudo tee -a /etc/vsftpd.conf << _EOF_
listen=YES
anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
ascii_upload_enable=YES
ascii_download_enable=YES
chroot_local_user=YES
chroot_list_file=/etc/vsftpd.chroot_list
secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=ftp

allow_writeable_chroot=YES
local_root=/var/www/sites
guest_enable=YES
chown_uploads=YES
chown_username=www-data
guest_username=www-data
nopriv_user=www-data
virtual_use_local_privs=YES

pasv_enable=YES
pasv_min_port=1060
pasv_max_port=1069
pasv_address=${MY_PUBLIC_IP}

rsa_cert_file=/var/ssl/vsftpd.pem
ssl_enable=YES
force_local_data_ssl=YES
force_local_logins_ssl=YES
ssl_tlsv1=YES
ssl_sslv2=NO
ssl_sslv3=NO
_EOF_

sudo systemctl restart vsftpd