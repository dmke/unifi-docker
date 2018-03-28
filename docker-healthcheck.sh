#!/usr/bin/env bash

SYSPROPS_FILE=${DATADIR}/system.properties
if [ -f "${SYSPROPS_FILE}" ]; then
    SYSPROPS_PORT=$(grep "^unifi.https.port=" ${SYSPROPS_FILE} | cut -d'=' -f2)
fi

curl -kILs --fail https://localhost:${SYSPROPS_PORT:-8443}
