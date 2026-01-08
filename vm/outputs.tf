output "vm_name" {
  description = "Name of the created VM"
  value       = libvirt_domain.debian_vm.name
}

data "external" "vm_ip" {
  program    = ["bash", "-c", "result=$(virsh --connect qemu:///system domifaddr ${var.vm_name} | grep -oP '([0-9]{1,3}\\.){3}[0-9]{1,3}' | head -1) ; if [ -z \"$result\" ]; then result=\"not assigned\"; fi ; echo \"$result\" | jq -R '{ip: .}'"]
  depends_on = [null_resource.wait_for_cloud_init]
}

output "vm_ip" {
  description = "IP address of the VM"
  value       = data.external.vm_ip.result.ip
}

output "default_user" {
  description = "Username of the default user"
  value       = var.default_user
}

output "ssh_command_default_user" {
  description = "SSH command to connect as default user"
  value       = "ssh ${var.default_user}@${data.external.vm_ip.result.ip}"
}

output "ssh_command_root" {
  description = "SSH command to connect as root"
  value       = "ssh root@${data.external.vm_ip.result.ip}"
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
