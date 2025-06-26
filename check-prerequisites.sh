#!/bin/bash

#===============================================================================
# SCRIPT DE VERIFICACIÓN DE PRE# Verificar dir# Verificar directorios necesarios
log "Verificando directorios..."
# Estos directorios son necesarios para:
# - postgres_data: Almacena los datos de PostgreSQL (tablas, índices, configuraciones)
# - pgladmin_data: Guarda las configuraciones y sesiones de pgAdmin
# - init-scripts: Scripts SQL que se ejecutan al crear la BD por primera vez
# - pgladmin-config: Configuraciones adicionales de pgAdmin (servers predefinidos, etc.)
# 
# NOTA: Las carpetas de datos (postgres_data, pgladmin_data, pgladmin-config) están en .gitignore
# y se crean automáticamente al iniciar los contenedores
DIRECTORIES=("postgres_data" "pgladmin_data" "init-scripts" "pgladmin-config")
for dir in "${DIRECTORIES[@]}"; do
    if [[ -d "$dir" ]]; then
        check_mark "Directorio $dir existe"
    else
        if [[ "$dir" == "init-scripts" ]]; then
            warning "Directorio $dir no existe (crear si necesitas scripts de inicialización)"
            WARNINGS=$((WARNINGS + 1))
        else
            info "Directorio $dir no existe (se creará automáticamente al iniciar)"
        fi
    fi
donecesarios
log "Verificando directorios..."
# Estos directorios son necesarios para:
# - postgres_data: Almacena los datos de PostgreSQL (tablas, índices, configuraciones)
# - pgadmin_data: Guarda las configuraciones y sesiones de pgAdmin
# - init-scripts: Scripts SQL que se ejecutan al crear la BD por primera vez
# - pgladmin-config: Configuraciones adicionales de pgAdmin (servers predefinidos, etc.)
DIRECTORIES=("postgres_data" "pgadmin_data" "init-scripts" "pgladmin-config")
for dir in "${DIRECTORIES[@]}"; do
    if [[ -d "$dir" ]]; then
        check_mark "Directorio $dir existe"
    else
        warning "Directorio $dir no existe (se creará automáticamente al iniciar)"
        WARNINGS=$((WARNINGS + 1))
    fi
done PARA POSTGRESQL DOCKER
# Descripción: Verifica que todos los pre-requisitos estén cumplidos
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

check_mark() {
    echo -e "${GREEN}✓${NC} $1"
}

x_mark() {
    echo -e "${RED}✗${NC} $1"
}

# Variables de estado
ERRORS=0
WARNINGS=0

echo "==============================================================================="
echo "VERIFICACIÓN DE PRE-REQUISITOS PARA POSTGRESQL DOCKER"
echo "==============================================================================="
echo ""

# Verificar Docker
log "Verificando Docker..."
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version | cut -d ' ' -f3 | tr -d ',')
    check_mark "Docker instalado: $DOCKER_VERSION"
    
    # Verificar Docker daemon
    if docker info &> /dev/null; then
        check_mark "Docker daemon corriendo"
    else
        x_mark "Docker daemon no está corriendo"
        ERRORS=$((ERRORS + 1))
    fi
else
    x_mark "Docker no está instalado"
    ERRORS=$((ERRORS + 1))
fi

# Verificar Docker Compose
log "Verificando Docker Compose..."
# Verificar primero el comando integrado 'docker compose'
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || docker compose version | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    check_mark "Docker Compose integrado instalado: $COMPOSE_VERSION"
# Si no está disponible, verificar docker-compose standalone
elif command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version | cut -d ' ' -f3 | tr -d ',')
    check_mark "Docker Compose standalone instalado: $COMPOSE_VERSION"
    warning "Se recomienda usar 'docker compose' en lugar de 'docker-compose'"
else
    x_mark "Docker Compose no está instalado"
    ERRORS=$((ERRORS + 1))
fi

# Verificar curl
log "Verificando curl..."
if command -v curl &> /dev/null; then
    check_mark "curl instalado"
else
    warning "curl no está instalado (opcional para verificación de servicios)"
    WARNINGS=$((WARNINGS + 1))
fi

# Verificar archivo .env
log "Verificando configuración..."
if [[ -f ".env" ]]; then
    check_mark "Archivo .env encontrado"
    
    # Verificar variables críticas
    source .env
    if [[ -n "$POSTGRES_PASSWORD" ]]; then
        check_mark "POSTGRES_PASSWORD configurada"
    else
        x_mark "POSTGRES_PASSWORD no está configurada en .env"
        ERRORS=$((ERRORS + 1))
    fi
    
    if [[ -n "$PGADMIN_PASSWORD" ]]; then
        check_mark "PGADMIN_PASSWORD configurada"
    else
        x_mark "PGADMIN_PASSWORD no está configurada en .env"
        ERRORS=$((ERRORS + 1))
    fi
