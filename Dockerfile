FROM ubuntu:xenial AS downloads

ENV DEBIAN_FRONTEND noninteractive
ENV GOSU_VERSION    1.10
ENV GOSU_URL        https://github.com/tianon/gosu/releases/download
ENV PKG_URL         https://dl.ubnt.com/unifi/5.7.20/unifi_sysvinit_all.deb

# download and verify gosu
# (https://github.com/tianon/gosu/blob/master/INSTALL.md)
RUN set -ex \
 && apt-get update \
 && apt-get install -yq --no-install-recommends ca-certificates curl \
 && dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')" \
 && curl --fail -Lo /tmp/gosu     "${GOSU_URL}/${GOSU_VERSION}/gosu-$dpkgArch" \
 && curl --fail -Lo /tmp/gosu.asc "${GOSU_URL}/${GOSU_VERSION}/gosu-$dpkgArch.asc" \
 && export GNUPGHOME="$(mktemp -d)" \
 && gpg --keyserver keyserver.ubuntu.com --recv-keys B42F6819007F00F88E364FD4036A9C25BF357DD4 \
 && gpg --batch --verify /tmp/gosu.asc /tmp/gosu \
 && chmod +x /tmp/gosu \
 && /tmp/gosu nobody true \
 && curl --fail -Lo /tmp/unifi.deb "${PKG_URL}"

FROM ubuntu:xenial

LABEL maintainer="Jacob Alberty <jacob.alberty@foundigital.com>"

ENV DEBIAN_FRONTEND noninteractive
ENV BASEDIR         /usr/lib/unifi
ENV DATADIR         /unifi/data
ENV LOGDIR          /unifi/log
ENV CERTDIR         /unifi/cert
ENV RUNDIR          /var/run/unifi
ENV ODATADIR        /var/lib/unifi
ENV OLOGDIR         /var/log/unifi
ENV CERTNAME        cert.pem
ENV CERT_IS_CHAIN   false
ENV BIND_PRIV       true
ENV RUNAS_UID0      true
ENV UNIFI_GID       999
ENV UNIFI_UID       999
ENV JVM_CRGOUPS     false

COPY --from=downloads /tmp/gosu      /usr/local/bin/
COPY --from=downloads /tmp/unifi.deb /tmp
COPY docker-entrypoint.sh  \
     docker-healthcheck.sh \
     docker-build.sh       /usr/local/bin/
COPY import_cert           /usr/unifi/init.d/

RUN chmod +x /usr/local/bin/docker-entrypoint.sh \
 && chmod +x /usr/unifi/init.d/import_cert \
 && chmod +x /usr/local/bin/docker-healthcheck.sh \
 && chmod +x /usr/local/bin/docker-build.sh \
 && /usr/local/bin/docker-build.sh

VOLUME ["/unifi", "${RUNDIR}"]

EXPOSE 6789/tcp 8080/tcp 8443/tcp 8880/tcp 8843/tcp 3478/udp

WORKDIR /unifi

HEALTHCHECK CMD /usr/local/bin/docker-healthcheck.sh || exit 1

# execute controller using JSVC like original debian package does
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

CMD ["unifi"]

# execute the conroller directly without using the service

# See issue #12 on github: probably want to consider how JSVC handled
# creating multiple processes, issuing the -stop instraction, etc. Not
# sure if the above ace.jar class gracefully handles TERM signals.
#ENTRYPOINT ["/usr/bin/java", "-Xmx${JVM_MAX_HEAP_SIZE}", "-jar", "/usr/lib/unifi/lib/ace.jar"]
#CMD ["start"]
