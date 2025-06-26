#!/bin/bash

#===============================================================================
# SCRIPT DE CONFIGURACIÓN POST-HARDENING PARA POSTGRESQL DOCKER
# Descripción: Configura UFW y puertos para PostgreSQL y pgAdmin después del hardening
# Autor: Administrador de Sistemas  
# Fecha: $(date +%Y-%m-%d)
#===============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables por defecto (se pueden sobrescribir con archivo .env)
DEFAULT_POSTGRES_PORT=5432
DEFAULT_PGADMIN_PORT=5050
ENV_FILE=".env"

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

# Verificar si se ejecuta como root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "Este script debe ejecutarse como root o con sudo"
        exit 1
    fi
}

# Cargar variables del archivo .env si existe
load_env_variables() {
    if [[ -f "$ENV_FILE" ]]; then
        log "Cargando variables desde $ENV_FILE"
        source "$ENV_FILE"
    else
        warning "Archivo $ENV_FILE no encontrado, usando valores por defecto"
        warning "Copia .env.example a .env y configura tus valores antes de ejecutar este script"
    fi
    
    # Usar variables de entorno o valores por defecto
    POSTGRES_PORT=${POSTGRES_PORT:-$DEFAULT_POSTGRES_PORT}
    PGADMIN_PORT=${PGADMIN_PORT:-$DEFAULT_PGADMIN_PORT}
    
    info "Puerto PostgreSQL: $POSTGRES_PORT"
    info "Puerto pgAdmin: $PGADMIN_PORT"
}

# Verificar si UFW está instalado y activo
check_ufw_status() {
    if ! command -v ufw &> /dev/null; then
        error "UFW no está instalado. Instalando UFW..."
        apt update && apt install -y ufw
    fi
    
    local ufw_status=$(ufw status | head -n1)
    if [[ $ufw_status == *"inactive"* ]]; then
        warning "UFW está inactivo. Activando UFW..."
        ufw --force enable
    fi
    
    log "Estado actual de UFW:"
    ufw status numbered
}

# Configurar reglas UFW para PostgreSQL
configure_postgresql_firewall() {
    log "Configurando reglas de firewall para PostgreSQL (puerto $POSTGRES_PORT)..."
    
    # Permitir conexiones a PostgreSQL desde localhost
    ufw allow from 127.0.0.1 to any port $POSTGRES_PORT comment "PostgreSQL local access"
    
    # Permitir conexiones desde redes privadas (ajusta según tu red)
    ufw allow from 10.0.0.0/8 to any port $POSTGRES_PORT comment "PostgreSQL private network"
    ufw allow from 172.16.0.0/12 to any port $POSTGRES_PORT comment "PostgreSQL private network"
    ufw allow from 192.168.0.0/16 to any port $POSTGRES_PORT comment "PostgreSQL private network"
    
    # Si necesitas acceso desde internet (NO RECOMENDADO sin VPN)
    read -p "¿Permitir acceso a PostgreSQL desde internet? (NO recomendado) [y/N]: " allow_internet
    if [[ $allow_internet =~ ^[Yy]$ ]]; then
        warning "ATENCIÓN: Permitiendo acceso a PostgreSQL desde internet"
        warning "Asegúrate de tener contraseñas fuertes y considera usar VPN"
        ufw allow $POSTGRES_PORT comment "PostgreSQL internet access"
    fi
}

# Configurar reglas UFW para pgAdmin
configure_pgadmin_firewall() {
    log "Configurando reglas de firewall para pgAdmin (puerto $PGADMIN_PORT)..."
    
    # Permitir conexiones a pgAdmin desde localhost
    ufw allow from 127.0.0.1 to any port $PGADMIN_PORT comment "pgAdmin local access"
    
    # Permitir conexiones desde redes privadas
    ufw allow from 10.0.0.0/8 to any port $PGADMIN_PORT comment "pgAdmin private network"
    ufw allow from 172.16.0.0/12 to any port $PGADMIN_PORT comment "pgAdmin private network"
    ufw allow from 192.168.0.0/16 to any port $PGADMIN_PORT comment "pgAdmin private network"
    
    # Preguntar si permitir acceso desde internet para pgAdmin
    read -p "¿Permitir acceso a pgAdmin desde internet? [y/N]: " allow_pgadmin_internet
    if [[ $allow_pgadmin_internet =~ ^[Yy]$ ]]; then
        info "Permitiendo acceso a pgAdmin desde internet"
        ufw allow $PGADMIN_PORT comment "pgAdmin web interface"
    fi
}

