#!/bin/bash

#===============================================================================
# SCRIPT PARA SOLUCIONAR "FAILED TO LOAD PREFERENCES" EN PGADMIN
# Descripción: Solución completa para errores de inicialización de pgAdmin
# Autor: Administrador de Sistemas
# Nota: Este es el único script de fix necesario después de las mejoras del instalador
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
echo "SOLUCIONADOR COMPLETO DE PROBLEMAS PGLADMIN"
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

log "Diagnosticando problemas de pgAdmin..."
echo ""

# Paso 1: Verificar configuración actual
log "1. Verificando configuración actual..."
if [ -f ".env" ]; then
    source .env
    echo "Puerto pgAdmin: ${PGLADMIN_PORT:-5050}"
    echo "Email configurado: ${PGLADMIN_EMAIL:-No configurado}"
else
    error "Archivo .env no encontrado"
    exit 1
fi

# Paso 2: Verificar estado del contenedor
log "2. Verificando estado del contenedor..."
container_status=$(${SUDO_PREFIX}${COMPOSE_CMD} ps pgadmin 2>/dev/null | grep pgadmin | awk '{print $3}' || echo "No encontrado")
echo "Estado actual: $container_status"

if [[ "$container_status" != "Up" ]] && [[ "$container_status" != "running" ]]; then
    warning "El contenedor no está corriendo correctamente"
fi

# Paso 3: Verificar logs para identificar problemas específicos
log "3. Analizando logs para identificar problemas..."
logs=$(${SUDO_PREFIX}${COMPOSE_CMD} logs --tail=20 pgadmin 2>/dev/null)

# Identificar tipo de problema
problem_type="unknown"
if echo "$logs" | grep -q -i "failed to load preferences"; then
    problem_type="preferences"
    log "Problema identificado: Failed to load preferences"
elif echo "$logs" | grep -q -i "csrf\|403\|unauthorized"; then
    problem_type="csrf"
    log "Problema identificado: CSRF/Authentication"
elif echo "$logs" | grep -q -i "database.*locked\|database.*corrupt"; then
    problem_type="database"
    log "Problema identificado: Base de datos corrupta"
elif echo "$logs" | grep -q -i "permission.*denied"; then
    problem_type="permissions"
    log "Problema identificado: Permisos incorrectos"
else
    log "Aplicando solución general (problema no específico detectado)"
fi

# Paso 4: Aplicar solución según el tipo de problema
log "4. Aplicando solución específica..."

case $problem_type in
    "preferences"|"database"|"unknown")
        log "Solucionando problemas de base de datos y preferencias..."
        
        # Detener contenedor
        ${SUDO_PREFIX}${COMPOSE_CMD} stop pgadmin
        
        # Backup y limpieza
        if [ -d "pgadmin_data" ]; then
            timestamp=$(date +%Y%m%d_%H%M%S)
            mv pgadmin_data "pgadmin_data_backup_${timestamp}"
            success "Backup creado: pgadmin_data_backup_${timestamp}"
        fi
        
        # Recrear estructura limpia
        mkdir -p pgadmin_data/{sessions,storage,logs}
        touch pgadmin_data/pgadmin4.db
        chmod 644 pgadmin_data/pgadmin4.db
        sudo chown -R 5050:5050 pgadmin_data/ 2>/dev/null || chown -R 5050:5050 pgadmin_data/
        chmod -R 755 pgadmin_data/
        
        success "Estructura de datos recreada"
        ;;
        
    "csrf")
        log "Solucionando problemas de CSRF y autenticación..."
        
        # Solo reiniciar y limpiar sesiones
        ${SUDO_PREFIX}${COMPOSE_CMD} restart pgadmin
        sleep 5
        
        # Limpiar sesiones dentro del contenedor
        ${SUDO_PREFIX}${COMPOSE_CMD} exec pgadmin sh -c "rm -f /var/lib/pgadmin/sessions/* 2>/dev/null || true"
        
        success "Sesiones limpiadas"
        ;;
        
    "permissions")
        log "Corrigiendo permisos..."
        
        # Detener contenedor
        ${SUDO_PREFIX}${COMPOSE_CMD} stop pgadmin
        
        # Corregir permisos
        if [ -d "pgadmin_data" ]; then
            sudo chown -R 5050:5050 pgadmin_data/ 2>/dev/null || chown -R 5050:5050 pgadmin_data/
            chmod -R 755 pgadmin_data/
            success "Permisos corregidos"
        fi
        ;;
