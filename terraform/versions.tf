terraform {
    required_providers {
        proxmox = {
            source = "bpg/proxmox"
            version = "~> 0.111"
        }
        bitwarden-secrets = {
            source = "bitwarden/bitwarden-secrets"
            version = "~> 1.0"
        }
    }
}
