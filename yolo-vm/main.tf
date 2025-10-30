terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Read all SSH public keys from directory
locals {
  ssh_key_files = fileset(var.ssh_keys_dir, "*.pub")
  ssh_keys = [
    for f in local.ssh_key_files :
    trimspace(file("${var.ssh_keys_dir}/${f}"))
  ]
  # Read GCP service account key if path is provided
  gcp_service_account_key = var.gcp_service_account_key_path != "" ? file(var.gcp_service_account_key_path) : ""
}

# Download Debian cloud image
resource "libvirt_volume" "debian_base" {
  name   = "debian-13-base.qcow2"
  pool   = "default"
  source = var.debian_image_url
  format = "qcow2"
}

# Create VM disk from base image
resource "libvirt_volume" "debian_disk" {
  name           = "${var.vm_name}-disk.qcow2"
  pool           = "default"
  base_volume_id = libvirt_volume.debian_base.id
  size           = var.vm_disk_size
  format         = "qcow2"
}

# Cloud-init configuration
resource "libvirt_cloudinit_disk" "cloud_init" {
  name = "${var.vm_name}-cloud-init.iso"
  pool = "default"
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname                = var.vm_hostname
    default_user            = var.default_user
    ssh_keys                = local.ssh_keys
    gcp_service_account_key = local.gcp_service_account_key
    vertex_project_id       = var.vertex_project_id
    vertex_region           = var.vertex_region
  })
}

# Define the VM
resource "libvirt_domain" "debian_vm" {
  name   = var.vm_name
  memory = var.vm_memory
  vcpu   = var.vm_vcpu

  cloudinit = libvirt_cloudinit_disk.cloud_init.id

  disk {
    volume_id = libvirt_volume.debian_disk.id
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_port = "1"
    target_type = "virtio"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
