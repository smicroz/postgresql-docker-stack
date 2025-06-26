#!/bin/bash

#===============================================================================
# SCRIPT DE LIMPIEZA RÁPIDA PARA ERRORES 401 EN PGADMIN
# Descripción: Reinicia pgAdmin y limpia sesiones sin perder configuración
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

echo "==============================================================================="
echo "LIMPIEZA RÁPIDA - ERRORES 401 PGADMIN"
echo "==============================================================================="
echo ""

# Detectar comando de Docker Compose
COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}[ERROR]${NC} Docker Compose no está disponible"
    exit 1
fi

# Verificar si necesita sudo
SUDO_PREFIX=""
if ! docker info &> /dev/null; then
    if sudo docker info &> /dev/null; then
        SUDO_PREFIX="sudo "
    else
        echo -e "${RED}[ERROR]${NC} Docker no está disponible"
        exit 1
    fi
fi

# Cargar variables
source .env 2>/dev/null || true

log "Reinicio rápido de pgAdmin para limpiar sesiones..."

# 1. Reiniciar contenedor
log "1. Reiniciando contenedor pgAdmin..."
${SUDO_PREFIX}${COMPOSE_CMD} restart pgladmin

# 2. Esperar que esté listo
log "2. Esperando que pgAdmin esté listo..."
echo -n "Esperando"
for i in {1..20}; do
    if curl -s http://localhost:${PGLADMIN_PORT:-5050}/misc/ping > /dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}✓ pgAdmin responde${NC}"
        break
    fi
    echo -n "."
    sleep 3
done

# 3. Limpiar solo archivos de sesión (mantener configuración)
log "3. Limpiando solo archivos de sesión..."
${SUDO_PREFIX}${COMPOSE_CMD} exec pgladmin sh -c "rm -f /var/lib/pgladmin/sessions/* 2>/dev/null || true"

echo ""
echo "============================================"
echo -e "${GREEN}LIMPIEZA RÁPIDA COMPLETADA${NC}"
echo "============================================"
echo ""
echo "🎯 AHORA DEBES:"
echo "1. LIMPIAR cookies del navegador para este sitio:"
echo "   http://192.168.3.243:${PGLADMIN_PORT:-5050}/"
echo ""
echo "2. Cerrar TODAS las pestañas de pgAdmin"
echo ""
echo "3. Acceder de nuevo y hacer login"
echo ""
echo "💡 Para limpiar cookies rápidamente:"
echo "• Chrome: F12 > Application > Storage > Clear site data"
echo "• Firefox: F12 > Storage > Cookies > eliminar todas para este sitio"
echo "• Safari: Develop > Empty Caches"
echo ""
echo "Si el problema persiste, ejecuta: ./fix-pgadmin-401-errors.sh"
