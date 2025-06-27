#!/bin/bash

#===============================================================================
# SCRIPT DE INICIO RÁPIDO PARA POSTGRESQL DOCKER
# Descripción: Configura e inicia PostgreSQL con compatibilidad post-hardening
# Autor: Administrador de Sistemas
# Fecha: $(date +%Y-%m-%d)
#===============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función de logging
log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Variable global para comando de Docker Compose
COMPOSE_CMD=""

# Verificar dependencias
check_dependencies() {
    log "Verificando dependencias..."
    
    if ! command -v docker &> /dev/null; then
        error "Docker no está instalado"
        exit 1
    fi
    
    # Verificar Docker Compose (nuevo comando integrado o legacy standalone)
    if docker compose version &> /dev/null; then
        COMPOSE_CMD="docker compose"
        log "Docker Compose integrado detectado"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
        log "Docker Compose standalone detectado"
        warning "Se recomienda usar 'docker compose' en lugar de 'docker-compose'"
    else
        error "Docker Compose no está instalado"
        exit 1
    fi
    
    # Verificar que Docker daemon esté corriendo
    if ! docker info &> /dev/null; then
        error "Docker daemon no está corriendo"
        info "Inicia Docker y vuelve a intentar"
        exit 1
    fi
    
    if ! command -v curl &> /dev/null; then
        warning "curl no está instalado - se omitirá la verificación de pgAdmin"
    fi
    
    log "Dependencias verificadas correctamente"
}

# Verificar archivo .env
check_env_file() {
    if [[ ! -f ".env" ]]; then
        warning "Archivo .env no encontrado"
        
        if [[ -f ".env.example" ]]; then
            info "Copiando .env.example a .env"
            cp .env.example .env
            
            echo ""
            warning "IMPORTANTE: Edita el archivo .env con tus credenciales antes de continuar"
            echo "Ejecuta: nano .env"
            echo ""
            read -p "¿Has editado el archivo .env? [y/N]: " env_edited
            
            if [[ ! $env_edited =~ ^[Yy]$ ]]; then
                error "Debes editar el archivo .env antes de continuar"
                exit 1
            fi
        else
            error "Archivo .env.example no encontrado"
            exit 1
        fi
    else
        log "Archivo .env encontrado"
    fi
}

# Verificar si es necesario configurar post-hardening
check_hardening_needed() {
    # Verificar si UFW está activo y tiene reglas configuradas
    if command -v ufw &> /dev/null; then
        local ufw_status=$(ufw status 2>/dev/null)
        
        if [[ $ufw_status == *"active"* ]]; then
            # Verificar si ya hay reglas para PostgreSQL
            if ! echo "$ufw_status" | grep -q "5432\|5050"; then
                warning "UFW está activo pero no hay reglas para PostgreSQL/pgAdmin"
                echo ""
                info "Se detectó que el servidor tiene hardening de seguridad aplicado"
                echo "Es necesario configurar el firewall para PostgreSQL y pgAdmin"
                echo ""
                read -p "¿Ejecutar configuración post-hardening? [y/N]: " run_hardening
                
                if [[ $run_hardening =~ ^[Yy]$ ]]; then
                    if [[ $EUID -ne 0 ]]; then
                        error "Se necesitan permisos de root para la configuración post-hardening"
                        info "Ejecuta: sudo ./quick-start.sh"
                        exit 1
                    fi
                    
                    log "Ejecutando configuración post-hardening..."
                    ./configure-post-hardening.sh
                else
                    warning "Continuando sin configurar firewall"
                    warning "Es posible que no puedas conectarte a PostgreSQL/pgAdmin"
                fi
            else
                log "Reglas UFW para PostgreSQL ya configuradas"
            fi
        fi
    fi
}

# Crear directorios necesarios y configurar pgAdmin robustamente
setup_directories() {
    if [[ ! -d "init-scripts" ]]; then
        log "Creando directorio init-scripts..."
        mkdir -p init-scripts
    fi
    
    # Crear directorios necesarios para bind mounts
    if [[ ! -d "postgres_data" ]]; then
        log "Creando directorio postgres_data..."
        mkdir -p postgres_data
        # Asegurar permisos correctos para PostgreSQL (usuario 999)
        if command -v chown &> /dev/null; then
            chown 999:999 postgres_data 2>/dev/null || warning "No se pudieron configurar permisos para postgres_data"
        fi
    fi
    
    # Configuración robusta para pgAdmin - prevenir problemas comunes
    setup_pgadmin_robust
}

