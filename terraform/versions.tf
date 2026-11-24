terraform {
    required_providers {
        proxmox = {
            source = "bpg/proxmox"
            version = "~> 0.123"
        }
        bitwarden-secrets = {
            source = "bitwarden/bitwarden-secrets"
            version = "~> 1.0"
        }
        local = {
            source = "hashicorp/local"
            version = "~> 2.9"
        }
    }
}
