#!/bin/bash

# https://qiita.com/keys/items/61eb02bd7396cda0d548
# https://flewkey.com/blog/2020-07-12-nds-constraint.html

openssl_latest="openssl-1.1.1l"
httpd_latest="httpd-2.4.38"

apt -y install curl build-essential libapr1-dev libaprutil1-dev libpcre3-dev

cd /
curl https://www.openssl.org/source/$openssl_latest.tar.gz -O
curl http://archive.apache.org/dist/httpd/$httpd_latest.tar.bz2 -O

cd /
tar zxvf $openssl_latest.tar.gz
cd $openssl_latest
./config --prefix=/usr enable-ssl3 enable-ssl3-method enable-weak-ssl-ciphers
apt -y purge openssl
make install
cp libssl.so /usr/lib/x86_64-linux-gnu/libssl.so
rm -f /usr/lib/x86_64-linux-gnu/libssl.so.1.1
ln -s /usr/lib/x86_64-linux-gnu/libssl.so /usr/lib/x86_64-linux-gnu/libssl.so.1.1
cp libcrypto.so /usr/lib/x86_64-linux-gnu/libcrypto.so
rm -f /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1
ln -s /usr/lib/x86_64-linux-gnu/libcrypto.so /usr/lib/x86_64-linux-gnu/libcrypto.so.1.1

cd /
tar jxvf $httpd_latest.tar.bz2
cd $httpd_latest
./configure --enable-ssl --with-ssl=/usr/lib
make
cp modules/ssl/.libs/mod_ssl.so /usr/lib/apache2/modules/mod_ssl.so