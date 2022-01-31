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

ARG ADMIN_USERNAME="admin"
ARG ADMIN_PASSWORD="opensesame"

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
        build-essential \
        curl \
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
    # with this command, you can switch openssl libraries
    echo "/usr/local/openssl/lib" > /etc/ld.so.conf.d/usr.local.openssl.lib.conf && ldconfig && \
    ./configure --enable-ssl --with-ssl=/usr/local/openssl/ && make

###
### Create dummy certificate files
###
FROM debian:11 AS builder_dummy-certs
RUN mkdir /dummy-certs && cd /dummy-certs/ && \
    \
    apt update && apt -y install \
        curl \
        openssl && \
    \
    curl https://larsenv.github.io/NintendoCerts/WII_NWC_1_CERT.p12 -O && \
    openssl pkcs12 -in WII_NWC_1_CERT.p12 -passin pass:alpine -passout pass:alpine -out keys.txt && \
    sed -n '7,29p' keys.txt > nwc.crt && \
    sed -n '33,50p' keys.txt > nwc.key && \
    openssl genrsa -out server.key 1024 && \
    echo "US\nWashington\nRedmond\nNintendo of America Inc.\nNintendo Wifi Network\n*.*.*\nca@noa.nintendo.com\n\n\n" | openssl req -new -key server.key -out server.csr && \
    openssl x509 -req -in server.csr -CA nwc.crt -CAkey nwc.key -CAcreateserial -out server.crt -days 3650 -sha1 -passin pass:alpine && \
    rm WII_NWC_1_CERT.p12 keys.txt nwc.key nwc.srl server.csr

FROM debian:11 AS builder_pkmn-classic-framework
ENV WINE_MONO_VERSION="7.0.0"
RUN cd / && \
    \
    #
    # Install dependencies
    #
    apt update && apt -y install \
        curl \
        git \
        gnupg \
        gnupg1 \
        gnupg2 \
        mariadb-server \
        mono-complete \
        nuget \
        sqlite3 \
        xz-utils && \
    \
    #
    # Install Wine
    # info: https://wiki.winehq.org/Debian
    #
    dpkg --add-architecture i386 && \
    curl https://dl.winehq.org/wine-builds/winehq.key -O && \
    apt-key add winehq.key && \
    echo "deb https://dl.winehq.org/wine-builds/debian/ bullseye main" >> /etc/apt/sources.list && \
    apt update && apt -y install --install-recommends winehq-devel && \
    rm winehq.key && \
    \
    #
    # Install Wine Mono
    # info: https://wiki.winehq.org/Mono
    #
    curl https://dl.winehq.org/wine/wine-mono/$WINE_MONO_VERSION/wine-mono-$WINE_MONO_VERSION-x86.tar.xz -O && \
    tar xfv wine-mono-$WINE_MONO_VERSION-x86.tar.xz && \
    mkdir -p /usr/share/wine/mono && \
    mv wine-mono-$WINE_MONO_VERSION/ /usr/share/wine/mono/ && \
    rm wine-mono-$WINE_MONO_VERSION-x86.tar.xz && \
    \
    #
    # Clone & build pkmn-classic-framework repository
    #
    git clone --depth 1 https://github.com/mm201/pkmn-classic-framework.git && \
    cd pkmn-classic-framework/ && \
    # hacky tweeks to clone submodule without generating new ssh key
    sed -i -e 's/git@github\.com:/https:\/\/github\.com\//g' .gitmodules && git submodule update --init && \
    find ./ -name *.config | xargs -n 1 sed -i -e 's/connectionString="Server=gts;/connectionString="Server=localhost;/g' && \
    # Replace System.Web.Entity with System.Web.Http.Common
    # reference: https://stackoverflow.com/questions/27326382/mvc-5-on-mono-could-not-load-file-or-assembly-system-web-entity-or-one-of-its
    cd gts/ && \
    sed -i -e 's/<Reference Include=\"System.Web.Entity\" \/>//g' gts.csproj && \
    nuget install System.Web.Http.Common && \
    # Don't know why, only debug build of VeekunImport.exe can be executed.
    # Disable annoying debug option
    # line: 536
    cd ../VeekunImport/ && \
    sed -i -e 's/Console.ReadKey();//g' Program.cs && \
    cd ../ && \
    # Build
    nuget restore || true && \
    cd VeekunImport/ && xbuild /p:Configuration=Debug && cd - && \
    cd gts/ && xbuild /p:Configuration=Release /p:OutDir=publish/ && \
    \
    #
    # Extract veekun-pokedex and dump database
    #
    cd /&& \
    curl http://veekun.com/static/pokedex/downloads/veekun-pokedex.sqlite.gz -LO && \
    gzip -d veekun-pokedex.sqlite.gz && \
    mv veekun-pokedex.sqlite pkmn-classic-framework/VeekunImport/bin/Debug/pokedex.sqlite && \
    echo "[mysqld]\nlower_case_table_names=1" >> /etc/mysql/my.cnf && \
    service mariadb start && \
    echo "CREATE DATABASE gts; CREATE USER gts@localhost IDENTIFIED BY 'gts'; GRANT ALL ON *.* TO gts@localhost;" | mysql --user=root && \
    mysql --user=root --password= --database=gts < pkmn-classic-framework/library/database.sql && \
    cd pkmn-classic-framework/VeekunImport/bin/Debug/ && wine VeekunImport.exe && \
    cd / && mysqldump --user=root gts > gts_dump.sql

