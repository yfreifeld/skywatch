variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "key_name" {
  description = "Name of an existing AWS EC2 key pair for SSH access"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Local path to the private key file for Ansible"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "allowed_ssh_cidr" {
  description = "CIDR block allowed to SSH into the instances (use your own IP: x.x.x.x/32)"
  type        = string
  default     = "0.0.0.0/0"
}

variable "instance_type" {
  description = "EC2 instance type (must stay in free tier)"
  type        = string
  default     = "t3.micro"
}

variable "master_volume_size" {
  description = "EBS volume size in GB for the master node"
  type        = number
  default     = 15
}

variable "worker_volume_size" {
  description = "EBS volume size in GB for the worker node"
  type        = number
  default     = 15
}

variable "project_name" {
  description = "Tag prefix applied to all resources"
  type        = string
  default     = "skywatch"
}
