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

# Crear directorios necesarios
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
    
    if [[ ! -d "pgadmin_data" ]]; then
        log "Creando directorio pgadmin_data..."
        mkdir -p pgadmin_data
        # Asegurar permisos correctos para pgAdmin (usuario 5050)
        if command -v chown &> /dev/null; then
            chown 5050:5050 pgadmin_data 2>/dev/null || warning "No se pudieron configurar permisos para pgadmin_data"
        fi
    fi
    
    if [[ ! -d "pgadmin-config" ]]; then
        log "Creando directorio pgadmin-config..."
        mkdir -p pgadmin-config
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

# Esperar que los servicios estén listos
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
    
    # Esperar pgAdmin
    echo -n "Esperando pgAdmin"
    for i in {1..30}; do
        if command -v curl &> /dev/null && curl -s http://localhost:${PGADMIN_PORT:-5050} &>/dev/null; then
            echo " ✓"
            break
        elif ! command -v curl &> /dev/null && [[ $i -eq 10 ]]; then
            echo " ⚠️ (curl no disponible, asumiendo que está listo)"
            break
        fi
        echo -n "."
        sleep 2
    done
    
    log "Servicios listos"
}

# Mostrar información de conexión
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
    echo "  URL: http://localhost:${PGADMIN_PORT:-5050}"
    echo "  Email: ${PGADMIN_EMAIL:-admin@example.com}"
    echo "  Contraseña: ${PGADMIN_PASSWORD:-[definida en .env]}"
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
    log "Estado actual de los contenedores:"
    $COMPOSE_CMD ps
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
    start_services
    wait_for_services
    show_connection_info
    
    echo ""
    log "¡Configuración completada! PostgreSQL y pgAdmin están listos para usar."
}

# Ejecutar función principal
main "$@"
