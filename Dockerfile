# PROXY/SQUID
FROM alpine AS proxy

RUN apk add --no-cache \
        squid nginx bash sudo cgroup-tools iproute2-tc

ARG CACHEBUST=1
RUN apk update && apk upgrade

RUN mkdir -p /etc/squid/proxy.conf.d/ && touch /etc/squid/proxy.conf.d/00-empty
COPY --chmod=0555 --chown=root proxy.sh /
COPY --chmod=0555 --chown=root speed.sh /
COPY squid.conf /etc/squid/
ENTRYPOINT ["/proxy.sh"]
