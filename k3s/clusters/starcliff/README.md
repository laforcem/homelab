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
