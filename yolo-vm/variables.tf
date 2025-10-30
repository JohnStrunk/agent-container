variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "debian-trixie-vm"
}

variable "vm_memory" {
  description = "Memory allocation for VM in MB"
  type        = number
  default     = 2048
}

variable "vm_vcpu" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 2
}

variable "vm_disk_size" {
  description = "Disk size in bytes (20GB default)"
  type        = number
  default     = 21474836480
}

variable "vm_hostname" {
  description = "Hostname for the VM"
  type        = string
  default     = "debian-trixie"
}

variable "default_user" {
  description = "Default non-root user to create"
  type        = string
  default     = "debian"
}

variable "ssh_keys_dir" {
  description = "Directory containing SSH public keys"
  type        = string
  default     = "./ssh-keys"
}

variable "debian_image_url" {
  description = "URL to Debian cloud image"
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2"
}
