#!/usr/bin/env bash

set -ex

# add MongoDB repo
echo "deb [ arch=amd64,arm64 ] http://repo.mongodb.org/apt/ubuntu xenial/mongodb-org/3.4 multiverse" | \
	tee /etc/apt/sources.list.d/mongodb-org-3.4.list
apt-key adv --keyserver keyserver.ubuntu.com --recv 0C49F3730359A14518585931BC711F9BA15703C6

# add Unifi repo
echo "deb http://www.ubnt.com/downloads/unifi/debian unifi5 ubiquiti" | \
	tee /etc/apt/sources.list.d/20ubiquiti.list
apt-key adv --keyserver keyserver.ubuntu.com --recv C0A52C50

apt-get update
apt-get install -qy --no-install-recommends \
    apt-transport-https \
    curl \
    openjdk-8-jre-headless \
    procps \
    libcap2-bin \
    mongodb-org

apt -qy install /tmp/unifi.deb
rm -rf /tmp/unifi.deb /var/lib/apt/lists/*

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
