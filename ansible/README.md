# Ansible

## Prerequisites

Ansible CLI, installed as an isolated `uv` tool (not apt/pip):
```
uv tool install --with-executables-from ansible-core --with bitwarden-sdk ansible
```

Collections this project depends on (`community.general` for modules like `timezone`, `bitwarden.secrets` for pulling secrets):
```
cd ansible
ansible-galaxy collection install -r requirements.yml
```

## Secrets

Reuses `terraform/.env` (gitignored) rather than a second secrets mechanism. That file must contain both:
```
BW_ACCESS_TOKEN=<bws machine account access token>
BWS_ACCESS_TOKEN=$BW_ACCESS_TOKEN
```
(Terraform's provider and Ansible's `bitwarden.secrets` collection expect differently-named env vars for the same token.)

## Usage

```
cd ansible
set -a && source ../terraform/.env && set +a
ansible-playbook playbooks/main.yaml
```
