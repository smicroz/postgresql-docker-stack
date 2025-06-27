#!/bin/bash

#===============================================================================
# SCRIPT DE MIGRACIÓN POSTGRESQL DOCKER
# Descripción: Ayuda a migrar desde instalación existente al nuevo instalador
# Autor: Administrador de Sistemas
#===============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "==============================================================================="
echo "MIGRACIÓN POSTGRESQL DOCKER - ASISTENTE"
echo "==============================================================================="
echo ""

# Detectar comando de Docker Compose
COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose no está disponible"
    exit 1
fi

# Verificar si necesita sudo
SUDO_PREFIX=""
if ! docker info &> /dev/null; then
    if sudo docker info &> /dev/null; then
        SUDO_PREFIX="sudo "
        warning "Usando sudo para comandos Docker"
    else
        error "Docker no está disponible"
        exit 1
    fi
fi

# Verificar estado actual
log "Verificando estado actual del sistema..."

# Comprobar si hay contenedores corriendo
containers_running=$(${SUDO_PREFIX}${COMPOSE_CMD} ps -q 2>/dev/null | wc -l)
echo "Contenedores activos: $containers_running"

# Comprobar datos existentes
data_dirs=""
if [ -d "postgres_data" ]; then
    data_dirs="$data_dirs postgres_data"
    echo "✓ postgres_data encontrado"
fi

if [ -d "pgadmin_data" ]; then
    data_dirs="$data_dirs pgadmin_data"
    echo "✓ pgadmin_data encontrado"
fi

echo ""
echo "OPCIONES DE MIGRACIÓN:"
echo "====================="
echo ""
echo "1) 🔄 MIGRACIÓN ESTÁNDAR (Recomendada)"
echo "   • Detiene servicios"
echo "   • Conserva datos de PostgreSQL"
echo "   • Limpia automáticamente configuración problemática"
echo "   • Aplica mejoras del nuevo instalador"
echo ""
echo "2) 🧹 MIGRACIÓN CON LIMPIEZA"
echo "   • Igual que opción 1"
echo "   • + Hace backup de datos"
echo "   • + Limpia volúmenes Docker relacionados"
echo ""
echo "3) 🗑️ RESET COMPLETO"
echo "   • ⚠️ ELIMINA TODOS LOS DATOS"
echo "   • Solo si no tienes datos importantes"
echo "   • Instalación completamente limpia"
echo ""
echo "4) 🔍 SOLO DIAGNÓSTICO"
echo "   • No hace cambios"
echo "   • Solo muestra información del sistema"
echo ""

read -p "Selecciona una opción [1-4]: " choice

case $choice in
    1)
        log "MIGRACIÓN ESTÁNDAR seleccionada"
        echo ""
        
        if [ $containers_running -gt 0 ]; then
            log "Deteniendo contenedores..."
            ${SUDO_PREFIX}${COMPOSE_CMD} down
        fi
        
        log "Ejecutando instalador mejorado..."
        ./quick-start.sh
        
        success "¡Migración completada! El instalador se encargó de las optimizaciones."
        ;;
        
    2)
        log "MIGRACIÓN CON LIMPIEZA seleccionada"
        echo ""
        
        # Crear backups
        if [ -n "$data_dirs" ]; then
            timestamp=$(date +%Y%m%d_%H%M%S)
            log "Creando backups con timestamp: $timestamp"
            
            for dir in $data_dirs; do
                if [ -d "$dir" ]; then
                    cp -r "$dir" "${dir}_backup_${timestamp}"
                    success "✓ Backup creado: ${dir}_backup_${timestamp}"
                fi
            done
        fi
        
        if [ $containers_running -gt 0 ]; then
            log "Deteniendo y removiendo contenedores..."
            ${SUDO_PREFIX}${COMPOSE_CMD} down
            ${SUDO_PREFIX}${COMPOSE_CMD} rm -f
        fi
        
        # Limpiar volúmenes relacionados
        log "Limpiando volúmenes Docker relacionados con PostgreSQL..."
        postgres_volumes=$(${SUDO_PREFIX}docker volume ls -q | grep -E "(postgres|pgadmin)" || true)
        if [ -n "$postgres_volumes" ]; then
            echo "$postgres_volumes" | xargs ${SUDO_PREFIX}docker volume rm 2>/dev/null || true
            success "✓ Volúmenes limpiados"
        fi
        
        log "Ejecutando instalador mejorado..."
        ./quick-start.sh
        
        success "¡Migración con limpieza completada!"
        ;;
        
    3)
        warning "RESET COMPLETO seleccionado"
        echo ""
        echo "⚠️  ESTA OPCIÓN ELIMINARÁ TODOS LOS DATOS DE POSTGRESQL Y PGADMIN"
        echo ""
        read -p "¿Estás ABSOLUTAMENTE seguro? Escribe 'SI ELIMINAR TODO': " confirm
        
        if [ "$confirm" = "SI ELIMINAR TODO" ]; then
            log "Deteniendo servicios..."
            ${SUDO_PREFIX}${COMPOSE_CMD} down 2>/dev/null || true
            
            log "Eliminando todos los datos..."
            rm -rf postgres_data pgadmin_data pgadmin_data 2>/dev/null || true
            
            log "Limpiando volúmenes Docker..."
            ${SUDO_PREFIX}docker volume prune -f 2>/dev/null || true
            
            log "Ejecutando instalador limpio..."
            ./quick-start.sh
            
            success "¡Reset completo realizado!"
        else
            log "Reset cancelado por seguridad"
        fi
        ;;
        
    4)
        log "DIAGNÓSTICO DEL SISTEMA"
        echo ""
        
        echo "📋 INFORMACIÓN DEL SISTEMA:"
        echo "Docker Compose: $COMPOSE_CMD"
        echo "Sudo requerido: $([ -n "$SUDO_PREFIX" ] && echo "Sí" || echo "No")"
        echo ""
        
        echo "📊 ESTADO DE CONTENEDORES:"
        ${SUDO_PREFIX}${COMPOSE_CMD} ps 2>/dev/null || echo "No hay servicios definidos"
        echo ""
        
        echo "💾 DATOS EXISTENTES:"
        ls -la *_data 2>/dev/null || echo "No se encontraron directorios de datos"
        echo ""
        
        echo "🐳 VOLÚMENES DOCKER:"
        ${SUDO_PREFIX}docker volume ls | grep -E "(postgres|pgadmin)" || echo "No se encontraron volúmenes relacionados"
        echo ""
        
        echo "📁 ARCHIVOS DE CONFIGURACIÓN:"
        ls -la .env docker-compose.yml 2>/dev/null || echo "Archivos de configuración no encontrados"
        
        log "Diagnóstico completado - no se realizaron cambios"
        ;;
        
    *)
        error "Opción inválida"
        exit 1
        ;;
esac

echo ""
echo "============================================"
success "PROCESO COMPLETADO"
echo "============================================"
echo ""
echo "💡 PRÓXIMOS PASOS:"
echo ""
echo "• Accede a pgAdmin: http://localhost:5050"
echo "• Si hay problemas: ./fix-pgladmin-preferences.sh"
echo "• Estado de servicios: ${COMPOSE_CMD} ps"
echo "• Logs: ${COMPOSE_CMD} logs -f"
