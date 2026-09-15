variable "lambda_api_key" {
  type      = string
  sensitive = true
}

variable "ssh_key_name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "gpu_1x_a10"
}

variable "region" {
  type    = string
  default = "us-east-1"
}
