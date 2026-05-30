output "master_public_ip" {
  description = "Public IP of the K3s master node"
  value       = aws_instance.master.public_ip
}

output "worker_public_ip" {
  description = "Public IP of K3s worker1 (ArgoCD)"
  value       = aws_instance.worker.public_ip
}

output "worker2_public_ip" {
  description = "Public IP of K3s worker2 (app pods)"
  value       = aws_instance.worker2.public_ip
}

output "master_instance_id" {
  description = "Instance ID of master"
  value       = aws_instance.master.id
}

output "worker_instance_id" {
  description = "Instance ID of worker1"
  value       = aws_instance.worker.id
}

output "worker2_instance_id" {
  description = "Instance ID of worker2"
  value       = aws_instance.worker2.id
}

output "app_url" {
  description = "URL to access the SkyWatch frontend (NodePort 30080)"
  value       = "http://${aws_instance.worker2.public_ip}:30080"
}

output "argocd_url" {
  description = "URL to access ArgoCD UI (NodePort 30081)"
  value       = "http://${aws_instance.master.public_ip}:30081"
}

output "grafana_url" {
  description = "URL to access Grafana (NodePort 30030)"
  value       = "http://${aws_instance.worker2.public_ip}:30030"
}

output "ssh_master" {
  description = "SSH command for master node"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.master.public_ip}"
}

output "ssh_worker" {
  description = "SSH command for worker1"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.worker.public_ip}"
}

output "ssh_worker2" {
  description = "SSH command for worker2"
  value       = "ssh -i ${var.ssh_private_key_path} ubuntu@${aws_instance.worker2.public_ip}"
}
