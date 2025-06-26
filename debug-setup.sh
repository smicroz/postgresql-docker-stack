#!/bin/bash

#===============================================================================
# SCRIPT DE VERIFICACIÓN DE SETUP PARA POSTGRESQL
# Descripción: Verifica que el entorno esté configurado correctamente
# Autor: Administrador de Sistemas
# Fecha: $(date +%Y-%m-%d)
#===============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "==============================================================================="
echo "VERIFICACIÓN DE SETUP - POSTGRESQL DOCKER"
echo "==============================================================================="
echo ""

# Variables de estado
ISSUES_FOUND=0
CRITICAL_ISSUES=0

# Verificar directorio actual
log "1. Verificando directorio actual..."
echo "Directorio actual: $(pwd)"
echo "Contenido del directorio:"
ls -la
echo ""

# Verificar archivos esenciales
log "2. Verificando archivos esenciales..."
if [ -f "docker-compose.yml" ]; then
    success "✅ docker-compose.yml encontrado"
else
    error "❌ docker-compose.yml NO encontrado"
    echo "   Este archivo es esencial para ejecutar PostgreSQL con Docker"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if [ -f ".env" ]; then
    success "✅ .env encontrado"
else
    error "❌ .env NO encontrado"
    if [ -f ".env.example" ]; then
        echo "   ➤ Se encontró .env.example, puedes copiarlo:"
        echo "     cp .env.example .env"
        echo "     nano .env  # Editar con tus credenciales"
    else
        echo "   ➤ No se encontró .env.example tampoco"
    fi
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

if [ -f ".env.example" ]; then
    success "✅ .env.example encontrado"
else
    warning "⚠️ .env.example NO encontrado"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi
echo ""

# Verificar permisos de Docker
log "3. Verificando permisos de Docker..."
if docker info &> /dev/null; then
    success "✅ Docker accesible sin sudo"
elif sudo docker info &> /dev/null; then
    warning "⚠️ Docker requiere sudo"
    echo "   ➤ Para usar Docker sin sudo:"
    echo "     sudo usermod -aG docker \$USER"
    echo "     # Luego cerrar sesión y volver a conectar"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
    error "❌ Docker no está disponible o no está funcionando"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi
echo ""

# Verificar Docker Compose
log "4. Verificando Docker Compose..."
if docker compose version &> /dev/null; then
    success "✅ Docker Compose integrado disponible"
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    success "✅ Docker Compose standalone disponible"
    warning "   ➤ Se recomienda usar 'docker compose' integrado"
    COMPOSE_CMD="docker-compose"
else
    error "❌ Docker Compose no está disponible"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi
echo ""

# Verificar si necesita sudo para Docker
SUDO_PREFIX=""
if ! docker info &> /dev/null; then
    if sudo docker info &> /dev/null; then
        SUDO_PREFIX="sudo "
        warning "Usando sudo para comandos Docker"
    fi
fi

# Si tenemos docker-compose.yml, verificar contenido
if [ -f "docker-compose.yml" ]; then
    log "5. Verificando contenido de docker-compose.yml..."
    if grep -q "pgadmin" docker-compose.yml; then
        success "✅ Configuración de pgAdmin encontrada"
    else
        warning "⚠️ No se encontró configuración de pgAdmin"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
    
    if grep -q "postgres" docker-compose.yml; then
        success "✅ Configuración de PostgreSQL encontrada"
    else
        error "❌ No se encontró configuración de PostgreSQL"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
    fi
    echo ""
fi

# Verificar estado de contenedores si Docker funciona
if [ $CRITICAL_ISSUES -eq 0 ]; then
    log "6. Verificando estado de contenedores..."
    if [ -f "docker-compose.yml" ]; then
        CONTAINER_STATUS=$(${SUDO_PREFIX}${COMPOSE_CMD} ps 2>/dev/null)
        if [ $? -eq 0 ]; then
            echo "$CONTAINER_STATUS"
        else
            warning "No se pudieron obtener el estado de contenedores"
        fi
    fi
    echo ""
fi

# Verificar directorios de datos
log "7. Verificando directorios de datos..."
for dir in "postgres_data" "pgladmin_data" "init-scripts"; do
    if [ -d "$dir" ]; then
        success "✅ Directorio $dir existe"
        echo "   Permisos: $(ls -ld "$dir" | awk '{print $1, $3, $4}')"
    else
        warning "⚠️ Directorio $dir no existe (se creará automáticamente)"
    fi
done
echo ""

# Resumen y recomendaciones
log "8. RESUMEN Y RECOMENDACIONES:"
echo "============================================"

if [ $CRITICAL_ISSUES -gt 0 ]; then
    error "❌ PROBLEMAS CRÍTICOS ENCONTRADOS ($CRITICAL_ISSUES)"
    echo ""
    echo "🔧 ACCIONES REQUERIDAS:"
    
    if [ ! -f "docker-compose.yml" ]; then
        echo "1. Navegar al directorio correcto del proyecto PostgreSQL"
        echo "   cd /ruta/correcta/al/proyecto/postgresql/"
        echo ""
        echo "   O si no tienes el proyecto, descárgalo:"
        echo "   git clone <tu-repositorio> postgresql"
        echo "   cd postgresql"
    fi
    
    if [ ! -f ".env" ]; then
        echo "2. Crear archivo .env con tus credenciales:"
        echo "   cp .env.example .env"
        echo "   nano .env"
        echo "   # Cambiar las contraseñas por defecto"
    fi
    
else
    success "✅ CONFIGURACIÓN BÁSICA CORRECTA"
    
    if [ $ISSUES_FOUND -gt 0 ]; then
        warning "⚠️ Problemas menores encontrados ($ISSUES_FOUND)"
    fi
    
    echo ""
    echo "🚀 PRÓXIMOS PASOS:"
    echo "1. Ejecutar diagnóstico completo:"
    echo "   ${SUDO_PREFIX}./debug-pgadmin.sh"
    echo ""
    echo "2. Si hay problemas, ejecutar soluciones:"
    echo "   ${SUDO_PREFIX}./fix-pgadmin.sh"
    echo ""
    echo "3. Iniciar servicios si no están corriendo:"
    echo "   ${SUDO_PREFIX}${COMPOSE_CMD} up -d"
fi

echo ""
echo "============================================"

# Crear script de inicio rápido personalizado
if [ $CRITICAL_ISSUES -eq 0 ]; then
    log "9. Creando script de inicio rápido personalizado..."
    
    cat > quick-fix.sh << EOF
#!/bin/bash
# Script de inicio rápido generado automáticamente

echo "Iniciando PostgreSQL y pgAdmin..."

# Usar sudo si es necesario
${SUDO_PREFIX}${COMPOSE_CMD} down 2>/dev/null
${SUDO_PREFIX}${COMPOSE_CMD} up -d

echo "Esperando que los servicios estén listos..."
sleep 10

echo "Estado de contenedores:"
${SUDO_PREFIX}${COMPOSE_CMD} ps

if [ -f ".env" ]; then
    source .env
    echo ""
    echo "=== INFORMACIÓN DE ACCESO ==="
    echo "PostgreSQL: localhost:\${POSTGRES_PORT:-5432}"
    echo "pgAdmin: http://localhost:\${PGLADMIN_PORT:-5050}"
    echo "Usuario pgAdmin: \${PGADMIN_EMAIL:-admin@example.com}"
fi
EOF

    chmod +x quick-fix.sh
    success "✅ Script quick-fix.sh creado"
    echo "   Ejecuta: ./quick-fix.sh para iniciar rápidamente"
fi

echo ""
log "Verificación completada."

exit $CRITICAL_ISSUES
