FROM alpine:3.21

RUN apk add --no-cache bash python3 py3-pip jq

RUN python3 -m venv /opt/oci-venv && \
    /opt/oci-venv/bin/pip install --quiet --upgrade pip && \
    /opt/oci-venv/bin/pip install --quiet oci-cli

ENV PATH="/opt/oci-venv/bin:$PATH"

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY backup.sh /usr/local/bin/backup.sh

RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
