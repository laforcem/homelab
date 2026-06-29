FROM alpine:3.21

RUN apk add --no-cache bash python3 jq

RUN python3 -m venv /opt/oci-venv && \
    /opt/oci-venv/bin/pip install --no-cache-dir --quiet --upgrade pip && \
    /opt/oci-venv/bin/pip install --no-cache-dir --quiet oci-cli==3.9.1

ENV PATH="/opt/oci-venv/bin:$PATH"

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 backup.sh /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
