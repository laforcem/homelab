provider "bitwarden-secrets" {
    organization_id = "d9739791-0bcf-4d0c-a794-b11101436d0f"
    api_url = "https://api.bitwarden.com"
    identity_url = "https://identity.bitwarden.com"
}

provider "proxmox" {
    endpoint = "https://192.168.10.2:8006/api2/json"
    api_token = data.bitwarden-secrets_secret.proxmox_token.value
    insecure = true
}
