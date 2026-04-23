variable "project_id" {
  description = "The ID of the project in which to create resources."
  type        = string
}

variable "region" {
  description = "The region in which to create resources."
  type        = string
  default     = "us-east1"
}

variable "zone" {
  description = "The zone in which the existing VM is located."
  type        = string
  default     = "us-east1-c"
}

variable "domain_name" {
  description = "The domain name for the SSL certificate and redirect."
  type        = string
}

variable "vm_name" {
  description = "The name of the existing Windows VM."
  type        = string
}

variable "network" {
  description = "The network where the VM and firewall rules reside."
  type        = string
  default     = "default"
}