FROM debian:11
ARG VERSION_OPENSSL
ARG VERSION_HTTPD

# Install requirements for CoWFC
RUN apt update && apt install -y \
        apache2 \
        apt-transport-https \
        ca-certificates \
        curl \
        dnsmasq \
        git \
        libapache2-mod-mono \
        lsb-release \
        mono-complete \
        mono-xsp \
        net-tools \
        python2.7 \
        python3-software-properties \
        software-properties-common \
        vim && \
    ln -s /usr/bin/python2.7 /usr/bin/python && \
    curl https://bootstrap.pypa.io/pip/2.7/get-pip.py -O && python get-pip.py && pip install twisted && rm get-pip.py && \
    curl https://packages.sury.org/php/apt.gpg -o /etc/apt/trusted.gpg.d/php.gpg && \
    echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" | tee /etc/apt/sources.list.d/php.list && \
    apt update && apt -y install \
        mariadb-server \
        php7.4 \
        php7.4-mysql \
        php7.4-sqlite3 \
        sqlite3

# Clone repositories
RUN cd /var/www/ && \
    git clone https://github.com/EnergyCube/CoWFC.git && \
    git clone https://github.com/EnergyCube/dwc_network_server_emulator.git && \
    echo "\npokemondpds\t2\tRwBpAHIAYQBmAGYAZQA_" >> dwc_network_server_emulator/gamestats.cfg && \
    chmod 777 /var/www/dwc_network_server_emulator/ -R

# Copy DNS config
COPY src/dnsmasq/dnsmasq.conf /etc/dnsmasq.conf

# Make dummy certificates
COPY --from=builder_dummy-certs /dummy-certs /
RUN mkdir /etc/apache2/certs && \
    cp /dummy-certs/server.crt /etc/apache2/certs/ && \
    cp /dummy-certs/server.key /etc/apache2/certs/ && \
    cp /dummy-certs/nwc.crt /etc/apache2/certs/ && \
    rm -rf /dummy-certs

# Build OpenSSL with SSLv3
COPY --from=builder_openssl /$VERSION_OPENSSL /
COPY --from=builder_openssl /$VERSION_HTTPD /
RUN apt update && apt -y install \
        build-essential && \
    cd /$VERSION_OPENSSL && make install_sw && make install_ssldirs && \
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

ARG ADMIN_USERNAME
ARG ADMIN_PASSWORD
RUN service mariadb start && \
    #
    # CoWFC admin page setting
    #
    echo "CREATE DATABASE cowfc; CREATE USER 'cowfc'@'localhost' IDENTIFIED BY 'cowfc'; GRANT ALL PRIVILEGES ON *.* TO 'cowfc'@'localhost'; FLUSH PRIVILEGES;" | mysql --user=root && \
    mysql --user=root --password= --database=cowfc < /var/www/CoWFC/SQL/cowfc.sql && \
    echo "INSERT INTO users (Username, Password, Rank) VALUES ('$ADMIN_USERNAME','`/var/www/CoWFC/SQL/bcrypt-hash "$ADMIN_PASSWORD"`','1');" | mysql --user=root --database=cowfc && \
    sed -i -e "s/db_user = root/db_user = cowfc/g" /var/www/html/config.ini && \
    sed -i -e "s/db_pass = passwordhere/db_pass = cowfc/g" /var/www/html/config.ini

# Finish CoWFC installation
COPY src/start-altwfc.sh /start-altwfc.sh
RUN mv /var/www/html/config.ini /var/www/config.ini && \
    touch /etc/.dwc_installed

# Install pkmn-classic-framework
COPY --from=builder_pkmn-classic-framework /pkmn-classic-framework /
COPY --from=builder_pkmn-classic-framework /gts_dump.sql /
RUN mv /pkmn-classic-framework/gts/publish/_PublishedWebsites/gts/* /var/www/gamestats2.gs.nintendowifi.net/ && \
    service mariadb start && \
    echo "CREATE DATABASE gts; CREATE USER 'gts'@'localhost' IDENTIFIED BY 'gts'; GRANT ALL ON *.* TO 'gts'@'localhost';" | mysql --user=root && \
    mysql --user=root --password= --database=gts < /gts_dump.sql

CMD ["/bin/sh"]
# CMD apachectl start && \
#     service dnsmasq start && \
#     service mysql start && \
#     bash /start-altwfc.sh
