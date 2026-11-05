# Flux on starcliff

Flux reconciles `k3s/` from `main` of the public repo. Controllers run in
`flux-system`, managed by the Flux Operator; the `FluxInstance` syncs this
directory every 5 minutes.

Not managed by Flux: traefik (k3s addon), cert-manager (Ansible), the
bootstrap secrets below, and the `FluxInstance` itself.

## Install (new cluster or rebuild)

1. Bootstrap secrets, once per cluster, by hand (see
   `k3s/infra/external-secrets/README.md`): `bitwarden-access-token` and
   `bitwarden-tls-certs`. Install external-secrets first if the cluster is
   empty; Flux adopts it afterwards.
2. Install the Operator:

   ```
   helm install flux-operator oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator \
     --version 0.62.1 -n flux-system --create-namespace --kube-context starcliff
   ```

3. Create the instance: `kubectl apply -f flux-instance.yaml`.
4. Check: `kubectl -n flux-system get fluxinstance flux` is `Ready`, and
   `flux get all` lists `flux-system` as Ready.

## Day to day

Merge to `main`; the cluster follows within 5 minutes. Never `kubectl apply`
or `helm upgrade` anything under `k3s/`: Flux reverts it.

## Adding an app

1. Create `k3s/apps/<app>/` with its manifests and a `kustomization.yaml`
   listing them. Namespaces, PVs and PVCs get the annotation
   `kustomize.toolkit.fluxcd.io/prune: disabled`.
2. Add a Kustomization for it to `apps.yaml` (copy an existing one).
3. Write the domain as `${DOMAIN}` (braces required; bare `$DOMAIN` is not
   substituted). Escape literal shell or regex `${...}` as `$${...}`.
4. Add the hostname to `k3s/infra/coredns-custom/` if it is public.

## Gotchas

- Flux only substitutes `${var}`. A value that looks numeric becomes an
  integer; wrap it in a `${quote}` variable (`quote: '"'` under
  `postBuild.substitute`) when the field is a string.
- Adopting a Deployment that was ever restarted with `kubectl rollout restart`
  drops its `restartedAt` annotation and rolls it once.
- Compare a chart against the cluster with `helm template ... --api-versions`
  for every CRD the cluster has, and `--no-hooks` against `helm get manifest`.

## Dashboard

`flux.lan.<domain>` (warden's Caddy, basic auth) proxies the Flux Operator's
web UI on NodePort `30200`. The UI's identity and permissions are in
`k3s/infra/flux/dashboard/`. Credentials are in Bitwarden
(`flux_ui_password`, `flux_ui_basic_auth_hash`); to rotate, replace both and
recreate the `caddy-lan` stack.
