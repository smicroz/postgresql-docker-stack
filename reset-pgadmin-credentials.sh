#!/bin/bash

#===============================================================================
# SCRIPT PARA RESETEAR CREDENCIALES DE PGADMIN
# Descripción: Resetea las credenciales de pgAdmin cuando no puedes acceder
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

echo "==============================================================================="
echo "RESETEAR CREDENCIALES DE PGADMIN"
echo "==============================================================================="
echo ""

# Verificar que docker compose esté disponible
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

log "Mostrando configuración actual de pgAdmin..."
if [ -f ".env" ]; then
    echo "Credenciales actuales en .env:"
    grep -E "PGADMIN_EMAIL|PGADMIN_PASSWORD" .env | sed 's/PGADMIN_PASSWORD=.*/PGADMIN_PASSWORD=***OCULTA***/'
else
    error "Archivo .env no encontrado"
    exit 1
fi

echo ""
log "¿Qué quieres hacer?"
echo "1) Ver la contraseña actual"
echo "2) Cambiar email y contraseña"
echo "3) Solo cambiar contraseña"
echo "4) Recrear completamente pgAdmin (elimina todas las configuraciones)"
echo "5) Salir"

read -p "Selecciona una opción [1-5]: " choice

case $choice in
    1)
        log "Contraseña actual:"
        grep "PGADMIN_PASSWORD=" .env
        ;;
    2)
        read -p "Nuevo email: " new_email
        read -s -p "Nueva contraseña: " new_password
        echo ""
        
        # Actualizar .env
        sed -i.bak "s/PGADMIN_EMAIL=.*/PGLADMIN_EMAIL=$new_email/" .env
        sed -i.bak "s/PGADMIN_PASSWORD=.*/PGLADMIN_PASSWORD=$new_password/" .env
        
        log "Credenciales actualizadas en .env"
        log "Recreando pgAdmin con nuevas credenciales..."
        
        ${SUDO_PREFIX}${COMPOSE_CMD} stop pgladmin
        ${SUDO_PREFIX}${COMPOSE_CMD} rm -f pgladmin
        sudo rm -rf pgladmin_data/ 2>/dev/null || rm -rf pgladmin_data/
        ${SUDO_PREFIX}${COMPOSE_CMD} up -d pgladmin
        
        log "pgAdmin recreado. Espera 30 segundos y prueba con las nuevas credenciales"
        ;;
    3)
        read -s -p "Nueva contraseña: " new_password
        echo ""
        
        # Actualizar .env
        sed -i.bak "s/PGADMIN_PASSWORD=.*/PGLADMIN_PASSWORD=$new_password/" .env
        
        log "Contraseña actualizada en .env"
        log "Recreando pgAdmin con nueva contraseña..."
        
        ${SUDO_PREFIX}${COMPOSE_CMD} stop pgladmin
        ${SUDO_PREFIX}${COMPOSE_CMD} rm -f pgladmin
        sudo rm -rf pgladmin_data/ 2>/dev/null || rm -rf pgladmin_data/
        ${SUDO_PREFIX}${COMPOSE_CMD} up -d pgladmin
        
        log "pgAdmin recreado. Espera 30 segundos y prueba con la nueva contraseña"
        ;;
    4)
        warning "Esto eliminará TODAS las configuraciones de pgAdmin"
        read -p "¿Estás seguro? (y/N): " confirm
        
        if [[ $confirm =~ ^[Yy]$ ]]; then
            log "Recreando pgAdmin completamente..."
            
            ${SUDO_PREFIX}${COMPOSE_CMD} stop pgladmin
            ${SUDO_PREFIX}${COMPOSE_CMD} rm -f pgladmin
            sudo rm -rf pgladmin_data/ 2>/dev/null || rm -rf pgladmin_data/
            ${SUDO_PREFIX}${COMPOSE_CMD} up -d pgladmin
            
            log "pgAdmin recreado completamente"
            log "Usa las credenciales de tu archivo .env para acceder"
        else
            log "Operación cancelada"
        fi
        ;;
    5)
        log "Saliendo..."
        exit 0
        ;;
    *)
        error "Opción inválida"
        exit 1
        ;;
esac

echo ""
log "Información de acceso:"
if [ -f ".env" ]; then
    source .env
    echo "URL: http://192.168.3.243:${PGLADMIN_PORT:-5050}/login"
    echo "Email: ${PGLADMIN_EMAIL:-No configurado}"
    echo "Contraseña: [Ver archivo .env]"
fi

echo ""
log "Si el problema persiste:"
echo "1. Limpia cookies del navegador para el sitio"
echo "2. Prueba en modo incógnito"
echo "3. Verifica que no tengas bloqueadores de ads activos"
