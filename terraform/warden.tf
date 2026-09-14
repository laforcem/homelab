resource "proxmox_virtual_environment_vm" "warden" {
    name = "warden"
    node_name = "pve0"
    scsi_hardware = "virtio-scsi-single"
    clone { vm_id = proxmox_virtual_environment_vm.template.id }
    # host, not the qemu64 default — see valet.tf; same single-node
    # cluster, no live migration to budget for.
    cpu {
        cores = 2
        type = "host"
    }
    memory { dedicated = 2048 }
    agent { 
        enabled = true 
        timeout = "10s"
    }
    network_device { bridge = "vmbr0" }
    disk {
        datastore_id = "local-zfs"
        interface = "scsi0"
        size = 32
    }
    initialization {
        datastore_id = "local-zfs"
        ip_config {
            ipv4 {
                address = "192.168.10.12/24"
                gateway = "192.168.10.1"
            }
        }
        user_account {
            username = "malc"
            keys = [trimspace(data.local_file.pubkey.content)]
        }
    }
    operating_system {
        type = "l26"
    }
}

data "local_file" "pubkey" {
    filename = "/home/malc/.ssh/id_ed25519.pub"
}