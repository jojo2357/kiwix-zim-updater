FROM alpine:latest

VOLUME /data

RUN apk add \
    ca-certificates \
    coreutils \
    gnutls-utils \
    curl \
    wget \
    grep \
    bash \
    dialog

COPY kiwix-zim-updater.sh /
COPY docker/startup.sh /
RUN chmod +x /startup.sh /kiwix-zim-updater.sh

CMD ["/startup.sh"]