else
    x_mark "Archivo .env no encontrado"
    ERRORS=$((ERRORS + 1))
    
    if [[ -f ".env.example" ]]; then
        info "Archivo .env.example disponible como plantilla"
    else
        x_mark "Archivo .env.example tampoco encontrado"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Verificar directorios necesarios
log "Verificando directorios..."
DIRECTORIES=("postgres_data" "pgadmin_data" "init-scripts" "pgadmin-config")
for dir in "${DIRECTORIES[@]}"; do
    if [[ -d "$dir" ]]; then
        check_mark "Directorio $dir existe"
    else
        warning "Directorio $dir no existe (se creará automáticamente)"
        WARNINGS=$((WARNINGS + 1))
    fi
done

# Verificar puertos disponibles
log "Verificando puertos..."
POSTGRES_PORT=${POSTGRES_PORT:-5432}
PGADMIN_PORT=${PGADMIN_PORT:-5050}

if command -v lsof &> /dev/null; then
    if lsof -Pi :$POSTGRES_PORT -sTCP:LISTEN -t &> /dev/null; then
        x_mark "Puerto $POSTGRES_PORT ya está en uso"
        ERRORS=$((ERRORS + 1))
    else
        check_mark "Puerto $POSTGRES_PORT disponible"
    fi
    
    if lsof -Pi :$PGADMIN_PORT -sTCP:LISTEN -t &> /dev/null; then
        x_mark "Puerto $PGADMIN_PORT ya está en uso"
        ERRORS=$((ERRORS + 1))
    else
        check_mark "Puerto $PGADMIN_PORT disponible"
    fi
elif command -v netstat &> /dev/null; then
    if netstat -tuln | grep -q ":$POSTGRES_PORT "; then
        x_mark "Puerto $POSTGRES_PORT ya está en uso"
        ERRORS=$((ERRORS + 1))
    else
        check_mark "Puerto $POSTGRES_PORT disponible"
    fi
    
    if netstat -tuln | grep -q ":$PGADMIN_PORT "; then
        x_mark "Puerto $PGADMIN_PORT ya está en uso"
        ERRORS=$((ERRORS + 1))
    else
        check_mark "Puerto $PGADMIN_PORT disponible"
    fi
else
    warning "No se puede verificar disponibilidad de puertos (lsof/netstat no disponibles)"
    WARNINGS=$((WARNINGS + 1))
fi

# Verificar espacio en disco
log "Verificando espacio en disco..."
if command -v df &> /dev/null; then
    AVAILABLE_SPACE=$(df . | awk 'NR==2 {print $4}')
    AVAILABLE_MB=$((AVAILABLE_SPACE / 1024))
    
    if [[ $AVAILABLE_MB -gt 1024 ]]; then
        check_mark "Espacio en disco suficiente: ${AVAILABLE_MB}MB disponibles"
    elif [[ $AVAILABLE_MB -gt 512 ]]; then
        warning "Poco espacio en disco: ${AVAILABLE_MB}MB disponibles (mínimo recomendado: 1GB)"
        WARNINGS=$((WARNINGS + 1))
    else
        x_mark "Espacio en disco insuficiente: ${AVAILABLE_MB}MB disponibles"
        ERRORS=$((ERRORS + 1))
    fi
else
    warning "No se puede verificar espacio en disco"
    WARNINGS=$((WARNINGS + 1))
fi

# Verificar configuración de firewall (si aplica)
log "Verificando configuración de firewall..."
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -n1)
    if [[ $UFW_STATUS == *"active"* ]]; then
        if ufw status | grep -q "5432\|5050"; then
            check_mark "Reglas UFW para PostgreSQL configuradas"
        else
            warning "UFW activo pero sin reglas para PostgreSQL (ejecutar configure-post-hardening.sh)"
            WARNINGS=$((WARNINGS + 1))
        fi
    else
        check_mark "UFW inactivo o no configurado"
    fi
else
    check_mark "UFW no instalado (no se requiere configuración adicional)"
fi

# Resumen final
echo ""
echo "==============================================================================="
if [[ $ERRORS -eq 0 ]]; then
    log "VERIFICACIÓN COMPLETADA EXITOSAMENTE"
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "${YELLOW}Advertencias: $WARNINGS${NC}"
    fi
    echo ""
    check_mark "Sistema listo para ejecutar PostgreSQL Docker"
    echo ""
    info "Para iniciar los servicios, ejecuta:"
    echo "  ./quick-start.sh"
else
    error "VERIFICACIÓN FALLÓ"
    echo -e "${RED}Errores: $ERRORS${NC}"
    echo -e "${YELLOW}Advertencias: $WARNINGS${NC}"
    echo ""
    x_mark "Sistema NO está listo para PostgreSQL Docker"
    echo ""
    error "Corrige los errores antes de continuar"
fi
echo "==============================================================================="

exit $ERRORS
