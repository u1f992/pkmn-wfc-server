#!/bin/bash

# https://flewkey.com/blog/2020-07-12-nds-constraint.html

mkdir /etc/apache2/certificates

cd /
mkdir nds-constraint/
cd nds-constraint/
curl https://larsenv.github.io/NintendoCerts/WII_NWC_1_CERT.p12 -O
openssl pkcs12 -in WII_NWC_1_CERT.p12 -passin pass:alpine -passout pass:alpine -out keys.txt
sed -n '7,29p' keys.txt > nwc.crt
sed -n '33,50p' keys.txt > nwc.key
cp nwc.crt /etc/apache2/certificates/

openssl genrsa -out server.key 1024
echo -e "US\nWashington\nRedmond\nNintendo of America Inc.\nNintendo Wifi Network\n*.*.*\nca@noa.nintendo.com\n\n\n" | openssl req -new -key server.key -out server.csr
openssl x509 -req -in server.csr -CA nwc.crt -CAkey nwc.key -CAcreateserial -out server.crt -days 3650 -sha1 -passin pass:alpine

cp server.key /etc/apache2/certificates/
cp server.crt /etc/apache2/certificates/
