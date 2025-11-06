terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

locals {
  # Read all SSH public keys from directory
  ssh_key_files = fileset(var.ssh_keys_dir, "*.pub")
  ssh_keys = [
    for f in local.ssh_key_files :
    trimspace(file("${var.ssh_keys_dir}/${f}"))
  ]

  # Read GCP service account key if path is provided
  gcp_service_account_key = var.gcp_service_account_key_path != "" ? file(var.gcp_service_account_key_path) : ""

  # Read .claude.json configuration file
  claude_config = file("${path.module}/files/.claude.json")

  # Read start-claude script
  start_claude_script = file("${path.module}/files/start-claude")
}

# Create default NAT network
resource "libvirt_network" "default" {
  name      = "default"
  mode      = "nat"
  addresses = ["192.168.122.0/24"]
  autostart = true
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
    claude_config           = local.claude_config
    start_claude_script     = local.start_claude_script
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
    network_id     = libvirt_network.default.id
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

# Wait for cloud-init to complete
resource "null_resource" "wait_for_cloud_init" {
  depends_on = [libvirt_domain.debian_vm]

  provisioner "remote-exec" {
    inline = [
      # Wait for cloud-init to finish (quietly)
      "cloud-init status --wait > /dev/null",
      # Print the final status
      "cloud-init status --long"
    ]

    connection {
      type    = "ssh"
      user    = "root"
      host    = libvirt_domain.debian_vm.network_interface[0].addresses[0]
      agent   = true
      timeout = "10m"
    }
  }

  # Force re-run if VM is recreated
  triggers = {
    vm_id = libvirt_domain.debian_vm.id
  }
}
