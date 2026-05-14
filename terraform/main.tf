terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  # If you configured a named profile above, add: profile = "cs312"
}

# Create the vpc
resource "aws_vpc" "cs312" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true

  tags = {
    Name = "cs312-vpc"
  }
}

resource "aws_subnet" "cs312_public" {
  vpc_id                  = aws_vpc.cs312.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "cs312-public-subnet"
  }
}

resource "aws_internet_gateway" "cs312_igw" {
  vpc_id = aws_vpc.cs312.id

  tags = {
    Name = "cs312-igw"
  }
}

resource "aws_route_table" "cs312_public_rt" {
  vpc_id = aws_vpc.cs312.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.cs312_igw.id
  }

  tags = {
    Name = "cs312-public-rt"
  }
}

resource "aws_route_table_association" "cs312_public_rta" {
  subnet_id      = aws_subnet.cs312_public.id
  route_table_id = aws_route_table.cs312_public_rt.id
}

# Security Group for the managed node: SSH from control node only, HTTP from anywhere
resource "aws_security_group" "managed" {
  name        = "cs312-tf-managed-sg"
  description = "Managed node: SSH from control node, HTTP from anywhere"
  vpc_id      = aws_vpc.cs312.id
  
  ingress {
    description = "SSH from my machine"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["76.144.26.104/32"]
  }

  ingress {
    description = "Minecraft"
    from_port   = 25565
    to_port     = 25565
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "cs312-tf-managed-sg"
  }
}

# Managed node: the server that will run the application
resource "aws_instance" "managed" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.managed.id]
  iam_instance_profile   = "LabInstanceProfile"
  subnet_id              = aws_subnet.cs312_public.id

  tags = {
    Name = "cs312-tf-managed"
  }
}

# ECR repository for the CI/CD pipeline in Lab 6
resource "aws_ecr_repository" "minecraft" {
  name                 = "cs312-ops3-minecraft"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = false
  }
}

# S3 Bucket for Minecraft world data
resource "aws_s3_bucket" "world_backups" {
  bucket = "cs312-minecraft-world-backups"

  lifecycle {
    prevent_destroy = true
  }
}

# S3 backups expire after 7 days
resource "aws_s3_bucket_lifecycle_configuration" "world_backups_lifecycle" {
  bucket = aws_s3_bucket.world_backups.id

  rule {
    id = "expire-old-backups"
    status = "Enabled"
    expiration {
      days = 7
    }
    filter {
      prefix = ""
    }
  }
}

# Inventory info for ansible
resource "local_file" "inventory" {
  content = templatefile("${path.module}/../ansible/inventory", {
    ip = aws_instance.managed.public_ip
  })

  filename = "${path.module}/../ansible/inventory"
}

# Ansible run playbook
resource "null_resource" "ansible_provision" {
  depends_on = [local_file.inventory]

  provisioner "local-exec" {
    environment = {
      ANSIBLE_CONFIG = "${path.module}/../ansible/ansible.cfg"
      ANSIBLE_HOST_KEY_CHECKING = "False"
    }

    command = <<EOT
  ansible-playbook \
    -i ${path.module}/../ansible/inventory \
    ${path.module}/../ansible/playbook.yaml \
    -e "ecr_url=${aws_ecr_repository.minecraft.repository_url}" \
    -e "s3_bucket=${aws_s3_bucket.world_backups.bucket}"
  EOT
}
}