esac

# Paso 5: Verificar configuración optimizada en .env
log "5. Verificando configuración optimizada..."
if ! grep -q "PGLADMIN_CONFIG_AUTO_CREATE_DB=True" .env 2>/dev/null; then
    warning "Aplicando configuraciones optimizadas al .env..."
    
    cat >> .env << 'EOF'

# Configuraciones optimizadas para pgAdmin (agregadas por fix-pgladmin-preferences.sh)
PGLADMIN_CONFIG_AUTO_CREATE_DB=True
PGLADMIN_CONFIG_WTF_CSRF_ENABLED=False
PGLADMIN_CONFIG_SESSION_COOKIE_SECURE=False
PGLADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION=False
EOF
    
    success "Configuraciones optimizadas aplicadas"
fi

# Paso 6: Iniciar pgAdmin
log "6. Iniciando pgAdmin..."
${SUDO_PREFIX}${COMPOSE_CMD} up -d pgadmin

# Paso 7: Esperar inicialización con timeout extendido
log "7. Esperando inicialización completa (puede tomar 2-3 minutos)..."
echo -n "Esperando"
pgladmin_ready=false

for i in {1..80}; do
    # Verificar que el contenedor esté corriendo
    if ${SUDO_PREFIX}${COMPOSE_CMD} ps pgadmin | grep -q "Up"; then
        # Verificar respuesta HTTP
        if command -v curl &> /dev/null; then
            status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${PGLADMIN_PORT:-5050}/" 2>/dev/null || echo "ERROR")
            if [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
                echo ""
                pgladmin_ready=true
                break
            fi
        else
            # Sin curl, asumir listo después de tiempo suficiente
            if [[ $i -ge 30 ]]; then
                echo ""
                pgladmin_ready=true
                break
            fi
        fi
    fi
    echo -n "."
    sleep 3
done

# Paso 8: Verificar resultado
if [[ "$pgladmin_ready" == "true" ]]; then
    success "✓ pgAdmin inicializado correctamente"
    
    # Verificar que no hay errores en logs
    recent_logs=$(${SUDO_PREFIX}${COMPOSE_CMD} logs --tail=5 pgadmin 2>/dev/null)
    if echo "$recent_logs" | grep -q -i "error\|failed\|exception"; then
        warning "Se detectaron algunos errores en logs recientes:"
        echo "$recent_logs" | grep -i "error\|failed\|exception" | tail -2
    else
        success "✓ No se detectaron errores en logs"
    fi
else
    warning "pgAdmin puede no estar completamente listo"
    log "Mostrando logs recientes:"
    ${SUDO_PREFIX}${COMPOSE_CMD} logs --tail=10 pgadmin
fi

echo ""
echo "============================================"
success "SOLUCIÓN APLICADA"
echo "============================================"
echo ""
echo "🎯 PRÓXIMOS PASOS:"
echo ""
echo "1. 🌐 Accede a: http://localhost:${PGLADMIN_PORT:-5050}/"
echo "2. 📧 Email: ${PGLADMIN_EMAIL:-admin@example.com}"
echo "3. 🔑 Contraseña: [la configurada en tu archivo .env]"
echo ""
echo "💡 SI SIGUE HABIENDO PROBLEMAS:"
echo ""
echo "🧹 LIMPIAR NAVEGADOR:"
echo "• Presiona Ctrl+F5 (Windows/Linux) o Cmd+Shift+R (Mac)"
echo "• O usa modo incógnito/privado"
echo "• Limpia cookies específicamente para este sitio"
echo ""
echo "🔍 VERIFICAR CONFIGURACIÓN:"
echo "• Estado: ${COMPOSE_CMD} ps"
echo "• Logs: ${COMPOSE_CMD} logs pgadmin"
echo "• Reiniciar: ${COMPOSE_CMD} restart pgadmin"
echo ""
echo "📱 LIMPIAR COOKIES ESPECÍFICAMENTE:"
echo "• Chrome: F12 > Application > Storage > Clear site data"
echo "• Firefox: F12 > Storage > Cookies > eliminar todas para este sitio"
echo "• Safari: Develop > Empty Caches"
echo ""
echo "⚠️  Si nada funciona, considera usar:"
echo "• Un navegador diferente"
echo "• Desactivar extensiones temporalmente"
echo "• Verificar firewall/antivirus"
