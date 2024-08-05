# Traefik

Traefik is a reverse proxy for routing incoming connections to a server. My implementation of it attempts to make the process simple to spin up a new service in a container and make it generally accessible through the proxy.

Setup is largely pulled from [bluepuma77/traefik-best-practice](https://github.com/bluepuma77/traefik-best-practice/blob/main/docker-traefik-dashboard-letsencrypt/).

## Setup

1) First, set up a username/password pair with `htpasswd` that will be used to log into the Traefik dashboard via basic auth:

    ```bash
    read -s password
    htpasswd -nb username $password
    ```

    *Note: If desired, more powerful encryption with `bcrypt` can be used for the password by using the following flags instead:*

    ```bash
    htpasswd -nBC 10 username $password
    ```

2) Create a `.env` file in this directory with the following values set:

    ```env
    EMAIL='me@example.com'
    DOMAIN='example.com'
    HTTP_BASIC_USER='me'
    HTTP_BASIC_PWD='$apr1$*****'
    ```

    The `DOMAIN` specified in this file will be used both for the Traefik dashboard and the `whoami` test application.

3) Spin up the containers. This will start them in detached mode:

    ```bash
    docker compose up -d
    ```

4) Check that both apps are available at `proxy.example.com` and `whoami.example.com`. If there are issues, see [Troubleshooting](#troubleshooting).

## Adding new services

Traefik will automatically detect any new app and secure it with HTTPS as long as the app in question has the following labels in its Compose file:

```yaml
labels:
      - traefik.enable=true
      - traefik.http.routers.whoami.rule=Host(`subdomain.${DOMAIN}`)
      - traefik.http.routers.whoami.entrypoints=websecure
      - traefik.http.routers.whoami.tls.certresolver=myresolver
```

Naturally, ensure that you have a corresponding exact-match or wildcard DNS entry through your domain name registrar.

## Troubleshooting

- *I'm getting a 404 trying to access either Traefik or `whoami`, what's wrong?*

    If your containers are healthy, check both your ingress rules and firewall rules for your OS, especially if you're using Oracle Cloud Infrastructure. Ports 80 and 443 must be accessible.
