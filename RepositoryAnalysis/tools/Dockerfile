FROM perl:5.30.0

RUN groupadd -g 1117 tdr && useradd -u 1117 -g tdr -m tdr && \
    mkdir -p /etc/canadiana /var/log/tdr /var/lock/tdr && ln -s /home/tdr /etc/canadiana/tdr && chown tdr.tdr /var/log/tdr && \
    groupadd -g 1115 cihm && useradd -u 1015 -g cihm -m cihm && \ 
    ln -s /home/tdr /etc/canadiana/wip && \
    apt-get update && \
    apt-get install -y --force-yes --no-install-recommends sudo default-jre && \
    apt-get clean

ENV TINI_VERSION 0.18.0
RUN set -ex; \
    \
    apt-get update; \
    apt-get install -y --force-yes --no-install-recommends wget; \
    rm -rf /var/lib/apt/lists/*; \
    \
    dpkgArch="$(dpkg --print-architecture | awk -F- '{ print $NF }')"; \
    \
# install tini
    wget -O /usr/local/bin/tini "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-$dpkgArch"; \
    wget -O /usr/local/bin/tini.asc "https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-$dpkgArch.asc"; \
    export GNUPGHOME="$(mktemp -d)"; \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys 595E85A6B1B4779EA4DAAEC70B588DFF0527A9B7; \
    gpg --batch --verify /usr/local/bin/tini.asc /usr/local/bin/tini; \
    rm -r "$GNUPGHOME" /usr/local/bin/tini.asc; \
    chmod +x /usr/local/bin/tini; \
    tini --version; \
    \
    apt-get purge -y --auto-remove wget ; apt-get clean


WORKDIR /home/tdr
COPY cpanfile* *.conf *.xml docker-entrypoint.sh /home/tdr/

# Build recent JHOVE.
RUN curl -OL http://software.openpreservation.org/rel/jhove/jhove-1.22.jar && \
    java -jar jhove-1.22.jar jhove-auto-install.xml && mv jhove.conf /opt/jhove/conf


# Our application is perl code
RUN cpanm -n --installdeps . && rm -rf /root/.cpanm || \
    (cat /root/.cpanm/work/*/build.log && exit 1)

COPY CIHM-Swift CIHM-Swift
COPY bin bin
COPY lib lib

ENTRYPOINT ["tini", "--", "/home/tdr/docker-entrypoint.sh"]
USER root
