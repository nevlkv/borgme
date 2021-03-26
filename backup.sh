#!/bin/sh
do_borg() {
 echo -e "Starting borg backup " 2>>  ${BORG_LOG}
 borg create -v --stats "ssh://${BORG_USER}@${BORG_HOST}:23/./${BORG_ARCHIVE}::${dt}" ${SOURCE_DIR}/${BORG_CUSTOM_FILTER} 2>> ${BORG_LOG}
 BORG_RESULT=$?
 if [ "${BORG_RESULT}" -ne "0" ]; then
  echo -e "Borg backup failed !\n Set dry-run mode" 2>>  ${BORG_LOG}
  # if store to backup failed, not delete local, and not purge from remote
  BORG_PRUNE_OPTIONS="--dry-run"
  BACKUP_STORE_TIME=180
 fi
 echo -e "Borg purge backup \n" 2>>  ${BORG_LOG}
 find ${SOURCE_DIR} -name "*.gz" -mtime +${BACKUP_STORE_TIME} -delete 2>> ${BORG_LOG}
 borg prune -v --list ${BORG_PRUNE_OPTIONS} --keep-daily=${BORG_KEEP_DAYS} --keep-monthly=${BORG_KEEP_MONTH}   ssh://${BORG_USER}@${BORG_HOST}:23/./${BORG_ARCHIVE} 2>> ${BORG_LOG}
}

do_event() {
URL_MESSAGE=https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage
URL_DOCUMENT=https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument
RESULT="success"
if [ "${BORG_RESULT}" -ne "0" ]; then
 RESULT="failed"
 DISABLE_NOTIFICATION="false"
fi
 #curl -F chat_id="$TELEGRAM_CHAT_ID" -F parse_mode="markdown" -F text="*Backup ${INSTANCE}::${SOURCE_DIR} ${RESULT}*" -F disable_notification="${DISABLE_NOTIFICATION}"  ${URL_MESSAGE}
 curl -F chat_id="$TELEGRAM_CHAT_ID" -F document=@"${BORG_LOG}" -F caption="Backup ${INSTANCE}::${SOURCE_DIR} ${RESULT}" ${URL_DOCUMENT}
}

dt=`date +%Y%m%d_%H%M`
BORG_KEEP_DAYS=${BORG_KEEP_DAYS:-7}
BORG_KEEP_MONTH=${BORG_KEEP_MONTH:-1}
BACKUP_STORE_TIME=${BACKUP_STORE_TIME:-7}
BORG_ARCHIVE=${BORG_ARCHIVE:-backup}
BORG_RESULT=0
BORG_LOG="/tmp/borg_${dt}.log"
DISABLE_NOTIFICATION=true
BORG_CUSTOM_FILTER=""

if [ ${BORG_DATE_FILTER} ]; then
 BORG_CUSTOM_FILTER=$(ls -1 -t ${SOURCE_DIR} | head -1) 
fi

do_borg
if [ ! -z $TELEGRAM_BOT_TOKEN ] && [ ! -z ${TELEGRAM_CHAT_ID} ] ; then
 do_event
fi
