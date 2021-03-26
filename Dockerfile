FROM postgres:12.5-alpine
RUN echo http://mirror.yandex.ru/mirrors/alpine/edge/main > /etc/apk/repositories && \
    echo http://mirror.yandex.ru/mirrors/alpine/edge/community >> /etc/apk/repositories
RUN apk add --update jq curl rsync bc gzip libacl libcrypto1.1 lz4-libs musl py3-pyzmq python3 borgbackup openssh-client && \
    apk upgrade musl && \
    rm -rf /var/cache/apk/*
