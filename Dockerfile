# Dockerfile of https://github.com/EnergyCube/cowfc_installer
# 
# `docker build -t pkmn-server .`
# `docker compose up`
# 
# Open ports listed below
# TCP: 53,80,443,8000,9000,9001,9009,9002,9003,9998,27500,27900,27901,28910,29900,29901,29920
# UDP: 2-65535
# 
# Admin URL: http://$IP/?page=admin&section=Dashboard

ARG VERSION_OPENSSL="openssl-1.1.1m"
ARG VERSION_HTTPD="httpd-2.4.52"

###
### Build OpenSSL with SSLv3
###
FROM debian:11 AS builder_openssl
ARG VERSION_OPENSSL
ARG VERSION_HTTPD
RUN cd / && \
    \
    apt update && apt -y install \
        curl \
        build-essential \
        libapr1-dev \
        libaprutil1-dev \
        libpcre3-dev && \
    \
    cd / && \
    curl https://www.openssl.org/source/$VERSION_OPENSSL.tar.gz -O && \
    tar xvf $VERSION_OPENSSL.tar.gz && rm $VERSION_OPENSSL.tar.gz && cd $VERSION_OPENSSL && \
    ./config --prefix=/usr/local/openssl --openssldir=/usr/local/openssl shared enable-ssl3 enable-ssl3-method enable-weak-ssl-ciphers && make install_sw && make install_ssldirs && \
    \
    cd / && \
    curl http://archive.apache.org/dist/httpd/$VERSION_HTTPD.tar.bz2 -O && \
    tar xvf $VERSION_HTTPD.tar.bz2 && rm $VERSION_HTTPD.tar.bz2 && cd $VERSION_HTTPD && \
    ./configure --enable-ssl --with-ssl=/usr/local/openssl/lib && make
###
### Create dummy certificate files
###
FROM debian:11 AS builder_dummy-certs
RUN apt update && apt -y install \
        curl \
        openssl &&\
    \
    mkdir /dummy-certs && cd /dummy-certs/ && \
    curl https://larsenv.github.io/NintendoCerts/WII_NWC_1_CERT.p12 -O && \
    openssl pkcs12 -in WII_NWC_1_CERT.p12 -passin pass:alpine -passout pass:alpine -out keys.txt && \
    sed -n '7,29p' keys.txt > nwc.crt && \
    sed -n '33,50p' keys.txt > nwc.key && \
    openssl genrsa -out server.key 1024 && \
    echo "US\nWashington\nRedmond\nNintendo of America Inc.\nNintendo Wifi Network\n*.*.*\nca@noa.nintendo.com\n\n\n" | openssl req -new -key server.key -out server.csr && \
    openssl x509 -req -in server.csr -CA nwc.crt -CAkey nwc.key -CAcreateserial -out server.crt -days 3650 -sha1 -passin pass:alpine && \
    rm WII_NWC_1_CERT.p12 keys.txt nwc.key nwc.srl server.csr

FROM debian:11 AS builder_pkmn-classic-framework

FROM debian:10
ARG VERSION_OPENSSL
ARG VERSION_HTTPD

# Install requirements for CoWFC
RUN apt update && \
    apt install -y vim wget curl git net-tools dnsmasq apache2 software-properties-common && \
    apt install -y python3-software-properties python2.7 python-twisted && \
    apt -y install lsb-release apt-transport-https ca-certificates && \
    wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg && \
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list && \
    apt update && \
    apt -y install php7.4 && \
    apt update && \
    apt -y install mariadb-server && \
    apt -y install php7.4-mysql && \
    apt -y install sqlite php7.4-sqlite3

# Install requirements for pkmn-classic-framework
COPY src/pkmn-classic-framework/ /pkmn-classic-framework/
RUN apt update && \
    apt install -y gnupg gnupg2 gnupg1 libapache2-mod-mono mono-complete mono-xsp && \
    wget http://veekun.com/static/pokedex/downloads/veekun-pokedex.sqlite.gz

# Install Wine(https://wiki.winehq.org/Debian)
RUN dpkg --add-architecture i386 && \
    # wget -nc https://download.opensuse.org/repositories/Emulators:/Wine:/Debian/Debian_10/Release.key && \
    # apt-key add Release.key && \
    # echo "deb https://download.opensuse.org/repositories/Emulators:/Wine:/Debian/Debian_10 ./" >> /etc/apt/sources.list && \
    wget -nc https://dl.winehq.org/wine-builds/winehq.key && \
    apt-key add winehq.key && \
    echo "deb https://dl.winehq.org/wine-builds/debian/ buster main" >> /etc/apt/sources.list && \
    apt update && \
    apt -y install --install-recommends winehq-devel

# Install Wine Mono(https://wiki.winehq.org/Mono)
RUN wget https://dl.winehq.org/wine/wine-mono/7.0.0/wine-mono-7.0.0-x86.tar.xz && \
    tar Jxfv wine-mono-7.0.0-x86.tar.xz && \
    mkdir -p /usr/share/wine/mono && \
    cp -r wine-mono-7.0.0/ /usr/share/wine/mono/

