terraform {
  required_version = ">= 1.0"
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.9.0"
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

  # Read all files from homedir recursively and create a map
  # The map key is the relative path within homedir, value is file content
  homedir_files = {
    for f in fileset("${path.module}/files/homedir", "**") :
    f => {
      content     = file("${path.module}/files/homedir/${f}")
      permissions = can(regex("^[^.]*$", basename(f))) && !can(regex("\\.", basename(f))) ? "0755" : "0644"
    }
  }
}

# Create default NAT network
resource "libvirt_network" "default" {
  name      = "default"
  autostart = true

  domain = {
    name = "vm.local"
  }

  forward = {
    mode = "nat"
  }

  ips = [
    {
      address = "192.168.122.1"
      prefix  = 24
      dhcp = {
        ranges = [{
          start = "192.168.122.2"
          end   = "192.168.122.254"
        }]
      }
    }
  ]
}

# Download Debian cloud image
resource "libvirt_volume" "debian_base" {
  name = "debian-13-base.qcow2"
  pool = "default"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = var.debian_image_url
    }
  }
}

# Create VM disk from base image
resource "libvirt_volume" "debian_disk" {
  name     = "${var.vm_name}-disk.qcow2"
  pool     = "default"
  capacity = var.vm_disk_size

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.debian_base.path
    format = {
      type = "qcow2"
    }
  }
}

# Cloud-init configuration
resource "libvirt_cloudinit_disk" "cloud_init" {
  name = "${var.vm_name}-cloud-init.iso"

  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname                = var.vm_hostname
    default_user            = var.default_user
    user_uid                = var.user_uid
    user_gid                = var.user_gid
    ssh_keys                = local.ssh_keys
    gcp_service_account_key = local.gcp_service_account_key
    vertex_project_id       = var.vertex_project_id
    vertex_region           = var.vertex_region
    homedir_files           = local.homedir_files
  })

  meta_data = <<-EOF
    instance-id: ${var.vm_name}
    local-hostname: ${var.vm_hostname}
  EOF
}

# Upload the cloud-init ISO into the pool as a volume
resource "libvirt_volume" "cloud_init_volume" {
  name = "${var.vm_name}-cloud-init-volume.iso"
  pool = "default"

  create = {
    content = {
      url = libvirt_cloudinit_disk.cloud_init.path
    }
  }
}

# Define the VM
resource "libvirt_domain" "debian_vm" {
  name        = var.vm_name
  memory      = var.vm_memory
  memory_unit = "MiB"
  vcpu        = var.vm_vcpu

  type    = "kvm"
  running = true

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  features = {
    acpi = true
  }

  # Enable nested virtualization by passing through host CPU
  cpu = {
    mode = "host-passthrough"
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.debian_disk.pool
            volume = libvirt_volume.debian_disk.name
          }
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
        driver = {
          name = "qemu"
          type = "qcow2"
        }
        boot = {
          order = 1
        }
      },
      {
        device = "cdrom"
        source = {
          volume = {
            pool   = libvirt_volume.cloud_init_volume.pool
            volume = libvirt_volume.cloud_init_volume.name
          }
        }
        target = {
          dev = "sdb"
          bus = "sata"
        }
      }
    ]

    interfaces = [
      {
        type = "network"
        model = {
          type = "virtio"
        }
        source = {
          network = {
            network = libvirt_network.default.name
          }
        }
      }
    ]

    consoles = [
      {
        type        = "pty"
        target_port = 0
        target_type = "serial"
      }
    ]

    graphics = [
      {
        spice = {
          autoport    = "yes"
          listen_type = "address"
        }
      }
    ]
  }
}

# Wait for cloud-init to complete
resource "null_resource" "wait_for_cloud_init" {
  depends_on = [libvirt_domain.debian_vm]

  provisioner "local-exec" {
    command = <<-EOT
      set -e
      echo "Waiting for VM to obtain IP address..."
      for i in $(seq 1 60); do
        IP=$(virsh --connect qemu:///system net-dhcp-leases default | grep ${var.vm_hostname} | grep -oP '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)
        if [ -n "$IP" ]; then
          echo "VM obtained IP: $IP"
          echo "Waiting for SSH to become available and cloud-init to complete..."
          for j in $(seq 1 60); do
            if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 root@$IP "cloud-init status --wait > /dev/null && cloud-init status --long" 2>/dev/null; then
              echo "Cloud-init completed successfully"
              exit 0
            fi
            echo "Attempt $j/60: SSH or cloud-init not ready, waiting..."
            sleep 5
          done
          echo "Timeout waiting for SSH or cloud-init"
          exit 1
        fi
        echo "Attempt $i/60: No IP yet, waiting..."
        sleep 5
      done
      echo "Timeout waiting for IP address"
      exit 1
    EOT
  }

  # Force re-run if VM is recreated
  triggers = {
    vm_id = libvirt_domain.debian_vm.id
  }
}
