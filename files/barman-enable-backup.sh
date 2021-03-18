#!/bin/bash

# This script enables backups for the given server name by renaming the conf file which
# needs to end in '.conf.hold' to end in '.conf' such that the cron job will start running
# backups for that server

SERVER=$1
CONFIG_FILE_DISABLED=/etc/barman.d/${SERVER}.conf.hold
CONFIG_FILE_ENABLED=/etc/barman.d/${SERVER}.conf

if [ -z "$1" ]; then
  echo "Please specify the backup name which should be started."
  exit 1
fi

set -euo pipefail

if [ ! -f  $CONFIG_FILE_DISABLED ]; then
  echo "ERROR: Config file $CONFIG_FILE_DISABLED does not exist."
  exit 1
fi

mv $CONFIG_FILE_DISABLED $CONFIG_FILE_ENABLED

echo "Config file $CONFIG_FILE_DISABLED renamed to $CONFIG_FILE_ENABLED. Now checking backup."

su -c "barman check $SERVER" barman

