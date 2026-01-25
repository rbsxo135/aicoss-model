variable "region" {
  type    = string
  default = "ap-northeast-2"
}

variable "project_name" {
  type    = string
  default = "aicoss"
}

# variable "input_bucket_name" {
#   type    = string
#   default = "input_datas"
# }

# Prefixes in S3
variable "clinical_prefix" {
  type    = string
  default = "input/Clinical/"
}

variable "gene_prefix" {
  type    = string
  default = "input/Gene/"
}

variable "image_prefix" {
  type    = string
  default = "input/Image/"
}

# SFTP target
variable "sftp_host" {
  type    = string
  default = "168.131.30.102"
}

variable "sftp_port" {
  type    = number
  default = 31113
}

variable "sftp_username" {
  type    = string
  default = "jovyan2"
}

# Provided known_hosts line (exact)
variable "sftp_known_hosts_entry" {
  type = string
  default = "[168.131.30.102]:31113 ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDXs9uxXXYXCl/bf33U5ORqJ53Y+AlPS7PDaUPQmUn5rL7p+1HlnOa8U0O1i7JPk3IR/NRUyCiSePh0RYDhls7l+i+nzm89GrwYmyCu1+gl1mPmXb5V1iCwHxIdAjqK+7uXbcUbuR+tOj4/Xu8UXVW6txUBFAKyHYm74RmElD4ljkEpzx9jBZDxvAadHYFuE/Mwn9/WsXVJlsX0yq66RWs0JXoG4bBDc14mAd31T3WUfIjNUtA9893uBVruR4jr61nxa0q6Htor9u5neOMBuT2sgtDVK2CetUngeRMPGf+tWT2SD8nDQDaRcpIenhmoq97RBXJwUlrg8i8nT240qCfhxSimSrXr4WfPu+YKG8GaSMELspaVWSG/obrPSQFtW/9bDXy/eVHlT9ckpWif2xap32r3MNV/0wJTuSZ4Dxglm/s4nCVQ5bddwk8cI5RgWhENbX9pvAQmY3kCOnsoE8Q6OmR3N/RrQiEcR/zMD40HToVkvUNbuCgvNnkTedtLr02a8GeI5EC8qWbrqwLW3S/GQ0F5Vim1H84Hz0M5s1Jd+Fb3Xa7XcBM32iNhdltWTVYWeBGgWwSuoZyRLopUAHPvy02pr8Lx3Lny0JQD7w8mj+ZL0fNxgjMIYoSjeayZN3K6AE3XQ+Rag6RwXNr68PNpV5iWVBWDWCnqm13m7BYzqQ=="
}

# Secrets Manager secret that stores the private key + sftp settings json
variable "sftp_secret_name" {
  type    = string
  default = "external-sftp-credentials"
}

# Lambda sizing
variable "lambda_timeout_seconds" {
  type    = number
  default = 120
}

variable "lambda_memory_mb" {
  type    = number
  default = 1024
}

# Image worker
variable "image_visibility_timeout_seconds" {
  type    = number
  default = 14400
}

variable "ec2_instance_type" {
  type    = string
  default = "t3.medium"
}

