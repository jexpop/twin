#!/bin/bash
set -e

ENVIRONMENT=${1:-dev}          # dev | test | prod
PROJECT_NAME=${2:-twin}

echo "🚀 Desplegando ${PROJECT_NAME} en ${ENVIRONMENT}..."

# 1. Construir el paquete Lambda
cd "$(dirname "$0")/.."        # raíz del proyecto
echo "📦 Construyendo paquete Lambda..."
(cd backend && uv run deploy.py)

# 2. Workspace y terraform apply
cd terraform
terraform init -input=false

if ! terraform workspace list | grep -q "$ENVIRONMENT"; then
  terraform workspace new "$ENVIRONMENT"
else
  terraform workspace select "$ENVIRONMENT"
fi

# Usar prod.tfvars para el entorno de producción
if [ "$ENVIRONMENT" = "prod" ]; then
  TF_APPLY_CMD=(terraform apply -var-file=prod.tfvars -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve)
else
  TF_APPLY_CMD=(terraform apply -var="project_name=$PROJECT_NAME" -var="environment=$ENVIRONMENT" -auto-approve)
fi

echo "🎯 Aplicando Terraform..."
"${TF_APPLY_CMD[@]}"

API_URL=$(terraform output -raw api_gateway_url)
FRONTEND_BUCKET=$(terraform output -raw s3_frontend_bucket)
CUSTOM_URL=$(terraform output -raw custom_domain_url 2>/dev/null || true)

# 3. Construir y desplegar el frontend
cd ../frontend

# Crear archivo .env.production con el URL de la API
echo "📝 Definiendo API URL para producción..."
echo "NEXT_PUBLIC_API_URL=$API_URL" > .env.production

npm install
npm run build
aws s3 sync ./out "s3://$FRONTEND_BUCKET/" --delete
cd ..

# 4. Mensajes finales
echo -e "\n✅ ¡Despliegue completo!"
echo "🌐 CloudFront URL : $(terraform -chdir=terraform output -raw cloudfront_url)"
if [ -n "$CUSTOM_URL" ]; then
  echo "🔗 Dominio personalizado  : $CUSTOM_URL"
fi
echo "📡 API Gateway    : $API_URL"