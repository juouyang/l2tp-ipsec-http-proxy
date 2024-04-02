FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive

ENV LANG C.UTF-8

RUN apt-get update \
    && apt-get install -q -y kmod ppp net-tools iputils-ping strongswan xl2tpd privoxy \
    && rm -rf /var/lib/apt/lists/*

COPY files/conf/privoxy.conf /etc/privoxy/config
COPY files/conf/ipsec.conf /etc/ipsec.conf
COPY files/conf/ipsec.secrets /etc/ipsec.secrets
COPY files/conf/xl2tpd.conf /etc/xl2tpd/xl2tpd.conf
COPY files/conf/options.l2tpd.client /etc/ppp/options.l2tpd.client

COPY entrypoint.sh /

RUN chmod 600 /etc/ipsec.secrets \
    && chmod 600 /etc/ppp/options.l2tpd.client \
    && mkdir -p /var/run/xl2tpd \
    && touch /var/run/xl2tpd/l2tp-control

# HEALTHCHECK --start-period=30s CMD ifconfig|grep ppp* 2>/dev/null || exit 1

STOPSIGNAL SIGTERM

EXPOSE 8118

ENTRYPOINT ["/bin/bash", "-c", "/entrypoint.sh"]
