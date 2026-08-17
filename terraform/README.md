# Terraform

`.env` (gitignored) must contain:
```
BW_ACCESS_TOKEN=<bws machine account access token>
```

## Usage

```
cd terraform
set -a && source .env && set +a
terraform plan
terraform apply
```
