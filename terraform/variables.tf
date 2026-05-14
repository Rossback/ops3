variable "ami_id" {
  description = "AMI ID for the EC2 instance (Ubuntu 26.04 in us-east-1)"
  type        = string
  default     = "ami-0fc5d935ebf8bc3bc"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Name of the SSH key pair (must already exist in AWS)"
  type        = string
}

variable "s3_backup_bucket" {
  description = "S3 bucket name for Minecraft world backups"
  type        = string
  default     = "cs312-minecraft-world-backups"
}
