resource "proxmox_virtual_environment_vm" "valet" {
    name = "valet"
    node_name = "pve0"
    scsi_hardware = "virtio-scsi-single"
    clone { vm_id = proxmox_virtual_environment_vm.template.id }
    # host, not the qemu64 default: single-node cluster, no live migration to
    # budget for — qemu64's baseline-SSE2 feature set made Claude Code's
    # native binary spin in an infinite loop at startup (moltron issue #17).
    cpu {
        cores = 2
        type = "host"
    }
    memory { dedicated = 8192 }
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
                address = "192.168.10.14/24"
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
