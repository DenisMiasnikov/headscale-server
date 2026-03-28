FROM headscale/headscale:latest AS headscale-bin

FROM alpine:3.20

RUN apk add --no-cache gettext ca-certificates

COPY --from=headscale-bin /ko-app/headscale /usr/local/bin/headscale
COPY entrypoint.sh /entrypoint.sh
COPY config.template.yaml /etc/headscale/config.template.yaml

RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