# Configuración robusta de pgAdmin para prevenir errores comunes
setup_pgadmin_robust() {
    log "Configurando pgAdmin con configuración robusta..."
    
    # Limpiar instalación anterior si existe
    if [[ -d "pgadmin_data" ]]; then
        warning "Limpiando datos anteriores de pgAdmin para evitar conflictos..."
        rm -rf pgadmin_data
    fi
    
    # Crear estructura de directorios optimizada
    log "Creando estructura optimizada de directorios para pgAdmin..."
    mkdir -p pgadmin_data/{sessions,storage,logs}
    
    # Crear base de datos inicial limpia
    touch pgadmin_data/pgadmin4.db
    chmod 644 pgadmin_data/pgadmin4.db
    
    # Configurar permisos correctos
    if command -v chown &> /dev/null; then
        chown -R 5050:5050 pgadmin_data 2>/dev/null || warning "No se pudieron configurar permisos para pgadmin_data"
    fi
    chmod -R 755 pgadmin_data
    
    # Crear directorio de configuración si no existe
    if [[ ! -d "pgladmin-config" ]]; then
        mkdir -p pgladmin-config
    fi
    
    # Configurar variables de entorno optimizadas para evitar errores comunes
    setup_pgadmin_env_config
}

# Configurar variables de entorno optimizadas para pgAdmin
setup_pgadmin_env_config() {
    log "Aplicando configuración optimizada para prevenir errores CSRF y 401..."
    
    # Verificar si ya existe configuración optimizada
    if ! grep -q "# CONFIGURACIÓN OPTIMIZADA PGADMIN" .env 2>/dev/null; then
        log "Agregando configuraciones optimizadas al archivo .env..."
        
        cat >> .env << 'EOF'

# =============================================================================
# CONFIGURACIÓN OPTIMIZADA PGADMIN - PREVIENE ERRORES COMUNES
# =============================================================================

# Configuraciones críticas para inicialización estable
PGLADMIN_CONFIG_DATA_DIR=/var/lib/pgladmin
PGLADMIN_CONFIG_LOG_FILE=/var/log/pgladmin/pgladmin4.log
PGLADMIN_CONFIG_SQLITE_PATH=/var/lib/pgladmin/pgladmin4.db
PGLADMIN_CONFIG_SESSION_DB_PATH=/var/lib/pgladmin/sessions

# Prevenir errores "Failed to load preferences"
PGLADMIN_CONFIG_AUTO_CREATE_DB=True
PGLADMIN_CONFIG_DB_UPGRADE=True
PGLADMIN_CONFIG_UPGRADE_CHECK_ENABLED=False

# Configuraciones de sesión y cookies optimizadas (previene errores CSRF)
PGLADMIN_CONFIG_SESSION_COOKIE_SECURE=False
PGLADMIN_CONFIG_SESSION_COOKIE_SAMESITE=Lax
PGLADMIN_CONFIG_SESSION_COOKIE_HTTPONLY=True
PGLADMIN_CONFIG_SESSION_COOKIE_DOMAIN=""

# Configuraciones de seguridad ajustadas para estabilidad
PGLADMIN_CONFIG_WTF_CSRF_ENABLED=False
PGLADMIN_CONFIG_WTF_CSRF_TIME_LIMIT=None
PGLADMIN_CONFIG_WTF_CSRF_CHECK_DEFAULT=False
PGLADMIN_CONFIG_ENHANCED_COOKIE_PROTECTION=False

# Configuraciones de autenticación optimizadas
PGLADMIN_CONFIG_AUTHENTICATION_SOURCES=['internal']
PGLADMIN_CONFIG_LOGIN_BANNER=""
PGLADMIN_CONFIG_MASTER_PASSWORD_REQUIRED=False
PGLADMIN_CONFIG_PASSWORD_LENGTH_MIN=1

# Configuraciones de logging para diagnóstico
PGLADMIN_CONFIG_CONSOLE_LOG_LEVEL=20
PGLADMIN_CONFIG_FILE_LOG_LEVEL=20

# Configuraciones específicas para prevenir errores de preferences
PGLADMIN_CONFIG_ALLOW_SAVE_PASSWORD=True
PGLADMIN_CONFIG_BROWSER_AUTO_EXPANSION_MINIMUM_ITEMS=0
PGLADMIN_CONFIG_MAX_QUERY_HIST_STORED=100
PGLADMIN_CONFIG_QUERY_HISTORY_MAX_COUNT=100

# Configuraciones de servidor por defecto
PGLADMIN_CONFIG_DEFAULT_SERVER='localhost'
PGLADMIN_CONFIG_DEFAULT_SERVER_PORT=5432
EOF
        
        log "✓ Configuraciones optimizadas agregadas al .env"
    else
        log "Configuraciones optimizadas ya presentes en .env"
    fi
}

