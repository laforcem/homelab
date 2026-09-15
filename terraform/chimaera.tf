resource "proxmox_virtual_environment_vm" "chimaera" {
    name = "chimaera"
    node_name = "pve0"
    scsi_hardware = "virtio-scsi-single"
    clone { vm_id = proxmox_virtual_environment_vm.template.id }
    # host, not the qemu64 default — see valet.tf; same single-node
    # cluster, no live migration to budget for.
    cpu {
        cores = 2
        type = "host"
    }
    memory { dedicated = 4096 }
    agent {
        enabled = true
        timeout = "10s"
    }
    # DMZ VLAN (40) — successor to vm101, not the trusted VLAN warden/valet sit on.
    network_device {
        bridge = "vmbr0"
        vlan_id = 40
    }
    disk {
        datastore_id = "local-zfs"
        interface = "scsi0"
        size = 32
    }
    initialization {
        datastore_id = "local-zfs"
        ip_config {
            ipv4 {
                address = "192.168.40.10/24"
                gateway = "192.168.40.1"
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
