param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    [string]$ProjectName = "twin"
)

# Validar parámetro de entorno
if ($Environment -notmatch '^(dev|test|prod)$') {
    Write-Host "Error: Entorno '$Environment' no válido" -ForegroundColor Red
    Write-Host "Entornos disponibles: dev, test, prod" -ForegroundColor Yellow
    exit 1
}

Write-Host "Preparando para destruir la infraestructura $ProjectName-$Environment..." -ForegroundColor Yellow

# Ir al directorio terraform
Set-Location (Join-Path (Split-Path $PSScriptRoot -Parent) "terraform")

# Comprobar si existe el workspace
$workspaces = terraform workspace list
if (-not ($workspaces | Select-String $Environment)) {
    Write-Host "Error: El workspace '$Environment' no existe" -ForegroundColor Red
    Write-Host "Workspaces disponibles:" -ForegroundColor Yellow
    terraform workspace list
    exit 1
}

# Seleccionar el workspace
terraform workspace select $Environment

Write-Host "Vaciando los buckets S3..." -ForegroundColor Yellow

# Obtener ID de cuenta AWS para los nombres de los buckets
$awsAccountId = aws sts get-caller-identity --query Account --output text

# Definir nombres de buckets con ID de cuenta
$FrontendBucket = "$ProjectName-$Environment-frontend-$awsAccountId"
$MemoryBucket = "$ProjectName-$Environment-memory-$awsAccountId"

# Vaciar el bucket de frontend si existe
try {
    aws s3 ls "s3://$FrontendBucket" 2>$null | Out-Null
    Write-Host "  Vaciando $FrontendBucket..." -ForegroundColor Gray
    aws s3 rm "s3://$FrontendBucket" --recursive
} catch {
    Write-Host "  Bucket frontend no encontrado o ya vacío" -ForegroundColor Gray
}

# Vaciar el bucket de memoria si existe
try {
    aws s3 ls "s3://$MemoryBucket" 2>$null | Out-Null
    Write-Host "  Vaciando $MemoryBucket..." -ForegroundColor Gray
    aws s3 rm "s3://$MemoryBucket" --recursive
} catch {
    Write-Host "  Bucket memory no encontrado o ya vacío" -ForegroundColor Gray
}

Write-Host "Ejecutando terraform destroy..." -ForegroundColor Yellow

# Ejecutar terraform destroy con auto-approve
if ($Environment -eq "prod" -and (Test-Path "prod.tfvars")) {
    terraform destroy -var-file=prod.tfvars -var="project_name=$ProjectName" -var="environment=$Environment" -auto-approve
} else {
    terraform destroy -var="project_name=$ProjectName" -var="environment=$Environment" -auto-approve
}

Write-Host "¡Infraestructura de $Environment destruida!" -ForegroundColor Green
Write-Host ""
Write-Host "  Para eliminar completamente el workspace, ejecuta:" -ForegroundColor Cyan
Write-Host "   terraform workspace select default" -ForegroundColor White
Write-Host "   terraform workspace delete $Environment" -ForegroundColor White