variable "project_name" {
  description = "Prefix used to name/tag all resources"
  type        = string
  default     = "phoenix-capstone"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "my_ip" {
  description = "Your public IP in CIDR form, e.g. 82.14.20.10/32 — used to restrict SSH"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance size for all nodes"
  type        = string
  default     = "t3.small"
}

variable "worker_count" {
  description = "Number of k3s worker nodes"
  type        = number
  default     = 2
}

variable "public_key_path" {
  description = "Path to the SSH public key to install on all nodes"
  type        = string
  default     = "./phoenix-key.pub"
}
