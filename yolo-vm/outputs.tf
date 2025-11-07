output "vm_name" {
  description = "Name of the created VM"
  value       = libvirt_domain.debian_vm.name
}

output "vm_ip" {
  description = "IP address of the VM"
  value = try(
    libvirt_domain.debian_vm.network_interface[0].addresses[0],
    "IP not yet assigned"
  )
}

output "default_user" {
  description = "Username of the default user"
  value       = var.default_user
}

output "ssh_command_default_user" {
  description = "SSH command to connect as default user"
  value = try(
    "ssh ${var.default_user}@${libvirt_domain.debian_vm.network_interface[0].addresses[0]}",
    "Waiting for IP address..."
  )
}

output "ssh_command_root" {
  description = "SSH command to connect as root"
  value = try(
    "ssh root@${libvirt_domain.debian_vm.network_interface[0].addresses[0]}",
    "Waiting for IP address..."
  )
}

output "console_command" {
  description = "Command to access VM console (auto-login as root)"
  value       = "virsh console ${libvirt_domain.debian_vm.name}"
}

output "cloud_init_complete" {
  description = "Indicates whether cloud-init has completed"
  value       = null_resource.wait_for_cloud_init.id != "" ? "Cloud-init completed successfully" : "Waiting for cloud-init..."
  depends_on  = [null_resource.wait_for_cloud_init]
}
