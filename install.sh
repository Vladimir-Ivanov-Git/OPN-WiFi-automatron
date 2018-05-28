#!/bin/bash

SCRIPT_NAME="open-wifi-automatron"
CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
INIT_DIR="/etc/init.d"

cp ${CURRENT_DIR}/${SCRIPT_NAME} ${INIT_DIR}/
chmod +x ${INIT_DIR}/${SCRIPT_NAME}

${INIT_DIR}/${SCRIPT_NAME} init
systemctl enable ${SCRIPT_NAME}.service

echo "Please reboot this device!"