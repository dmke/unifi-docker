#!/usr/bin/env bash

set -ex

apt-get update
apt-get install -qy --no-install-recommends \
    openjdk-8-jre-headless \
    procps \
    libcap2-bin

dpkg -i /tmp/mongodb-org-server*.deb
apt -qy install /tmp/unifi.deb
rm -rf /tmp/*.deb /var/lib/apt/lists/*

chown -R unifi:unifi "${BASEDIR}"

rm -rf "${ODATADIR}" "${OLOGDIR}"
mkdir -p "${DATADIR}" "${LOGDIR}"
ln -s "${DATADIR}" "${BASEDIR}/data"
ln -s "${RUNDIR}"  "${BASEDIR}/run"
ln -s "${LOGDIR}"  "${BASEDIR}/logs"
ln -s "${DATADIR}" "${ODATADIR}"
ln -s "${LOGDIR}"  "${OLOGDIR}"

mkdir -p /var/cert "${CERTDIR}"
ln -s "${CERTDIR}" /var/cert/unifi

# self-destruct
rm -rf "$0"
