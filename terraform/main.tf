terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Data: latest Ubuntu 22.04 LTS AMI
# ---------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ---------------------------------------------------------------------------
# Default VPC + first available subnet
# ---------------------------------------------------------------------------
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# ---------------------------------------------------------------------------
# Security Group
# ---------------------------------------------------------------------------
resource "aws_security_group" "skywatch" {
  name        = "${var.project_name}-sg"
  description = "SkyWatch K3s cluster security group"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # K3s API server (needed for kubectl from your laptop)
  ingress {
    description = "K3s API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  # NodePort range (app access from browser)
  ingress {
    description = "NodePort services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Internal cluster traffic (all ports within the SG)
  ingress {
    description = "Intra-cluster"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # VXLAN (Flannel overlay)
  ingress {
    description = "VXLAN Flannel"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  # kubelet metrics
  ingress {
    description = "kubelet"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${var.project_name}-sg", Project = var.project_name }
}

# ---------------------------------------------------------------------------
# Master Node (Control Plane + ArgoCD + Prometheus)
# ---------------------------------------------------------------------------
resource "aws_instance" "master" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.skywatch.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.master_volume_size
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname skywatch-master
    apt-get update -y
    apt-get install -y curl
  EOF

  tags = { Name = "${var.project_name}-master", Role = "master", Project = var.project_name }
}

# ---------------------------------------------------------------------------
# Worker Node 1 (ArgoCD)
# ---------------------------------------------------------------------------
resource "aws_instance" "worker" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.skywatch.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.worker_volume_size
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname skywatch-worker
    apt-get update -y
    apt-get install -y curl
  EOF

  tags = { Name = "${var.project_name}-worker", Role = "worker", Project = var.project_name }
}

# ---------------------------------------------------------------------------
# Worker Node 2 (App pods + RabbitMQ + Grafana)
# ---------------------------------------------------------------------------
resource "aws_instance" "worker2" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = tolist(data.aws_subnets.default.ids)[0]
  vpc_security_group_ids      = [aws_security_group.skywatch.id]
  associate_public_ip_address = true

  root_block_device {
    volume_type = "gp3"
    volume_size = var.worker_volume_size
  }

  user_data = <<-EOF
    #!/bin/bash
    hostnamectl set-hostname skywatch-worker2
    apt-get update -y
    apt-get install -y curl
  EOF

  tags = { Name = "${var.project_name}-worker2", Role = "worker", Project = var.project_name }
}

# ---------------------------------------------------------------------------
# Generate Ansible inventory from instance IPs
# ---------------------------------------------------------------------------
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tpl", {
    master_ip          = aws_instance.master.public_ip
    worker_ip          = aws_instance.worker.public_ip
    worker2_ip         = aws_instance.worker2.public_ip
    master_private_ip  = aws_instance.master.private_ip
    worker_private_ip  = aws_instance.worker.private_ip
    worker2_private_ip = aws_instance.worker2.private_ip
    key_path           = var.ssh_private_key_path
  })
  filename        = "${path.module}/../ansible/inventory.ini"
  file_permission = "0644"
}
