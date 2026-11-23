FROM golang:alpine AS builder
RUN apk add --no-cache git make gcc musl-dev linux-headers
RUN git clone https://github.com/amnezia-vpn/amneziawg-go.git && cd amneziawg-go && make && make install
RUN git clone https://github.com/amnezia-vpn/amneziawg-tools.git && cd amneziawg-tools/src && make && make WITH_WGQUICK=yes install

FROM alpine:3.24

COPY --from=builder /usr/bin/amneziawg-go /usr/bin/amneziawg-go
COPY --from=builder /usr/bin/awg /usr/bin/awg
COPY --from=builder /usr/bin/awg-quick /usr/bin/awg-quick

# Install the latest mainline nginx from the official nginx.org repository
RUN apk add --no-cache curl ca-certificates \
    && printf "@nginx https://nginx.org/packages/mainline/alpine/v%s/main\n" \
        "$(grep -oE '^[0-9]+\.[0-9]+' /etc/alpine-release)" >> /etc/apk/repositories \
    && curl -fsSL -o /etc/apk/keys/nginx_signing.rsa.pub https://nginx.org/keys/nginx_signing.rsa.pub \
    && apk add --no-cache nginx@nginx \
    && sed -i 's|/etc/nginx/conf.d/\*.conf|/etc/nginx/http.d/*.conf|' /etc/nginx/nginx.conf \
    && rm -f /etc/nginx/conf.d/default.conf

RUN apk update && apk add \
    python3 \
    py3-pip \
    supervisor \
    curl \
    apache2-utils \
    certbot \
    certbot-nginx \
    iptables \
    iptables-legacy \
    bash \
    iproute2 \
    openresolv \
    && rm -rf /var/cache/apk/*

RUN pip3 install flask flask_socketio flask-wtf requests python-socketio eventlet --break-system-packages

RUN mkdir -p /app/web-ui /var/log/supervisor /var/log/webui /var/log/amnezia /var/log/nginx /etc/amnezia/amneziawg /etc/letsencrypt /var/www/le

COPY web-ui /app/web-ui/

RUN mkdir -p /run/nginx
COPY config/nginx/ /etc/nginx/http.d/
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY config/cli.ini /etc/letsencrypt/cli.ini

COPY scripts/ /app/scripts/
RUN chmod +x /app/scripts/*.sh

# Expose default ports
EXPOSE 80
EXPOSE 51820/udp

ENV NGINX_PORT=80
ENV APP_VERSION=1.9.1

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:$NGINX_PORT/status || exit 1

ENTRYPOINT ["/app/scripts/start.sh"]