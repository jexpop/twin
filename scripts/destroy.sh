#!/bin/bash
set -e

# Verifica si el parámetro de entorno fue suministrado
if [ $# -eq 0 ]; then
    echo "❌ Error: Se requiere el parámetro de entorno"
    echo "Uso: $0 <entorno>"
    echo "Ejemplo: $0 dev"
    echo "Entornos disponibles: dev, test, prod"
    exit 1
fi

ENVIRONMENT=$1
PROJECT_NAME=${2:-twin}

echo "🗑️ Preparando destrucción de la infraestructura ${PROJECT_NAME}-${ENVIRONMENT}..."

cd "$(dirname "$0")/../terraform"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=${DEFAULT_AWS_REGION:-us-east-1}

echo "🔧 Inicializando Terraform con backend S3..."
terraform init -input=false \
  -backend-config="bucket=twin-terraform-state-${AWS_ACCOUNT_ID}" \
  -backend-config="key=${ENVIRONMENT}/terraform.tfstate" \
  -backend-config="region=${AWS_REGION}" \
  -backend-config="dynamodb_table=twin-terraform-locks" \
  -backend-config="encrypt=true"

if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
    echo "❌ Error: El workspace '$ENVIRONMENT' no existe"
    echo "Workspaces disponibles:"
    terraform workspace list
    exit 1
fi

terraform workspace select "$ENVIRONMENT"

echo "📦 Vaciando buckets S3..."

FRONTEND_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-frontend-${AWS_ACCOUNT_ID}"
MEMORY_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-memory-${AWS_ACCOUNT_ID}"

if aws s3 ls "s3://$FRONTEND_BUCKET" 2>/dev/null; then
    echo "  Vaciando $FRONTEND_BUCKET..."
    aws s3 rm "s3://$FRONTEND_BUCKET" --recursive
else
    echo "  Bucket frontend no encontrado o ya vacío"
fi

if aws s3 ls "s3://$MEMORY_BUCKET" 2>/dev/null; then
    echo "  Vaciando $MEMORY_BUCKET..."
    aws s3 rm "s3://$MEMORY_BUCKET" --recursive
else
    echo "  Bucket memory no encontrado o ya vacío"
fi

echo "🔥 Ejecutando terraform destroy..."

if [ ! -f "../backend/lambda-deployment.zip" ]; then
    echo "Creando paquete lambda de prueba para la destrucción..."
    echo "dummy" | zip ../backend/lambda-deployment.zip -
fi

if [ "$ENVIRONMENT" = "prod" ] && [ -f "prod.tfvars" ]; then
    terraform destroy -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
else
    terraform destroy -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
fi

echo "✅ ¡Infraestructura de $ENVIRONMENT destruida!"
echo ""
echo "💡 Para eliminar el workspace completamente, ejecuta:"
echo "   terraform workspace select default"
echo "   terraform workspace delete $ENVIRONMENT"