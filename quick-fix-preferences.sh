#!/bin/bash

#===============================================================================
# SCRIPT PARA SOLUCIONAR "FAILED TO LOAD PREFERENCES" EN PGADMIN
# Descripción: Solución rápida para cuando pgAdmin no puede cargar preferences
# Autor: Administrador de Sistemas
#===============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo "==============================================================================="
echo "SOLUCIÓN RÁPIDA: FAILED TO LOAD PREFERENCES - PGADMIN"
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
    else
        error "Docker no está disponible"
        exit 1
    fi
fi

# Cargar variables
source .env 2>/dev/null || true

log "Solucionando 'Failed to load preferences' en pgAdmin..."
echo ""

# 1. Parar pgAdmin
log "1. Deteniendo pgAdmin..."
${SUDO_PREFIX}${COMPOSE_CMD} stop pgladmin

# 2. Eliminar contenedor
log "2. Eliminando contenedor..."
${SUDO_PREFIX}${COMPOSE_CMD} rm -f pgladmin

# 3. Limpiar datos corruptos pero mantener backup
log "3. Limpiando datos corruptos..."
if [ -d "pgladmin_data" ]; then
    timestamp=$(date +%Y%m%d_%H%M%S)
    mv pgladmin_data "pgladmin_data_backup_${timestamp}"
    echo "✓ Backup creado: pgladmin_data_backup_${timestamp}"
fi

# 4. Recrear estructura limpia
log "4. Recreando estructura limpia..."
mkdir -p pgladmin_data/{sessions,storage,logs}
touch pgladmin_data/pgladmin4.db
chmod 644 pgladmin_data/pgladmin4.db
sudo chown -R 5050:5050 pgladmin_data/ 2>/dev/null || chown -R 5050:5050 pgladmin_data/
chmod -R 755 pgladmin_data/

# 5. Añadir configuraciones críticas si no existen
log "5. Verificando configuraciones críticas..."
if ! grep -q "PGLADMIN_CONFIG_AUTO_CREATE_DB" .env; then
    echo "" >> .env
    echo "# Configuraciones para solucionar 'Failed to load preferences'" >> .env
    echo "PGLADMIN_CONFIG_AUTO_CREATE_DB=True" >> .env
    echo "PGLADMIN_CONFIG_WTF_CSRF_ENABLED=False" >> .env
    echo "PGLADMIN_CONFIG_CONSOLE_LOG_LEVEL=10" >> .env
    echo "✓ Configuraciones críticas añadidas"
fi

# 6. Iniciar pgAdmin
log "6. Iniciando pgAdmin con configuración limpia..."
${SUDO_PREFIX}${COMPOSE_CMD} up -d pgladmin

# 7. Esperar inicialización
log "7. Esperando inicialización (esto puede tomar 2-3 minutos)..."
echo -n "Esperando"
for i in {1..60}; do
    if curl -s http://localhost:${PGLADMIN_PORT:-5050}/ > /dev/null 2>&1; then
        echo ""
        success "✓ pgAdmin responde"
        break
    fi
    echo -n "."
    sleep 3
done

# 8. Verificar endpoint de preferences
echo ""
log "8. Verificando carga de preferences..."
status=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:${PGLADMIN_PORT:-5050}/preferences/get_all" 2>/dev/null || echo "ERROR")
if [ "$status" = "401" ] || [ "$status" = "302" ]; then
    success "✓ Preferences endpoint responde (requiere login)"
elif [ "$status" = "500" ]; then
    error "✗ Preferences endpoint con error 500"
else
    echo "Status preferences: $status"
fi

echo ""
echo "============================================"
success "SOLUCIÓN RÁPIDA COMPLETADA"
echo "============================================"
echo ""
echo "🎯 PRUEBA AHORA:"
echo "1. Accede a: http://192.168.3.243:${PGLADMIN_PORT:-5050}/"
echo "2. Si ves la página de login SIN 'failed to load preferences' = ✅ SOLUCIONADO"
echo "3. Si sigue el error, ejecuta: ./fix-pgladmin-preferences.sh"
echo ""
echo "📱 Si el navegador muestra cache viejo:"
echo "• Presiona Ctrl+F5 (o Cmd+Shift+R en Mac) para refrescar completamente"
echo "• O usa modo incógnito"
echo ""

# Mostrar logs si hay errores
if ! curl -s http://localhost:${PGLADMIN_PORT:-5050}/ > /dev/null 2>&1; then
    echo "🔍 Logs recientes (si hay problemas):"
    ${SUDO_PREFIX}${COMPOSE_CMD} logs --tail=10 pgladmin
fi
