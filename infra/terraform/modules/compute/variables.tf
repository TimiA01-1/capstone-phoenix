variable "project_name" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "security_group_id" {
  type = string
}

variable "public_key_path" {
  type = string
}

variable "worker_count" {
  type = number
}

variable "ami_id" {
  description = "Pinned Ubuntu 22.04 AMI ID (avoid data-source auto-updates replacing instances)"
  type        = string
  default     = "ami-0d30b6a4d95baf37f"
}

