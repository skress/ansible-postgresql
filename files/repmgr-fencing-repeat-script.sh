#!/bin/bash
set -euo pipefail

# sleeps for INITIAL_DELAY, then executes SCRIPT three times waiting DELAY in between

SCRIPT=$1
INITIAL_DELAY=$2
DELAY=$3

sleep $INITIAL_DELAY
$SCRIPT
sleep $DELAY
$SCRIPT
sleep $DELAY
$SCRIPT