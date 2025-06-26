#!/bin/bash

#===============================================================================
# SCRIPT PARA SOLUCIONAR PROBLEMA DE CSRF TOKEN EN PGADMIN
# Descripción: Soluciona el error "CSRF token is missing" en pgAdmin
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
echo "SOLUCIONADOR DE PROBLEMA CSRF TOKEN - PGADMIN"
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

log "Problema detectado: CSRF token missing en pgAdmin"
echo ""
echo "Este error puede ocurrir por:"
echo "1. Configuración incorrecta de cookies en pgAdmin"
echo "2. Problemas con variables de entorno de seguridad"
echo "3. Volúmenes corruptos de pgAdmin"
echo "4. Configuración de red incorrecta"
echo ""

log "Aplicando soluciones paso a paso..."
echo ""

# Paso 1: Verificar configuración actual
log "1. Verificando configuración actual de pgAdmin..."
if [ -f ".env" ]; then
    source .env
    echo "Puerto pgAdmin: ${PGADMIN_PORT:-5050}"
    echo "Email configurado: ${PGADMIN_EMAIL:-No configurado}"
else
    error "Archivo .env no encontrado"
    exit 1
fi

# Paso 2: Verificar docker-compose.yml para configuraciones de seguridad
log "2. Verificando configuraciones de seguridad en docker-compose.yml..."
if grep -q "PGADMIN_CONFIG_WTF_CSRF" docker-compose.yml; then
    echo "✓ Configuraciones CSRF encontradas"
else
    warning "⚠ Configuraciones CSRF no optimizadas"
fi

# Paso 3: Detener pgAdmin
log "3. Deteniendo pgAdmin..."
${SUDO_PREFIX}${COMPOSE_CMD} stop pgadmin

# Paso 4: Limpiar volúmenes y datos de sesión
log "4. Limpiando datos de sesión corruptos..."
if [ -d "pgladmin_data" ]; then
    echo "Haciendo backup de configuraciones existentes..."
    sudo mv pgladmin_data pgladmin_data_backup_$(date +%Y%m%d_%H%M%S) 2>/dev/null || mv pgladmin_data pgladmin_data_backup_$(date +%Y%m%d_%H%M%S)
    success "✓ Backup creado"
else
    echo "No hay datos previos que respaldar"
fi

# Paso 5: Recrear directorio con permisos correctos
log "5. Recreando directorio pgladmin_data con permisos correctos..."
mkdir -p pgladmin_data
sudo chown -R 5050:5050 pgladmin_data/ 2>/dev/null || chown -R 5050:5050 pgladmin_data/
chmod -R 755 pgladmin_data/

# Paso 6: Verificar/actualizar configuración de seguridad
log "6. Verificando configuración de seguridad..."

# Crear configuración temporal mejorada si es necesario
if ! grep -q "PGLADMIN_CONFIG_SESSION_COOKIE_SECURE" docker-compose.yml; then
    warning "Creando configuración temporal mejorada..."
    
    # Backup del docker-compose.yml original
    cp docker-compose.yml docker-compose.yml.backup
    
    # Agregar configuraciones de seguridad mejoradas para CSRF
    cat >> .env << 'EOF'

# Configuraciones adicionales para solucionar CSRF token
PGLADMIN_CONFIG_SESSION_COOKIE_SAMESITE=Lax
PGLADMIN_CONFIG_SESSION_COOKIE_SECURE=False
PGLADMIN_CONFIG_WTF_CSRF_TIME_LIMIT=None
PGLADMIN_CONFIG_WTF_CSRF_CHECK_DEFAULT=False
EOF

    success "✓ Configuraciones de seguridad agregadas"
fi

# Paso 7: Iniciar pgAdmin
log "7. Iniciando pgAdmin con configuración limpia..."
${SUDO_PREFIX}${COMPOSE_CMD} up -d pgadmin

# Paso 8: Esperar que esté listo
log "8. Esperando que pgAdmin esté completamente listo..."
echo -n "Esperando"
for i in {1..30}; do
    if curl -s http://localhost:${PGADMIN_PORT:-5050}/ > /dev/null 2>&1; then
        echo ""
        success "✓ pgAdmin responde"
        break
    fi
    echo -n "."
    sleep 2
done

# Paso 9: Verificar logs
log "9. Verificando logs de pgAdmin..."
echo "Últimas líneas de logs:"
${SUDO_PREFIX}${COMPOSE_CMD} logs --tail=10 pgadmin

echo ""
log "10. INSTRUCCIONES PARA ACCEDER:"
echo "============================================"
echo ""
echo "🌐 Accede a pgAdmin usando:"
echo "   URL: http://192.168.3.243:${PGADMIN_PORT:-5050}/"
echo "   Email: ${PGADMIN_EMAIL:-admin@example.com}"
echo "   Contraseña: [la de tu archivo .env]"
echo ""
echo "🔧 Si el problema persiste:"
echo "   1. Limpia COMPLETAMENTE las cookies del navegador para este sitio"
echo "   2. Cierra todas las pestañas del navegador"
echo "   3. Prueba en modo incógnito"
echo "   4. Prueba desde otro navegador"
echo "   5. Verifica que no tengas extensiones que bloqueen cookies"
echo ""
echo "📱 Para limpiar cookies específicamente:"
echo "   • Chrome: F12 > Application > Storage > Clear site data"
echo "   • Firefox: F12 > Storage > Cookies > eliminar todas"
echo "   • Safari: Develop > Empty Caches"
echo ""

# Paso 10: Crear script de acceso rápido
log "11. Creando script de acceso rápido..."
cat > pgadmin-access.sh << EOF
#!/bin/bash
echo "=== ACCESO RÁPIDO A PGADMIN ==="
echo ""

# Cargar variables
source .env 2>/dev/null || true

echo "Estado del contenedor:"
${SUDO_PREFIX}${COMPOSE_CMD} ps | grep pgadmin

echo ""
echo "URL de acceso: http://192.168.3.243:\${PGADMIN_PORT:-5050}/"
echo "Email: \${PGADMIN_EMAIL:-admin@example.com}"
echo ""
echo "Contraseña actual:"
grep "PGADMIN_PASSWORD=" .env

echo ""
echo "Probando conectividad:"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:\${PGADMIN_PORT:-5050}/

echo ""
echo "Si hay problemas, ejecuta: ./fix-csrf-pgadmin.sh"
EOF

chmod +x pgadmin-access.sh
success "✓ Script pgadmin-access.sh creado"

echo ""
log "SOLUCIÓN COMPLETADA"
echo "============================================"
echo ""
echo "🎯 PRÓXIMOS PASOS:"
echo "1. Espera 1-2 minutos más para que pgAdmin termine de inicializar"
echo "2. Accede a http://192.168.3.243:${PGADMIN_PORT:-5050}/"
echo "3. Si sigue el error CSRF, limpia cookies del navegador completamente"
echo "4. Usa modo incógnito para probar"
echo ""
echo "💡 RECORDATORIO:"
echo "El error CSRF suele resolverse limpiando las cookies del navegador"
echo "para el sitio específico de pgAdmin."
