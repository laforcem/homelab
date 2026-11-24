FROM alpine:3.24

RUN apk add --no-cache bash python3 jq

# Some oci-cli dependencies (crc32c) ship no prebuilt wheel for Alpine's
# Python, so pip compiles them. The toolchain is removed in the same layer.
RUN apk add --no-cache --virtual .build-deps build-base python3-dev && \
    python3 -m venv /opt/oci-venv && \
    /opt/oci-venv/bin/pip install --no-cache-dir --quiet --upgrade pip && \
    /opt/oci-venv/bin/pip install --no-cache-dir --quiet oci-cli==3.88.0 && \
    apk del .build-deps

ENV PATH="/opt/oci-venv/bin:$PATH"

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=755 backup.sh /usr/local/bin/backup.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
