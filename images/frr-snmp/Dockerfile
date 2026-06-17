FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        frr \
        frr-snmp \
        snmp \
        snmpd \
        iproute2 \
        iputils-ping \
        procps \
        tcpdump \
        less \
    && rm -rf /var/lib/apt/lists/*

COPY images/frr-snmp/snmpd.conf /etc/snmp/snmpd.conf
COPY images/frr-snmp/start.sh /usr/local/bin/start.sh

RUN chmod +x /usr/local/bin/start.sh \
    && mkdir -p /etc/frr /run/frr /var/log/frr /var/agentx \
    && chown -R frr:frr /run/frr /var/log/frr \
    && chown -R Debian-snmp:Debian-snmp /var/agentx || true

EXPOSE 161/udp

CMD ["/usr/local/bin/start.sh"]