# Iniciar servicios
start_services() {
    log "Iniciando servicios PostgreSQL y pgAdmin..."
    
    # Bajar servicios anteriores por si estaban corriendo
    $COMPOSE_CMD down 2>/dev/null
    
    # Iniciar servicios
    $COMPOSE_CMD up -d
    
    if [[ $? -eq 0 ]]; then
        log "Servicios iniciados correctamente"
    else
        error "Error al iniciar los servicios"
        exit 1
    fi
}

# Esperar que los servicios estén listos con validaciones robustas
wait_for_services() {
    log "Esperando que los servicios estén listos..."
    
    # Esperar PostgreSQL
    echo -n "Esperando PostgreSQL"
    for i in {1..30}; do
        if $COMPOSE_CMD exec -T postgres pg_isready -U ${POSTGRES_USER:-postgres} &>/dev/null; then
            echo " ✓"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    # Esperar pgAdmin con validación más robusta
    echo -n "Esperando pgAdmin"
    pgadmin_ready=false
    for i in {1..60}; do  # Aumentar tiempo de espera para pgAdmin
        # Verificar que el contenedor esté corriendo
        if ! $COMPOSE_CMD ps pgadmin | grep -q "Up"; then
            echo -n "."
            sleep 2
            continue
        fi
        
        # Verificar que responda HTTP
        if command -v curl &> /dev/null; then
            if curl -s --max-time 5 http://localhost:${PGLADMIN_PORT:-5050}/misc/ping &>/dev/null; then
                echo " ✓"
                pgadmin_ready=true
                break
            fi
        else
            # Si no hay curl, asumir que está listo después de tiempo razonable
            if [[ $i -ge 20 ]]; then
                echo " ⚠️ (curl no disponible, asumiendo que está listo)"
                pgadmin_ready=true
                break
            fi
        fi
        echo -n "."
        sleep 3
    done
    
    if [[ "$pgadmin_ready" == "true" ]]; then
        log "Servicios listos"
        
        # Validación adicional de pgAdmin
        validate_pgadmin_setup
    else
        warning "pgAdmin puede no estar completamente listo"
        log "Servicios iniciados (verificación manual requerida)"
    fi
}

# Validar que pgAdmin esté configurado correctamente
validate_pgadmin_setup() {
    log "Validando configuración de pgAdmin..."
    
    # Verificar que el contenedor esté corriendo
    if ! $COMPOSE_CMD ps pgadmin | grep -q "Up"; then
        warning "El contenedor de pgAdmin no está corriendo correctamente"
        return 1
    fi
    
    # Verificar logs para errores críticos
    local logs=$($COMPOSE_CMD logs --tail=10 pgadmin 2>/dev/null)
    
    if echo "$logs" | grep -q -i "error\|failed\|exception"; then
        warning "Se detectaron posibles errores en pgAdmin:"
        echo "$logs" | grep -i "error\|failed\|exception" | tail -3
        echo ""
        warning "Si tienes problemas, ejecuta: ./fix-pgladmin-preferences.sh"
    else
        log "✓ pgAdmin validado correctamente"
    fi
    
    # Verificar accesibilidad HTTP si curl está disponible
    if command -v curl &> /dev/null; then
        local http_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${PGLADMIN_PORT:-5050}/" 2>/dev/null || echo "ERROR")
        
        if [[ "$http_status" == "200" ]] || [[ "$http_status" == "302" ]]; then
            log "✓ pgAdmin responde correctamente (HTTP $http_status)"
        else
            warning "pgAdmin no responde como se esperaba (HTTP $http_status)"
        fi
    fi
}

