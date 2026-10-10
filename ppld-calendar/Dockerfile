FROM alpine:3.21

RUN apk add --no-cache bash python3 tzdata

WORKDIR /app
COPY ppld_calendar ./ppld_calendar
COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
