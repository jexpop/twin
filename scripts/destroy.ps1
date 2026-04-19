param(
    [Parameter(Mandatory=$true)]
    [string]$Environment,
    [string]$ProjectName = "twin"
)

if ($Environment -notmatch '^(dev|test|prod)$') {
    Write-Host "Error: Entorno inválido '$Environment'" -ForegroundColor Red
    Write-Host "Entornos disponibles: dev, test, prod" -ForegroundColor Yellow
    exit 1
}

Write-Host "Preparando destrucción de $ProjectName-$Environment..." -ForegroundColor Yellow

Set-Location (Join-Path (Split-Path $PSScriptRoot -Parent) "terraform")

$awsAccountId = aws sts get-caller-identity --query Account --output text
$awsRegion = if ($env:DEFAULT_AWS_REGION) { $env:DEFAULT_AWS_REGION } else { "us-east-1" }

Write-Host "Inicializando Terraform con backend S3..." -ForegroundColor Yellow
terraform init -input=false `
  -backend-config="bucket=twin-terraform-state-$awsAccountId" `
  -backend-config="key=$Environment/terraform.tfstate" `
  -backend-config="region=$awsRegion" `
  -backend-config="dynamodb_table=twin-terraform-locks" `
  -backend-config="encrypt=true"

$workspaces = terraform workspace list
if (-not ($workspaces | Select-String $Environment)) {
    Write-Host "Error: El workspace '$Environment' no existe" -ForegroundColor Red
    Write-Host "Workspaces disponibles:" -ForegroundColor Yellow
    terraform workspace list
    exit 1
}

terraform workspace select $Environment

Write-Host "Vaciando buckets S3..." -ForegroundColor Yellow

$FrontendBucket = "$ProjectName-$Environment-frontend-$awsAccountId"
$MemoryBucket = "$ProjectName-$Environment-memory-$awsAccountId"

try {
    aws s3 ls "s3://$FrontendBucket" 2>$null | Out-Null
    Write-Host "  Vaciando $FrontendBucket..." -ForegroundColor Gray
    aws s3 rm "s3://$FrontendBucket" --recursive
} catch {
    Write-Host "  Bucket frontend no encontrado o ya vacío" -ForegroundColor Gray
}

try {
    aws s3 ls "s3://$MemoryBucket" 2>$null | Out-Null
    Write-Host "  Vaciando $MemoryBucket..." -ForegroundColor Gray
    aws s3 rm "s3://$MemoryBucket" --recursive
} catch {
    Write-Host "  Bucket memory no encontrado o ya vacío" -ForegroundColor Gray
}

Write-Host "Ejecutando terraform destroy..." -ForegroundColor Yellow

if ($Environment -eq "prod" -and (Test-Path "prod.tfvars")) {
    terraform destroy -var-file=prod.tfvars `
                     -var="project_name=$ProjectName" `
                     -var="environment=$Environment" `
                     -auto-approve
} else {
    terraform destroy -var="project_name=$ProjectName" `
                     -var="environment=$Environment" `
                     -auto-approve
}

Write-Host "¡Infraestructura $Environment destruida!" -ForegroundColor Green
Write-Host ""
Write-Host "  Para eliminar el workspace completamente, ejecuta:" -ForegroundColor Cyan
Write-Host "   terraform workspace select default" -ForegroundColor White
Write-Host "   terraform workspace delete $Environment" -ForegroundColor White