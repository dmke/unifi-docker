#!/usr/bin/env bash

log() {
    echo "$(date +"[%Y-%m-%d %T,%3N]") <docker-entrypoint> $*"
}

exit_handler() {
    log "Exit signal received, shutting down"
    java -jar ${BASEDIR}/lib/ace.jar stop

    for i in $(seq 1 10) ; do
        pgrep -f "${BASEDIR}/lib/ace.jar" || break

        # graceful shutdown
        [ $i -gt 1 ] && [ -d "${BASEDIR}/run" ] && touch "${BASEDIR}/run/server.stop" || true

	# savage shutdown
        [ $i -gt 7 ] && pkill -f ${BASEDIR}/lib/ace.jar || true

	sleep 1
    done

    # shutdown mongod
    if [ -f ${MONGOLOCK} ]; then
        mongo localhost:${MONGOPORT} --eval "db.getSiblingDB('admin').shutdownServer()" >/dev/null 2>&1
    fi

    exit $?
}

trap 'kill ${!}; exit_handler' SIGHUP SIGINT SIGQUIT SIGTERM

if [ -n "${JAVA_HOME}" ]; then
    JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/jre/bin/java::")
    if [ ! -d "${JAVA_HOME}" ]; then
        # For some reason readlink failed so lets just make some assumptions instead
        # We're assuming openjdk 8 since thats what we install in Dockerfile
        arch=$(dpkg --print-architecture 2>/dev/null)
        JAVA_HOME=/usr/lib/jvm/java-8-openjdk-${arch}
    fi
fi


# vars similar to those found in unifi.init
MONGOPORT=27117

CODEPATH="${BASEDIR}"
DATALINK="${BASEDIR}/data"
LOGLINK="${BASEDIR}/logs"
RUNLINK="${BASEDIR}/run"

DIRS="${RUNDIR} ${LOGDIR} ${DATADIR}"

JVM_EXTRA_OPTS="-Dunifi.datadir=${DATADIR} -Dunifi.logdir=${LOGDIR} -Dunifi.rundir=${RUNDIR} -Djava.awt.headless=true -Dfile.encoding=UTF-8"

MONGOLOCK="${DATAPATH}/db/mongod.lock"
PIDFILE=/var/run/unifi/unifi.pid

if [ "${JVM_TRY_CRGOUPS}" = "true" ]; then
	JVM_EXTRA_OPTS="${JVM_EXTRA_OPTS} -XX:+UnlockExperimentalVMOptions -XX:+UseCGroupMemoryLimitForHeap"
else
	if [ -n "${JVM_MAX_HEAP_SIZE}" ]; then
		JVM_EXTRA_OPTS="${JVM_EXTRA_OPTS} -Xmx${JVM_MAX_HEAP_SIZE}"
	else
		JVM_EXTRA_OPTS="${JVM_EXTRA_OPTS} -Xmx1024M"
	fi

	if [ -n "${JVM_INIT_HEAP_SIZE}" ]; then
		JVM_EXTRA_OPTS="${JVM_EXTRA_OPTS} -Xms${JVM_INIT_HEAP_SIZE}"
	fi

	if [ -n "${JVM_MAX_THREAD_STACK_SIZE}" ]; then
		JVM_EXTRA_OPTS="${JVM_EXTRA_OPTS} -Xss${JVM_MAX_THREAD_STACK_SIZE}"
	fi
fi

JVM_OPTS="${JVM_OPTS} ${JVM_EXTRA_OPTS}"

# Cleaning /var/run/unifi/*, Docker takes care of exlusivity in the container anyway.
# See https://github.com/jacobalberty/unifi-docker/issues/26
rm -f ${PIDFILE}

run-parts /usr/local/unifi/init.d
run-parts /usr/unifi/init.d

if [ -d "/unifi/init.d" ]; then
	run-parts "/unifi/init.d"
fi

# Used to generate simple key/value pairs, for example system.properties
confSet() {
	local file="$1"
	local key="$2"
	local value="$3"
	if [ -e "$file" ] && grep -q "^${key} *=" "$file"; then
		local ekey=$(echo "$key" | sed -e 's/[]\/$*.^|[]/\\&/g')
		local evalue=$(echo "$value" | sed -e 's/[\/&]/\\&/g')
		sed -i "s/^\(${ekey}\s*=\s*\).*$/\1${evalue}/" "$file"
	else
		echo "${key}=${value}" >> "$file"
	fi
}

# implement external MongoDB (https://github.com/jacobalberty/unifi-docker/issues/30)
confFile=/unifi/data/system.properties
if [ -n "$DB_URI" ] && [ -n "$STATDB_URI" ] && [ -n "$DB_NAME" ]; then
	confSet "$confFile" "db.mongo.local"   "false"
	confSet "$confFile" "db.mongo.uri"     "$DB_URI"
	confSet "$confFile" "statdb.mongo.uri" "$STATDB_URI"
	confSet "$confFile" "unifi.db.name"    "$DB_NAME"
fi

UNIFI_CMD="java ${JVM_OPTS} -jar ${BASEDIR}/lib/ace.jar start"

# controller writes to relative path logs/server.log
cd ${BASEDIR}

current_uid=$(id -u)

if [ "$@" != "unifi" ]; then
	log "Executing: ${@}"
	exec ${@}
fi

# keep attached to shell so we can wait on it
log 'Starting unifi controller service.'
for dir in "${DATADIR}" "${LOGDIR}"; do
	if [ ! -d "${dir}" ]; then
		if [ "${UNSAFE_IO}" == "true" ]; then
			rm -rf "${dir}"
		fi
		mkdir -p "${dir}"
	fi
done

if [ "$RUNAS_UID0" = "true" ] || [ "$current_uid" != "0" ]; then
	if [ "$current_uid" -eq 0 ]; then
		log 'WARNING: Running UniFi in insecure (root) mode'
	fi
	${UNIFI_CMD} &

elif [ "$RUNAS_UID0" = "false" ]; then
	if [ "$BIND_PRIV" = "true" ]; then
		if setcap 'cap_net_bind_service=+ep' "${JAVA_HOME}/jre/bin/java"; then
			sleep 1
		else
			log "ERROR: setcap failed, can not continue"
			log "ERROR: You may either launch with -e BIND_PRIV=false and only use ports >1024"
			log "ERROR: or run this container as root with -e RUNAS_UID0=true"
			exit 1
		fi
	fi

	# adjust unifi user if necessary
	if [ "$(id unifi -u)" != "$UNIFI_UID" ]; then
		log "INFO: Changing 'unifi' UID to '${UNIFI_UID}'"
		usermod -o -u ${UNIFI_UID} unifi
	fi
	if [ "$(id unifi -g)" != "$UNIFI_GID" ]; then
		log "INFO: Changing 'unifi' GID to '${UNIFI_GID}'"
		groupmod -o -g ${UNIFI_GID} unifi
	fi

	# Using a loop here so I can check more directories easily later
	for dir in ${DIRS}; do
		if [ "$(stat -c '%u' "${dir}")" != "${UNIFI_UID}" ]; then
			chown -R "${UNIFI_UID}:${UNIFI_GID}" "${dir}"
		fi
	done
	gosu unifi:unifi ${UNIFI_CMD} &
fi

wait
log "WARN: unifi service process ended without being singaled? Check for errors in ${LOGDIR}." >&2
exit 1
