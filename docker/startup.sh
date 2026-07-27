#!/bin/bash

if [ -z "${CRON_SCHEDULE}" ]; then
    CRON_SCHEDULE='0 2 1 * *'
fi

if [ -z "${SCRIPT_FLAGS}" ]; then
    SCRIPT_FLAGS='-d -w -c'
fi

if [ -z "${TZ}" ]; then
    TZ='US/Eastern'
fi

if [ "${UPDATE_ON_START}" = "true" ]; then
    curl https://raw.githubusercontent.com/jojo2357/kiwix-zim-updater/main/kiwix-zim-updater.sh -o /kiwix-zim-updater.sh &&\
    chmod +x /kiwix-zim-updater.sh
fi

if [ "${RUN_ON_START}" = "true" ]; then
    /bin/bash /kiwix-zim-updater.sh ${SCRIPT_FLAGS} /data
fi

echo "${CRON_SCHEDULE} /bin/bash /kiwix-zim-updater.sh ${SCRIPT_FLAGS} /data" > /crontab
crontab /crontab

echo "Running cron on schedule '${CRON_SCHEDULE}'"
crond -f
