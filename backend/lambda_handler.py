from mangum import Mangum
from server import app

# Crea el handler para Lambda
handler = Mangum(app)