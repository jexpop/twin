output "api_gateway_url" {
  description = "URL de la API Gateway"
  value       = aws_apigatewayv2_api.main.api_endpoint
}

output "cloudfront_url" {
  description = "URL de la distribución de CloudFront"
  value       = "https://${aws_cloudfront_distribution.main.domain_name}"
}

output "s3_frontend_bucket" {
  description = "Nombre del bucket S3 para el frontend"
  value       = aws_s3_bucket.frontend.id
}

output "s3_memory_bucket" {
  description = "Nombre del bucket S3 para almacenamiento de memoria"
  value       = aws_s3_bucket.memory.id
}

output "lambda_function_name" {
  description = "Nombre de la función Lambda"
  value       = aws_lambda_function.api.function_name
}

output "custom_domain_url" {
  description = "URL raíz del sitio en producción"
  value       = var.use_custom_domain ? "https://${var.root_domain}" : ""
}