# Configurar fail2ban para PostgreSQL
configure_fail2ban_postgresql() {
    log "Configurando Fail2Ban para PostgreSQL..."
    
    # Crear filtro para PostgreSQL
    cat > /etc/fail2ban/filter.d/postgresql.conf << 'EOF'
[Definition]
failregex = ^%(__prefix_line)s.*FATAL:.*password authentication failed for user.*$
            ^%(__prefix_line)s.*FATAL:.*no pg_hba.conf entry for host.*$
            ^%(__prefix_line)s.*FATAL:.*authentication failed for user.*$
ignoreregex =
EOF

    # Añadir jail para PostgreSQL
    cat >> /etc/fail2ban/jail.local << EOF

[postgresql]
enabled = true
port = $POSTGRES_PORT
filter = postgresql
logpath = /var/log/postgresql/*.log
maxretry = 3
bantime = 3600
findtime = 600
EOF

    # Reiniciar fail2ban
    systemctl restart fail2ban
    log "Fail2Ban configurado para PostgreSQL"
}

# Configurar límites de conexión en kernel
configure_kernel_limits() {
    log "Configurando límites del kernel para PostgreSQL..."
    
    # Añadir configuraciones para PostgreSQL
    cat >> /etc/sysctl.d/99-postgresql.conf << 'EOF'
# Configuraciones optimizadas para PostgreSQL
kernel.shmmax = 268435456
kernel.shmall = 4194304
fs.file-max = 65536

# Configuraciones de red para base de datos
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
EOF

    # Aplicar cambios
    sysctl -p /etc/sysctl.d/99-postgresql.conf
}

# Crear script de monitoreo
create_monitoring_script() {
    log "Creando script de monitoreo para PostgreSQL..."
    
    cat > /usr/local/bin/postgresql-monitor.sh << 'EOF'
#!/bin/bash
# Script de monitoreo para PostgreSQL Docker

POSTGRES_CONTAINER="postgresql_db"
PGADMIN_CONTAINER="pgadmin_web"

echo "=== Estado de contenedores PostgreSQL ==="
docker ps --filter "name=$POSTGRES_CONTAINER" --filter "name=$PGADMIN_CONTAINER"

echo ""
echo "=== Uso de recursos ==="
docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}"

echo ""
echo "=== Logs recientes PostgreSQL ==="
docker logs --tail 10 $POSTGRES_CONTAINER 2>/dev/null || echo "Contenedor PostgreSQL no encontrado"

echo ""
echo "=== Conexiones UFW activas ==="
ufw status | grep -E "(5432|5050)"

echo ""
echo "=== Estado de Fail2Ban ==="
fail2ban-client status postgresql 2>/dev/null || echo "Jail postgresql no configurado"
EOF

    chmod +x /usr/local/bin/postgresql-monitor.sh
    log "Script de monitoreo creado en /usr/local/bin/postgresql-monitor.sh"
}

# Crear cron job para limpieza de logs
setup_log_rotation() {
    log "Configurando rotación de logs para Docker..."
    
    # Configurar logrotate para logs de Docker
    cat > /etc/logrotate.d/docker-postgresql << 'EOF'
/var/lib/docker/containers/*/*-json.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0644 root root
    postrotate
        /bin/kill -USR1 $(cat /var/run/docker.pid 2>/dev/null) 2>/dev/null || true
    endscript
}
EOF
}

# Mostrar información de conexión
show_connection_info() {
    echo ""
    log "=== INFORMACIÓN DE CONEXIÓN ==="
    echo ""
    info "PostgreSQL:"
    echo "  Host: localhost"
    echo "  Puerto: $POSTGRES_PORT"
    echo "  Usuario: \$POSTGRES_USER (definido en .env)"
    echo "  Base de datos: \$POSTGRES_DB (definido en .env)"
    echo "  Conexión: postgresql://usuario:contraseña@localhost:$POSTGRES_PORT/basedatos"
    echo ""
    info "pgAdmin:"
    echo "  URL: http://localhost:$PGADMIN_PORT"
    echo "  Email: \$PGADMIN_EMAIL (definido en .env)"
    echo "  Contraseña: \$PGADMIN_PASSWORD (definido en .env)"
    echo ""
    info "Comandos útiles:"
    echo "  Monitoreo: sudo /usr/local/bin/postgresql-monitor.sh"
    echo "  Ver logs: docker-compose logs -f"
    echo "  Estado UFW: sudo ufw status"
    echo "  Estado Fail2Ban: sudo fail2ban-client status"
}

# Función principal
main() {
    echo "==============================================================================="
    echo "CONFIGURACIÓN POST-HARDENING PARA POSTGRESQL DOCKER"
    echo "==============================================================================="
    
    check_root
    load_env_variables
    
    echo ""
    warning "Este script configurará:"
    echo "- Reglas UFW para PostgreSQL (puerto $POSTGRES_PORT)"
    echo "- Reglas UFW para pgAdmin (puerto $PGADMIN_PORT)"
    echo "- Fail2Ban para PostgreSQL"
    echo "- Optimizaciones del kernel"
    echo "- Scripts de monitoreo"
    echo ""
    
    read -p "¿Continuar con la configuración? [y/N]: " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        info "Configuración cancelada"
        exit 0
    fi
    
    check_ufw_status
    configure_postgresql_firewall
    configure_pgadmin_firewall
    configure_fail2ban_postgresql
    configure_kernel_limits
    create_monitoring_script
    setup_log_rotation
    
    echo ""
    log "=== CONFIGURACIÓN COMPLETADA ==="
    show_connection_info
    
    echo ""
    log "Estado final de UFW:"
    ufw status numbered
}

# Ejecutar función principal
main "$@"
