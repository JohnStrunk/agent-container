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
  default     = "user"
}

variable "user_uid" {
  description = "UID for the default user (should match host user)"
  type        = number
  default     = 1000
}

variable "user_gid" {
  description = "GID for the default user (should match host user)"
  type        = number
  default     = 1000
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

variable "gcp_service_account_key_path" {
  description = "Path to GCP service account JSON key file for Vertex AI access (leave empty to skip credential injection)"
  type        = string
  default     = ""
}

variable "vertex_project_id" {
  description = "Google Cloud project ID for Vertex AI (required if using claude-code with Vertex AI)"
  type        = string
  default     = ""
}

variable "vertex_region" {
  description = "Google Cloud region for Vertex AI"
  type        = string
  default     = "us-central1"
}
