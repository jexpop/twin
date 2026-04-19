variable "project_name" {
  description = "Prefijo de nombre para todos los recursos"
  type        = string
  validation {
    condition     = can(regex("^[a-z0-9-]+$", var.project_name))
    error_message = "El nombre del proyecto solo debe contener letras minúsculas, números y guiones."
  }
}

variable "environment" {
  description = "Nombre del entorno (dev, test, prod)"
  type        = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.environment)
    error_message = "El entorno debe ser uno de: dev, test, prod."
  }
}

variable "bedrock_model_id" {
  description = "ID del modelo Bedrock"
  type        = string
  default     = "amazon.nova-micro-v1:0"
}

variable "lambda_timeout" {
  description = "Timeout de la función Lambda en segundos"
  type        = number
  default     = 60
}

variable "api_throttle_burst_limit" {
  description = "Límite de ráfaga de API Gateway"
  type        = number
  default     = 10
}

variable "api_throttle_rate_limit" {
  description = "Límite de tasa de API Gateway"
  type        = number
  default     = 5
}

variable "use_custom_domain" {
  description = "Vincular un dominio personalizado a CloudFront"
  type        = bool
  default     = false
}

variable "root_domain" {
  description = "Nombre del dominio raíz, ej. midominio.com"
  type        = string
  default     = ""
}