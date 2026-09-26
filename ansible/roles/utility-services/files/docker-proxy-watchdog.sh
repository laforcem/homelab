#!/bin/sh
# doco-cd relies on docker-socket-proxy to reach the Docker API. A recreate
# of docker-socket-proxy interrupted mid-flight (see #108) leaves it stopped
# with no self-heal path, since doco-cd is blind without it. This runs
# outside doco-cd's own loop so it can restart the proxy independently.
set -eu

if [ "$(docker inspect -f '{{.State.Running}}' docker-proxy 2>/dev/null || echo false)" != "true" ]; then
    docker start docker-proxy
fi
