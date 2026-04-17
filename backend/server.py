from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import os
from dotenv import load_dotenv
from typing import Optional, List, Dict
import json
import uuid
from datetime import datetime
import boto3
from botocore.exceptions import ClientError
from context import prompt

# Cargar variables de entorno
load_dotenv()

app = FastAPI()

# Configuración de CORS
origins = os.getenv("CORS_ORIGINS", "http://localhost:3000").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=False,
    allow_methods=["GET", "POST", "OPTIONS"],
    allow_headers=["*"],
)

# Inicializar cliente de Bedrock
bedrock_client = boto3.client(
    service_name="bedrock-runtime", 
    region_name=os.getenv("DEFAULT_AWS_REGION", "us-east-1")
)

# Selección de modelo Bedrock
# Modelos disponibles:
# - amazon.nova-micro-v1:0  (más rápido, más barato)
# - amazon.nova-lite-v1:0   (balanceado - por defecto)
# - amazon.nova-pro-v1:0    (el más capaz, más caro)
# Recuerda el aviso: puede que necesites añadir el prefijo us. o eu. al id de modelo
BEDROCK_MODEL_ID = os.getenv("BEDROCK_MODEL_ID", "amazon.nova-lite-v1:0")

# Configuración de almacenamiento de memoria
USE_S3 = os.getenv("USE_S3", "false").lower() == "true"
S3_BUCKET = os.getenv("S3_BUCKET", "")
MEMORY_DIR = os.getenv("MEMORY_DIR", "../memory")

# Inicializar cliente S3 si es necesario
if USE_S3:
    s3_client = boto3.client("s3")


# Modelos de petición/respuesta
class ChatRequest(BaseModel):
    message: str
    session_id: Optional[str] = None


class ChatResponse(BaseModel):
    response: str
    session_id: str


class Message(BaseModel):
    role: str
    content: str
    timestamp: str


# Funciones de gestión de memoria
def get_memory_path(session_id: str) -> str:
    return f"{session_id}.json"


def load_conversation(session_id: str) -> List[Dict]:
    """Cargar historial de conversación desde el almacenamiento"""
    if USE_S3:
        try:
            response = s3_client.get_object(Bucket=S3_BUCKET, Key=get_memory_path(session_id))
            return json.loads(response["Body"].read().decode("utf-8"))
        except ClientError as e:
            if e.response["Error"]["Code"] == "NoSuchKey":
                return []
            raise
    else:
        # Almacenamiento en archivo local
        file_path = os.path.join(MEMORY_DIR, get_memory_path(session_id))
        if os.path.exists(file_path):
            with open(file_path, "r") as f:
                return json.load(f)
        return []


def save_conversation(session_id: str, messages: List[Dict]):
    """Guardar historial de conversación en el almacenamiento"""
    if USE_S3:
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=get_memory_path(session_id),
            Body=json.dumps(messages, indent=2),
            ContentType="application/json",
        )
    else:
        # Almacenamiento en archivo local
        os.makedirs(MEMORY_DIR, exist_ok=True)
        file_path = os.path.join(MEMORY_DIR, get_memory_path(session_id))
        with open(file_path, "w") as f:
            json.dump(messages, f, indent=2)


def call_bedrock(conversation: List[Dict], user_message: str) -> str:
    """Llama a AWS Bedrock con el historial de conversación"""
    
    # Construir mensajes en formato Bedrock
    messages = []
    
    # Añadir prompt de sistema como primer mensaje de usuario (convención Bedrock)
    messages.append({
        "role": "user", 
        "content": [{"text": f"System: {prompt()}"}]
    })
    
    # Añadir historial de conversación (limitar a últimos 10 intercambios para controlar el contexto)
    for msg in conversation[-20:]:  # Últimos 10 intercambios ida y vuelta
        messages.append({
            "role": msg["role"],
            "content": [{"text": msg["content"]}]
        })
    
    # Añadir mensaje actual del usuario
    messages.append({
        "role": "user",
        "content": [{"text": user_message}]
    })
    
    try:
        # Llamar a Bedrock usando la API converse
        response = bedrock_client.converse(
            modelId=BEDROCK_MODEL_ID,
            messages=messages,
            inferenceConfig={
                "maxTokens": 2000,
                "temperature": 0.7,
                "topP": 0.9
            }
        )
        
        # Extraer el texto de la respuesta
        return response["output"]["message"]["content"][0]["text"]
        
    except ClientError as e:
        error_code = e.response['Error']['Code']
        if error_code == 'ValidationException':
            # Gestionar errores de formato de mensaje
            print(f"Error de validación de Bedrock: {e}")
            raise HTTPException(status_code=400, detail="Formato de mensaje no válido para Bedrock")
        elif error_code == 'AccessDeniedException':
            print(f"Acceso denegado a Bedrock: {e}")
            raise HTTPException(status_code=403, detail="Acceso denegado al modelo Bedrock")
        else:
            print(f"Error de Bedrock: {e}")
            raise HTTPException(status_code=500, detail=f"Error de Bedrock: {str(e)}")


@app.get("/")
async def root():
    return {
        "message": "API Gemelo Digital IA (Con AWS Bedrock)",
        "memory_enabled": True,
        "storage": "S3" if USE_S3 else "local",
        "ai_model": BEDROCK_MODEL_ID
    }


@app.get("/health")
async def health_check():
    return {
        "status": "healthy", 
        "use_s3": USE_S3,
        "bedrock_model": BEDROCK_MODEL_ID
    }


@app.post("/chat", response_model=ChatResponse)
async def chat(request: ChatRequest):
    try:
        # Generar session_id si no se proporciona
        session_id = request.session_id or str(uuid.uuid4())

        # Cargar historial de conversación
        conversation = load_conversation(session_id)

        # Llamar a Bedrock para obtener la respuesta
        assistant_response = call_bedrock(conversation, request.message)

        # Actualizar historial de conversación
        conversation.append(
            {"role": "user", "content": request.message, "timestamp": datetime.now().isoformat()}
        )
        conversation.append(
            {
                "role": "assistant",
                "content": assistant_response,
                "timestamp": datetime.now().isoformat(),
            }
        )

        # Guardar la conversación
        save_conversation(session_id, conversation)

        return ChatResponse(response=assistant_response, session_id=session_id)

    except HTTPException:
        raise
    except Exception as e:
        print(f"Error en endpoint chat: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/conversation/{session_id}")
async def get_conversation(session_id: str):
    """Recuperar historial de conversación"""
    try:
        conversation = load_conversation(session_id)
        return {"session_id": session_id, "messages": conversation}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)