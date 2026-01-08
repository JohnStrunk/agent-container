variable "vm_name" {
  description = "Name of the virtual machine"
  type        = string
  default     = "agent-vm"
}

variable "vm_memory" {
  description = "Memory allocation for VM in MB"
  type        = number
  default     = 4096
}

variable "vm_vcpu" {
  description = "Number of virtual CPUs"
  type        = number
  default     = 4
}

variable "vm_disk_size" {
  description = "Disk size in bytes (40GB default)"
  type        = number
  default     = 42949672960
}

variable "vm_hostname" {
  description = "Hostname for the VM"
  type        = string
  default     = "agent-vm"
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

variable "network_subnet_third_octet" {
  description = "Third octet of the VM network subnet (192.168.X.0/24). Change this when running nested VMs to avoid conflicts with the outer VM's network."
  type        = number
  default     = 123
  validation {
    condition     = var.network_subnet_third_octet >= 0 && var.network_subnet_third_octet <= 255
    error_message = "Network subnet third octet must be between 0 and 255."
  }
}
