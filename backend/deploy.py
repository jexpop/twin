import os
import shutil
import zipfile
import subprocess

def main():
    print("Creando paquete de despliegue para Lambda...")

    # Limpiar
    if os.path.exists("lambda-package"):
        shutil.rmtree("lambda-package")
    if os.path.exists("lambda-deployment.zip"):
        os.remove("lambda-deployment.zip")

    # Crear directorio de paquete
    os.makedirs("lambda-package")

    # Instalar dependencias usando Docker con la imagen oficial de Lambda Python 3.12
    print("Instalando dependencias para runtime de Lambda...")

    subprocess.run(
        [
            "docker",
            "run",
            "--rm",
            "-v",
            f"{os.getcwd()}:/var/task",
            "--platform",
            "linux/amd64",
            "--entrypoint",
            "",
            "public.ecr.aws/lambda/python:3.13",
            "/bin/sh",
            "-c",
            "pip install --target /var/task/lambda-package -r /var/task/requirements.txt --platform manylinux2014_x86_64 --only-binary=:all: --upgrade",
        ],
        check=True,
    )

    # Copiar archivos de aplicación
    print("Copiando archivos de aplicación...")
    for file in ["server.py", "lambda_handler.py", "context.py", "resources.py"]:
        if os.path.exists(file):
            shutil.copy2(file, "lambda-package/")
    
    # Copiar directorio de datos
    if os.path.exists("data"):
        shutil.copytree("data", "lambda-package/data")

    # Crear zip
    print("Creando archivo zip...")
    with zipfile.ZipFile("lambda-deployment.zip", "w", zipfile.ZIP_DEFLATED) as zipf:
        for root, dirs, files in os.walk("lambda-package"):
            for file in files:
                file_path = os.path.join(root, file)
                arcname = os.path.relpath(file_path, "lambda-package")
                zipf.write(file_path, arcname)

    # Mostrar tamaño del paquete
    size_mb = os.path.getsize("lambda-deployment.zip") / (1024 * 1024)
    print(f"✓ Creado lambda-deployment.zip ({size_mb:.2f} MB)")

if __name__ == "__main__":
    main()