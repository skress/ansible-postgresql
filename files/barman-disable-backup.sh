#!/bin/bash

# This script disables backups for the given server name by executing the following steps:
# 1. Renaming the backup config file to end in ".hold" (such that the barman cron job does not use it anymore)
# 2. Stopping a possibly running wal-receive process and dropping the replication slot

SERVER=$1
CONFIG_FILE=/etc/barman.d/${SERVER}.conf

if [ -z "$1" ]; then
  echo "Please specify the backup name which should be stopped."
  echo "Configured backups are: (barman list-server)"
  barman list-server
  exit 1
fi

set -euo pipefail

if [ ! -f  $CONFIG_FILE ]; then
  echo "ERROR: Config file $CONFIG_FILE does not exist."
  exit 1
fi

mv $CONFIG_FILE ${CONFIG_FILE}.hold

su -c "cat /etc/barman.conf ${CONFIG_FILE}.hold | barman --config=/dev/stdin receive-wal --stop --drop-slot $SERVER" barman
