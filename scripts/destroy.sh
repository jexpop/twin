#!/bin/bash
set -e

# Comprobar si el parámetro de entorno ha sido proporcionado
if [ $# -eq 0 ]; then
    echo "❌ Error: Se requiere parámetro de entorno"
    echo "Uso: $0 <entorno>"
    echo "Ejemplo: $0 dev"
    echo "Entornos disponibles: dev, test, prod"
    exit 1
fi

ENVIRONMENT=$1
PROJECT_NAME=${2:-twin}

echo "🗑️ Preparando para destruir la infraestructura de ${PROJECT_NAME}-${ENVIRONMENT}..."

# Ir al directorio terraform
cd "$(dirname "$0")/../terraform"

# Comprobar si existe el workspace
if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
    echo "❌ Error: El workspace '$ENVIRONMENT' no existe"
    echo "Workspaces disponibles:"
    terraform workspace list
    exit 1
fi

# Seleccionar el workspace
terraform workspace select "$ENVIRONMENT"

echo "📦 Vaciando los buckets S3..."

# Obtener el ID de cuenta AWS para los nombres de los buckets
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Nombres de los buckets con ID de cuenta
FRONTEND_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-frontend-${AWS_ACCOUNT_ID}"
MEMORY_BUCKET="${PROJECT_NAME}-${ENVIRONMENT}-memory-${AWS_ACCOUNT_ID}"

# Vaciar el bucket de frontend si existe
if aws s3 ls "s3://$FRONTEND_BUCKET" 2>/dev/null; then
    echo "  Vaciando $FRONTEND_BUCKET..."
    aws s3 rm "s3://$FRONTEND_BUCKET" --recursive
else
    echo "  Bucket frontend no encontrado o ya vacío"
fi

# Vaciar el bucket de memoria si existe
if aws s3 ls "s3://$MEMORY_BUCKET" 2>/dev/null; then
    echo "  Vaciando $MEMORY_BUCKET..."
    aws s3 rm "s3://$MEMORY_BUCKET" --recursive
else
    echo "  Bucket memory no encontrado o ya vacío"
fi

echo "🔥 Ejecutando terraform destroy..."

# Ejecutar terraform destroy automático
if [ "$ENVIRONMENT" = "prod" ] && [ -f "prod.tfvars" ]; then
    terraform destroy -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
else
    terraform destroy -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve
fi

echo "✅ ¡Infraestructura de ${ENVIRONMENT} destruida!"
echo ""
echo "💡 Para eliminar completamente el workspace, ejecuta:"
echo "   terraform workspace select default"
echo "   terraform workspace delete $ENVIRONMENT"