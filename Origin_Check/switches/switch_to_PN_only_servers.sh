#!/bin/bash

# Set Colour Vars
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

bash /root/Origin_Check/origin_check-pause.sh
sleep 10
rm -rf /root/Origin_Check/origin_pool.csv
rm -rf /etc/apache2/sites-enabled/000-default-le-ssl.conf
cp /root/Origin_Check/switches/PNonly-origin_pool.csv /root/Origin_Check/origin_pool.csv
cp /root/Origin_Check/switches/PNonly-000-default-le-ssl.conf /etc/apache2/sites-enabled/000-default-le-ssl.conf
systemctl reload apache2
bash /root/Origin_Check/origin_check-restart.sh
echo -e "${GREEN} PublicNexus is now using ONLY PublicNexus private backend servers ${NC}"
