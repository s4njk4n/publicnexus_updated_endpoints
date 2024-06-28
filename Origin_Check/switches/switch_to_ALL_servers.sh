#!/bin/bash

# Set Colour Vars
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

bash /root/Origin_Check/origin_check-pause.sh
sleep 10
rm -rf /root/Origin_Check/origin_pool.csv
cp /root/Origin_Check/switches/ALLorigin_pool.csv /root/Origin_Check/origin_pool.csv
bash /root/Origin_Check/origin_check-restart.sh
echo -e "${GREEN} PublicNexus now using all public servers + PublicNexus private backend servers ${NC}"
