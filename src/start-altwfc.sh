#!/bin/sh

service dnsmasq start
service apache2 start
service mysql start

cd /
chmod 777 /var/www/dwc_network_server_emulator -R
cd var/www/dwc_network_server_emulator
python master_server.py
cd /