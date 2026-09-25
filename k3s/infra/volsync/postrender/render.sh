#!/bin/sh
# Helm --post-renderer entrypoint: reads Helm's rendered manifests from
# stdin, patches them via Kustomize, writes the result to stdout.
set -eu
cd "$(dirname "$0")"
cat > all.yaml
kubectl kustomize .
rm -f all.yaml
