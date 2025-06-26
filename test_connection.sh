#!/bin/bash

#===============================================================================
# SCRIPT DE TEST DE CONEXIÓN PARA POSTGRESQL
# Descripción: Verifica si la conexión a la base de datos PostgreSQL es exitosa.
#===============================================================================

# Colores para el output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# 1. Verificar si el archivo .env existe
if [ ! -f ".env" ]; then
    error "Archivo .env no encontrado."
    echo "Por favor, asegúrate de que el archivo .env exista y contenga las variables de conexión."
    exit 1
fi

# 2. Verificar si psql está instalado
if ! command -v psql &> /dev/null; then
    error "El comando 'psql' no está disponible en este sistema."
    echo ""
    echo "Para instalar PostgreSQL client:"
    echo "• En Ubuntu/Debian: sudo apt-get install postgresql-client"
    echo "• En CentOS/RHEL: sudo yum install postgresql"
    echo "• En macOS: brew install postgresql"
    echo "• En Arch Linux: sudo pacman -S postgresql"
    echo ""
    echo "Alternativamente, puedes usar Docker para ejecutar psql:"
    echo "docker run --rm -it postgres:15 psql --help"
    exit 1
fi

# 3. Cargar variables de entorno desde .env
# Esto exporta las variables para que estén disponibles para psql
export $(grep -v '^#' .env | grep -v '^$' | xargs)

# 4. Preguntar por el tipo de conexión
echo ""
echo "Seleccione el tipo de conexión a probar:"
# Usamos un menú select para una entrada más robusta
select conn_type in "Local (dentro de este servidor)" "Externa (desde otra máquina)"; do
    case $conn_type in
        "Local (dentro de este servidor)" )
            # Para conexión local, usamos localhost. Si POSTGRES_HOST está en .env, se sobrescribe aquí.
            POSTGRES_HOST="localhost"
            break;;
        "Externa (desde otra máquina)" )
            # Para conexión externa, pedir la IP
            read -p "Introduce la dirección IP o el nombre de host del servidor PostgreSQL: " external_host
            if [ -z "$external_host" ]; then
                error "La dirección IP no puede estar vacía."
                exit 1
            fi
            POSTGRES_HOST=$external_host
            break;;
    esac
done
echo ""

log "Probando conexión con la siguiente configuración:"
echo "----------------------------------------"
echo "Host: ${POSTGRES_HOST}"
echo "Puerto: ${POSTGRES_PORT:-5432}"
echo "Usuario: ${POSTGRES_USER:-postgres}"
echo "Base de datos: ${POSTGRES_DB:-mydatabase}"
echo "----------------------------------------"
echo ""

# 5. Intentar la conexión usando psql
# El comando `psql -c "\q"` intenta conectar y sale inmediatamente.
# El código de salida (0 para éxito, >0 para fallo) nos dice si funcionó.
# Se necesita la variable PGPASSWORD para que psql no pida la contraseña interactivamente.
export PGPASSWORD=$POSTGRES_PASSWORD

log "Intentando conectar a PostgreSQL..."

# Usamos el host definido por el usuario
psql -h "${POSTGRES_HOST}" \
     -p "${POSTGRES_PORT:-5432}" \
     -U "${POSTGRES_USER:-postgres}" \
     -d "${POSTGRES_DB:-mydatabase}" \
     -c "\q" &> /dev/null

# 6. Verificar el resultado de la conexión
if [ $? -eq 0 ]; then
    log "✅ Conexión a PostgreSQL exitosa."
else
    error "❌ Fallo al conectar a PostgreSQL."
    echo ""
    echo "Posibles causas:"
    echo "1. Los contenedores de Docker no están corriendo (si es conexión local)."
    echo "2. Las credenciales en el archivo .env son incorrectas."
    echo "3. Un firewall está bloqueando el puerto ${POSTGRES_PORT:-5432} en el host ${POSTGRES_HOST}."
    echo "4. La base de datos '${POSTGRES_DB:-mydatabase}' no existe."
    echo "5. El servidor PostgreSQL no está aceptando conexiones desde tu IP."
    echo "6. El comando 'psql' no está instalado correctamente en el sistema."
    exit 1
fi
