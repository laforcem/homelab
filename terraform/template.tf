resource "proxmox_download_file" "debian_image" {
    content_type = "import"
    datastore_id = "local"
    node_name = "pve0"
    url = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
    file_name = "debian-13-generic-amd64.qcow2"
}

resource "proxmox_virtual_environment_vm" "vm" {
    name = "debian-template"
    node_name = "pve0"
    template = true
    cpu { cores = 2 }
    memory { dedicated = 2048 }
    agent { enabled = true }
    serial_device {}
    network_device { bridge = "vmbr0" }
    disk {
        datastore_id = "local-zfs"
        import_from = proxmox_download_file.debian_image.id
        interface = "scsi0"
    }
    initialization {
        datastore_id = "local-zfs"
        ip_config {
            ipv4 {
                address = "dhcp"
            }
        }
    }
}
