resource "proxmox_virtual_environment_vm" "chimaera" {
    name = "chimaera"
    node_name = "pve0"
    scsi_hardware = "virtio-scsi-single"
    clone { vm_id = proxmox_virtual_environment_vm.template.id }
    # host, not the qemu64 default — see valet.tf; same single-node
    # cluster, no live migration to budget for.
    cpu {
        cores = 4
        type = "host"
    }
    memory { dedicated = 16384 }
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
        size = 64
    }
    # The lab drive (/mnt/lab). Created by hand, not by Terraform, but it must
    # be declared here: an undeclared disk is detached on any in-place update
    # (the 32 -> 64 resize on 2026-10-26 dropped it).
    disk {
        datastore_id = "truelab"
        path_in_datastore = "vm-100-disk-0"
        interface = "scsi1"
        file_format = "raw"
        size = 456
        backup = false
    }
    # Defaults to true, which would delete the lab drive with the VM.
    delete_unreferenced_disks_on_destroy = false
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