# Clone repositories
RUN cd /var/www/ && \
    git clone https://github.com/EnergyCube/CoWFC.git && \
    git clone https://github.com/EnergyCube/dwc_network_server_emulator.git && \
    rm -rf ./dwc_network_server_emulator/dlc/* && \
    echo "\npokemondpds\t2\tRwBpAHIAYQBmAGYAZQA_" >> ./dwc_network_server_emulator/gamestats.cfg && \
    chmod 777 /var/www/dwc_network_server_emulator/ -R

# Copy DNS config
COPY src/dnsmasq/dnsmasq.conf /etc/dnsmasq.conf

# Make certificate
COPY src/make-certificate.sh /make-certificate.sh
RUN chmod +x /make-certificate.sh && \
    /make-certificate.sh

# # Build OpenSSL with SSLv3
# COPY src/build-openssl.sh /build-openssl.sh
# RUN chmod +x /build-openssl.sh && \
#     /build-openssl.sh
COPY --from=builder_openssl /$VERSION_OPENSSL /
COPY --from=builder_openssl /$VERSION_HTTPD /
RUN cd /$VERSION_OPENSSL && make install_sw && make install_ssldirs && \
    cd /$VERSION_HTTPD && cp modules/ssl/.libs/mod_ssl.so /usr/lib/apache2/modules/ && \
    rm -rf /$VERSION_OPENSSL && \
    rm -rf /$VERSION_HTTPD

# Enable Apache virtualhost config
COPY src/apache/conntest.nintendowifi.net.conf /etc/apache2/sites-available/conntest.nintendowifi.net.conf
COPY src/apache/dls1.nintendowifi.net.conf /etc/apache2/sites-available/dls1.nintendowifi.net.conf
COPY src/apache/gamestats.gs.nintendowifi.net.conf /etc/apache2/sites-available/gamestats.gs.nintendowifi.net.conf
COPY src/apache/gamestats2.gs.nintendowifi.net.conf /etc/apache2/sites-available/gamestats2.gs.nintendowifi.net.conf
#COPY src/apache/nas.nintendowifi.net.conf /etc/apache2/sites-available/nas.nintendowifi.net.conf
COPY src/apache/nas.nintendowifi.net-ssl.conf /etc/apache2/sites-available/nas.nintendowifi.net.conf
COPY src/apache/naswii.nintendowifi.net.conf /etc/apache2/sites-available/naswii.nintendowifi.net.conf
COPY src/apache/sake.gs.nintendowifi.net.conf /etc/apache2/sites-available/sake.gs.nintendowifi.net.conf
COPY src/apache/ssl.conf /etc/apache2/mods-available/ssl.conf
COPY src/apache/ssl.load /etc/apache2/mods-available/ssl.load
RUN mkdir /var/www/gamestats2.gs.nintendowifi.net
RUN echo "ServerName localhost\nHttpProtocolOptions Unsafe LenientMethods Allow0.9" >> /etc/apache2/apache2.conf && \
    a2dismod mpm_event && \
    a2enmod proxy proxy_http "php7.4" ssl && \
    a2ensite *.nintendowifi.net.conf && \
    apachectl graceful

# Install Website
RUN rm -rf /var/www/html && \
    mkdir /var/www/html && \
    cp /var/www/CoWFC/Web/* /var/www/html -R && \
    chmod 777 /var/www/html/bans.log && \
    service apache2 restart && \
    touch /var/www/dwc_network_server_emulator/gpcm.db && \
    chmod 777 /var/www/dwc_network_server_emulator/ -R && \
    sed -i -e "s/recaptcha_enabled = 1/recaptcha_enabled = 0/g" /var/www/html/config.ini

# Config database
# first user='admin'
# password='opensesame'
# DB password='cowfc'
RUN service mysql start && \
    echo "Create database cowfc" | mysql -u root && \
    mysql -u root cowfc </var/www/CoWFC/SQL/cowfc.sql && \
    echo "INSERT INTO users (Username, Password, Rank) VALUES ('admin','`/var/www/CoWFC/SQL/bcrypt-hash "opensesame"`','1');" | mysql -u root cowfc && \
    echo "CREATE USER 'cowfc'@'localhost' IDENTIFIED BY 'cowfc';" | mysql -u root && \
    echo "GRANT ALL PRIVILEGES ON *.* TO 'cowfc'@'localhost';" | mysql -u root && \
    echo "FLUSH PRIVILEGES;" | mysql -u root && \
    sed -i -e "s/db_user = root/db_user = cowfc/g" /var/www/html/config.ini && \
    sed -i -e "s/db_pass = passwordhere/db_pass = cowfc/g" /var/www/html/config.ini

# Finish CoWFC installation
COPY src/start-altwfc.sh /start-altwfc.sh
RUN mv /var/www/html/config.ini /var/www/config.ini && \
    touch /etc/.dwc_installed

# Config database
COPY src/config-gts.sql /config-gts.sql
RUN echo "[mysqld]\nlower_case_table_names=1" >> /etc/mysql/my.cnf && \
    gzip -d veekun-pokedex.sqlite.gz && \
    cp veekun-pokedex.sqlite /pkmn-classic-framework/VeekunImport/bin/Release/pokedex.sqlite && \
    service mysql start && \
    mysql < config-gts.sql && \
    mysql --user=root --password= --database=gts < /pkmn-classic-framework/library/database.sql && \
    ln -s /pkmn-classic-framework/packages/System.Data.SQLite.Core.1.0.94.0/build/net451/x64/SQLite.Interop.dll /pkmn-classic-framework/VeekunImport/bin/Release/SQLite.Interop.dll && \
    cd /pkmn-classic-framework/VeekunImport/bin/Release/ && wine VeekunImport.exe

# Install ASP.NET Websites
RUN cp -r /pkmn-classic-framework/publish/* /var/www/gamestats2.gs.nintendowifi.net/

CMD apachectl start && \
    service dnsmasq start && \
    service mysql start && \
    bash /start-altwfc.sh
