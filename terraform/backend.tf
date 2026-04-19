terraform {
  backend "s3" {
    # Estos valores los establecerán los scripts de despliegue
    # Para desarrollo local, pueden pasarse vía -backend-config
  }
}