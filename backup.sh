#!/bin/sh
set -x
## 


do_backup_full() {

echo -e "Backup all tables"
pg_dump -v -Z 9 -Fc ${PG_DUMP_OPTIONS} -T 'user_worlds*' -f ${BACKUP_DIR}/${PGDATABASE}_${dt}/full.dump 2> /tmp/pgdump.log
result=$?
rsize=`stat -c %s ${BACKUP_DIR}/${PGDATABASE}_${dt}/full.dump`
dts=`date +%s`
echo "http://${PUSHGW_HOST}/job/${PGDATABASE}_backup/instance/${PGDATABASE}"
echo "Date: ${dts}"
echo "Size: ${rsize}"
echo "Result: ${result}"
log=$(cat /tmp/pgdump.log)
log_url=$(curl -X POST -s -d "$log" http://${HASTE_HOST} | awk -F '"' '{print $4}')
cat << EOF | curl --data-binary @- http://${PUSHGW_HOST}/metrics/job/${PGDATABASE}_backup/instance/${PGDATABASE}
  # TYPE date counter
  last_backup{size="${rsize}", log="${log_url}",result="${result}"} ${dts}
EOF
}

do_rsync() {

#rsync to backup server

echo -e "Do rsync.. "
rsync -av ${BACKUP_DIR}/${PGDATABASE}_${dt}/*.dump ${RSYNC_HOST}::${RSYNC_DIR}/${PGDATABASE}/${dt}

}

do_borg() {
 echo -e "Starting borg backup " 2>>  ${BORG_LOG}
 borg create -v --stats "ssh://${BORG_USER}@${BORG_HOST}:23/./${BORG_ARCHIVE}::${PGDATABASE}_${dt}" ${BACKUP_DIR}/${PGDATABASE}_${dt} 2>>  ${BORG_LOG}
 BORG_RESULT=$?
 if [ "${BORG_RESULT}" -ne "0" ]; then
  echo -e "Borg backup failed !\n Set dry-run mode" 2>>  ${BORG_LOG}
  # if store to backup failed, not delete local, and not purge from remote
  BORG_PRUNE_OPTIONS="--dry-run"
 fi
  echo -e "Borg prune backup \n" 2>>  ${BORG_LOG}
  borg prune -v --list ${BORG_PRUNE_OPTIONS}  --keep-daily=${BORG_KEEP_DAYS}  ssh://${BORG_USER}@${BORG_HOST}:23/./${BORG_ARCHIVE} 2>>  ${BORG_LOG}
}

do_event() {
URL_MESSAGE=https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
URL_DOCUMENT=https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument

RESULT="success"
if [ "${BORG_RESULT}" -ne "0" ]; then
 RESULT="failed"
 DISABLE_NOTIFICATION="false"
fi
 #curl -F chat_id="$TELEGRAM_CHAT_ID" -F parse_mode="markdown" -F text="Backup ${PGDATABASE}::${PGDATABASE}_${dt} *${RESULT}*" -F disable_notification="${DISABLE_NOTIFICATION}"  ${URL_MESSAGE}
 curl -F chat_id="$TELEGRAM_CHAT_ID" -F document=@"${BORG_LOG}" -F caption="Backup ${PGDATABASE} ${RESULT}" ${URL_DOCUMENT}
}

# pg_dump, send statistics to prometheus
PUSHGW_HOST=${PUSHGW_HOST}
HASTE_HOST=${HASTE_HOST}
BACKUP_DIR="/mnt/backup"
BORG_USER=${BORG_USER}
BORG_HOST=${BORG_HOST}
BORG_ARCHIVE=${BORG_ARCHIVE}
BORG_KEEP_DAYS=14
# defaults
dt=`date +%Y%m%d_%H%M%S`
BACKUP_STORE_TIME=${BACKUP_STORE_TIME:-1}
RSYNC_HOST=${RSYNC_HOST}
RSYNC_DIR=${RSYNC_DIR:-pg}
BORG_RESULT=0
BORG_LOG="/tmp/borg_${dt}.log"
PG_DUMP_OPTIONS=${PG_DUMP_OPTIONS:-''}
DISABLE_NOTIFICATION=true
ETCD_SUFFIX=${ETCD_SUFFIX:-"etcd.svc.cluster.local:2379/v2/keys/service"}
ETCD_CLUSTER=${ETCD_CLUSTER:-etcd-cluster}
PATRONI_CLUSTER=${PATRONI_CLUSTER:-m3-patroni}

if [ -z ${BORG_ARCHIVE} ]; then
   echo -e "BORG_ARCHIVE is empty, exit"
   exit 1;
fi

HOST=$(curl -sL http://${ETCD_CLUSTER}.${ETCD_SUFFIX}/${PATRONI_CLUSTER}/members | jq '.' | grep replica | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | uniq)
if [ -n "${HOST}" ]; then
    export PGHOST=${HOST}
else
   echo -e "Replica not set"
   exit 1;
fi


##
find ${BACKUP_DIR} -name *.dump -mtime +${BACKUP_STORE_TIME} -delete
mkdir -p ${BACKUP_DIR}/${PGDATABASE}_${dt}

if [ -z "${DRY_RUN}" ];
then
  do_backup_full
fi

do_${BACKUP_TO}

if [ ! -z $TELEGRAM_BOT_TOKEN ] && [ ! -z ${TELEGRAM_CHAT_ID} ] ; then
 do_event
fi
