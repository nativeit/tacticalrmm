#!/bin/bash

SCRIPT_VERSION="7"
SCRIPT_URL='https://raw.githubusercontent.com/wh1te909/tacticalrmm/master/backup.sh'

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

TMP_FILE=$(mktemp -p "" "rmmbackup_XXXXXXXXXX")
curl -s -L "${SCRIPT_URL}" > ${TMP_FILE}
NEW_VER=$(grep "^SCRIPT_VERSION" "$TMP_FILE" | awk -F'[="]' '{print $3}')

if [ "${SCRIPT_VERSION}" -ne "${NEW_VER}" ]; then
    printf >&2 "${YELLOW}A newer version of this backup script is available.${NC}\n"
    printf >&2 "${YELLOW}Please download the latest version from ${GREEN}${SCRIPT_URL}${YELLOW} and re-run.${NC}\n"
    rm -f $TMP_FILE
    exit 1
fi
if [ $EUID -eq 0 ]; then
  echo -ne "\033[0;31mDo NOT run this script as root. Exiting.\e[0m\n"
  exit 1
fi

#####################################################

POSTGRES_USER="changeme"
POSTGRES_PW="hunter2"

#####################################################

if [[ "$POSTGRES_USER" == "changeme" || "$POSTGRES_PW" == "hunter2" ]]; then
  printf >&2 "${RED}You must change the postgres username/password at the top of this file.${NC}\n"
  printf >&2 "${RED}Check the github readme for where to find them.${NC}\n"
  exit 1
fi

if [ ! -d /rmmbackups ]; then
    sudo mkdir /rmmbackups
    sudo chown ${USER}:${USER} /rmmbackups
fi

if [ -d /meshcentral/meshcentral-backup ]; then
    rm -f /meshcentral/meshcentral-backup/*
fi

if [ -d /meshcentral/meshcentral-coredumps ]; then
    rm -f /meshcentral/meshcentral-coredumps/*
fi

printf >&2 "${GREEN}Running postgres vacuum${NC}\n"
sudo -u postgres psql -d tacticalrmm -c "vacuum full logs_auditlog"
sudo -u postgres psql -d tacticalrmm -c "vacuum full logs_pendingaction"
sudo -u postgres psql -d tacticalrmm -c "vacuum full agents_agentoutage"

dt_now=$(date '+%Y_%m_%d__%H_%M_%S')
tmp_dir=$(mktemp -d -t tacticalrmm-XXXXXXXXXXXXXXXXXXXXX)
sysd="/etc/systemd/system"

mkdir -p ${tmp_dir}/meshcentral/mongo
mkdir ${tmp_dir}/postgres
mkdir ${tmp_dir}/certs
mkdir ${tmp_dir}/nginx
mkdir ${tmp_dir}/systemd
mkdir ${tmp_dir}/rmm
mkdir ${tmp_dir}/confd


pg_dump --dbname=postgresql://"${POSTGRES_USER}":"${POSTGRES_PW}"@127.0.0.1:5432/tacticalrmm | gzip -9 > ${tmp_dir}/postgres/db-${dt_now}.psql.gz

tar -czvf ${tmp_dir}/meshcentral/mesh.tar.gz --exclude=/meshcentral/node_modules /meshcentral
mongodump --gzip --out=${tmp_dir}/meshcentral/mongo

sudo tar -czvf ${tmp_dir}/certs/etc-letsencrypt.tar.gz -C /etc/letsencrypt .

sudo tar -czvf ${tmp_dir}/nginx/etc-nginx.tar.gz -C /etc/nginx .

sudo tar -czvf ${tmp_dir}/confd/etc-confd.tar.gz -C /etc/conf.d .

sudo cp ${sysd}/rmm.service ${sysd}/celery.service ${sysd}/celerybeat.service ${sysd}/meshcentral.service ${sysd}/nats.service ${sysd}/natsapi.service ${tmp_dir}/systemd/

cat /rmm/api/tacticalrmm/tacticalrmm/private/log/debug.log | gzip -9 > ${tmp_dir}/rmm/debug.log.gz
cp /rmm/api/tacticalrmm/tacticalrmm/local_settings.py /rmm/api/tacticalrmm/app.ini ${tmp_dir}/rmm/
cp /rmm/web/.env ${tmp_dir}/rmm/env
cp /rmm/api/tacticalrmm/tacticalrmm/private/exe/mesh*.exe ${tmp_dir}/rmm/

tar -cf /rmmbackups/rmm-backup-${dt_now}.tar -C ${tmp_dir} .

rm -rf ${tmp_dir}

echo -ne "${GREEN}Backup saved to /rmmbackups/rmm-backup-${dt_now}.tar${NC}\n"