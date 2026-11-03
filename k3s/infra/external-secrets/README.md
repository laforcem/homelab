# external-secrets + Bitwarden Secrets Manager

Flux installs and upgrades the chart (`helmrelease.yaml`, values in `values.yaml`)
and applies the ClusterSecretStore (`config/`) once the CRDs exist. Do not run
`helm` by hand. Only the two secrets below are manual, once per cluster, before
Flux reconciles this directory.

## bitwarden-tls-certs (manual step, chart gap)

The bundled `bitwarden-sdk-server` subchart has `image.tls.enabled: true` by
default and expects a pre-existing `bitwarden-tls-certs` secret — the chart
does **not** generate one. Without it the pod hangs in `ContainerCreating`
(`FailedMount`).

Generate a self-signed cert and create the secret (one-time, per cluster):

```
openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout bitwarden-sdk.key -out bitwarden-sdk.crt -days 825 \
  -subj "/CN=bitwarden-sdk-server.external-secrets.svc.cluster.local" \
  -addext "subjectAltName=DNS:bitwarden-sdk-server.external-secrets.svc.cluster.local"

kubectl -n external-secrets create secret tls bitwarden-tls-certs \
  --cert=bitwarden-sdk.crt --key=bitwarden-sdk.key

# the pod also requires a ca.crt key (self-signed => cert is its own CA);
# `create secret tls` doesn't add one, so patch it in:
CA_B64=$(base64 -w0 bitwarden-sdk.crt)
kubectl -n external-secrets patch secret bitwarden-tls-certs --type=json \
  -p "[{\"op\":\"add\",\"path\":\"/data/ca.crt\",\"value\":\"${CA_B64}\"}]"
```

Same cert's base64 goes into `secretstore.yaml`'s `caBundle` field, so
external-secrets trusts the SDK server's self-signed TLS.

## Bootstrap secret

`bitwarden-access-token` (key: `token`) holds the external-secrets machine
account's BWS access token — created once by hand
(`kubectl create secret generic ...`), not by Flux or anything else in this repo. This is the
roadmap's accepted stopgap until Phase 3 secrets-as-code.
