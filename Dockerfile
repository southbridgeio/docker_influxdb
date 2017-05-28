FROM buildpack-deps:jessie-curl

MAINTAINER admin@southbridge.io

ENV PATH $PATH:/srv/southbridge/bin

RUN set -ex && \
    for key in \
        05CE15085FC09D18E99EFB22684A14CF2582E0C5 ; \
    do \
        gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key" || \
        gpg --keyserver pgp.mit.edu --recv-keys "$key" || \
        gpg --keyserver keyserver.pgp.com --recv-keys "$key" ; \
    done

ENV INFLUXDB_VERSION 1.2.4
RUN wget -q https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUXDB_VERSION}_amd64.deb.asc && \
    wget -q https://dl.influxdata.com/influxdb/releases/influxdb_${INFLUXDB_VERSION}_amd64.deb && \
    gpg --batch --verify influxdb_${INFLUXDB_VERSION}_amd64.deb.asc influxdb_${INFLUXDB_VERSION}_amd64.deb && \
    dpkg -i influxdb_${INFLUXDB_VERSION}_amd64.deb && \
    rm -f influxdb_${INFLUXDB_VERSION}_amd64.deb* && \
    touch /root/.influxdb

COPY influxdb.conf /etc/influxdb/influxdb.conf

EXPOSE 8086
EXPOSE 8088

VOLUME /var/lib/influxdb

VOLUME /var/backups/influxdb

RUN touch /root/.influxdb
COPY southbridge/ /srv/southbridge/.

COPY entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
CMD ["influxd"]