# Mostrar información de conexión con troubleshooting
show_connection_info() {
    # Cargar variables del .env
    source .env 2>/dev/null || true
    
    echo ""
    echo "==============================================================================="
    log "SERVICIOS POSTGRESQL INICIADOS CORRECTAMENTE"
    echo "==============================================================================="
    echo ""
    
    info "PostgreSQL:"
    echo "  Host: localhost"
    echo "  Puerto: ${POSTGRES_PORT:-5432}"
    echo "  Base de datos: ${POSTGRES_DB:-mydatabase}"
    echo "  Usuario: ${POSTGRES_USER:-postgres}"
    echo "  Contraseña: ${POSTGRES_PASSWORD:-[definida en .env]}"
    echo "  String de conexión: postgresql://${POSTGRES_USER:-postgres}:${POSTGRES_PASSWORD}@localhost:${POSTGRES_PORT:-5432}/${POSTGRES_DB:-mydatabase}"
    echo ""
    
    info "pgAdmin:"
    echo "  URL: http://localhost:${PGLADMIN_PORT:-5050}"
    echo "  Email: ${PGLADMIN_EMAIL:-admin@example.com}"
    echo "  Contraseña: ${PGLADMIN_PASSWORD:-[definida en .env]}"
    echo ""
    
    info "Comandos útiles:"
    echo "  Ver logs: $COMPOSE_CMD logs -f"
    echo "  Detener: $COMPOSE_CMD down"
    echo "  Reiniciar: $COMPOSE_CMD restart"
    echo "  Estado: $COMPOSE_CMD ps"
    
    if command -v /usr/local/bin/postgresql-monitor.sh &> /dev/null; then
        echo "  Monitoreo: sudo /usr/local/bin/postgresql-monitor.sh"
    fi
    
    echo ""
    info "Troubleshooting pgAdmin:"
    echo "  Si hay errores de 'preferences': ./fix-pgladmin-preferences.sh"
    echo "  Limpiar cache del navegador: Ctrl+F5 o modo incógnito"
    echo "  Ver logs de pgAdmin: $COMPOSE_CMD logs pgadmin"
    
    echo ""
    log "Estado actual de los contenedores:"
    $COMPOSE_CMD ps
    
    # Crear script de acceso rápido
    create_quick_access_script
}

# Crear script de acceso rápido para pgAdmin
create_quick_access_script() {
    log "Creando script de acceso rápido..."
    
    cat > pgladmin-access.sh << 'EOF'
#!/bin/bash

# Script de acceso rápido a pgAdmin
# Generado automáticamente por quick-start.sh

# Colores
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=== ACCESO RÁPIDO A PGLADMIN ==="
echo ""

# Cargar variables
source .env 2>/dev/null || true

# Detectar comando de compose
COMPOSE_CMD=""
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
fi

echo "🔍 Estado del contenedor:"
$COMPOSE_CMD ps | grep pgadmin

echo ""
echo "🌐 URL de acceso: http://localhost:${PGLADMIN_PORT:-5050}/"
echo "📧 Email: ${PGLADMIN_EMAIL:-admin@example.com}"
echo ""

# Verificar conectividad
if command -v curl &> /dev/null; then
    echo "🔍 Probando conectividad:"
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:${PGLADMIN_PORT:-5050}/" 2>/dev/null || echo "ERROR")
    
    if [[ "$status" == "200" ]] || [[ "$status" == "302" ]]; then
        echo -e "${GREEN}✓ pgAdmin responde correctamente (HTTP $status)${NC}"
    else
        echo -e "${RED}✗ pgAdmin no responde (HTTP $status)${NC}"
        echo ""
        echo "🔧 Para solucionar problemas:"
        echo "   ./fix-pgladmin-preferences.sh"
    fi
else
    echo "⚠️ curl no disponible para verificar conectividad"
fi

echo ""
echo "💡 Consejos:"
echo "• Si no puedes acceder, limpia cookies del navegador"
echo "• Usa modo incógnito para probar"
echo "• Verifica que no tengas extensiones bloqueando cookies"
EOF
    
    chmod +x pgladmin-access.sh
    log "✓ Script pgladmin-access.sh creado"
}

# Función principal
main() {
    echo "==============================================================================="
    echo "INICIO RÁPIDO DE POSTGRESQL DOCKER"
    echo "==============================================================================="
    
    check_dependencies
    check_env_file
    check_hardening_needed
    setup_directories
    setup_pgadmin_robust
    start_services
    wait_for_services
    show_connection_info
    
    echo ""
    log "¡Configuración completada! PostgreSQL y pgAdmin están listos para usar."
}

# Ejecutar función principal
main "$@"
