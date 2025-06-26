#!/bin/bash

#===============================================================================
# SCRIPT DE SOLUCIONES RÁPIDAS PARA PGADMIN
# Descripción: Aplicar soluciones comunes para problemas de pgAdmin
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

# Variables
COMPOSE_CMD=""

# Detectar comando de Docker Compose
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose no está disponible"
    exit 1
fi

# Mostrar menú de opciones
show_menu() {
    echo "==============================================================================="
    echo "SOLUCIONES RÁPIDAS PARA PGADMIN"
    echo "==============================================================================="
    echo ""
    echo "Selecciona una opción:"
    echo "1) Reiniciar solo pgAdmin"
    echo "2) Recrear completamente pgAdmin (elimina datos de sesión)"
    echo "3) Corregir permisos de directorios"
    echo "4) Limpiar volúmenes y recrear"
    echo "5) Verificar y reparar configuración"
    echo "6) Ver logs en tiempo real"
    echo "7) Salir"
    echo ""
}

# Opción 1: Reiniciar pgAdmin
restart_pgadmin() {
    log "Reiniciando pgAdmin..."
    $COMPOSE_CMD restart pgadmin
    
    if [ $? -eq 0 ]; then
        log "pgAdmin reiniciado exitosamente"
        log "Espera 30 segundos y luego intenta acceder nuevamente"
    else
        error "Error al reiniciar pgAdmin"
    fi
}

# Opción 2: Recrear pgAdmin
recreate_pgadmin() {
    warning "Esta opción eliminará todas las configuraciones y sesiones guardadas de pgAdmin"
    read -p "¿Estás seguro? (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        log "Deteniendo pgAdmin..."
        $COMPOSE_CMD stop pgadmin
        
        log "Eliminando contenedor..."
        $COMPOSE_CMD rm -f pgladmin_data
        
        log "Eliminando datos de sesión..."
        if [ -d "pgladmin_data" ]; then
            sudo rm -rf pgladmin_data/ 2>/dev/null || rm -rf pgladmin_data/
        fi
        
        log "Recreando pgAdmin..."
        $COMPOSE_CMD up -d pgadmin
        
        log "pgAdmin recreado. Espera 60 segundos antes de intentar acceder"
    else
        log "Operación cancelada"
    fi
}

# Opción 3: Corregir permisos
fix_permissions() {
    log "Corrigiendo permisos de directorios..."
    
    # Crear directorios si no existen
    mkdir -p pgladmin_data
    mkdir -p postgres_data
    
    # Corregir permisos para pgAdmin (usuario 5050)
    if command -v sudo &> /dev/null; then
        sudo chown -R 5050:5050 pgladmin_data/ 2>/dev/null
        sudo chown -R 999:999 postgres_data/ 2>/dev/null
    else
        chown -R 5050:5050 pgladmin_data/ 2>/dev/null
        chown -R 999:999 postgres_data/ 2>/dev/null
    fi
    
    # Verificar permisos
    echo "Permisos actuales:"
    ls -la pgladmin_data/ postgres_data/ 2>/dev/null || echo "Algunos directorios no existen"
    
    log "Permisos corregidos. Reiniciando servicios..."
    $COMPOSE_CMD restart
}

# Opción 4: Limpiar volúmenes
clean_volumes() {
    warning "Esta opción eliminará TODOS los datos de pgAdmin y PostgreSQL"
    read -p "¿Estás ABSOLUTAMENTE seguro? Esto borrará la base de datos (y/N): " confirm
    
    if [[ $confirm =~ ^[Yy]$ ]]; then
        log "Deteniendo todos los servicios..."
        $COMPOSE_CMD down
        
        log "Eliminando volúmenes..."
        if command -v sudo &> /dev/null; then
            sudo rm -rf pgladmin_data/ postgres_data/ 2>/dev/null
        else
            rm -rf pgladmin_data/ postgres_data/ 2>/dev/null
        fi
        
        log "Recreando servicios..."
        $COMPOSE_CMD up -d
        
        warning "IMPORTANTE: Tendrás que configurar pgAdmin desde cero"
    else
        log "Operación cancelada"
    fi
}

# Opción 5: Verificar configuración
verify_config() {
    log "Verificando configuración..."
    
    # Verificar archivo .env
    if [ -f ".env" ]; then
        log "Archivo .env encontrado"
        source .env
        
        if [ -z "$PGADMIN_EMAIL" ] || [ -z "$PGADMIN_PASSWORD" ]; then
            error "Credenciales de pgAdmin incompletas en .env"
            echo "Agrega las siguientes líneas a tu archivo .env:"
            echo "PGADMIN_EMAIL=tu_email@ejemplo.com"
            echo "PGADMIN_PASSWORD=tu_contraseña_segura"
        else
            log "Credenciales de pgAdmin configuradas correctamente"
        fi
    else
        error "Archivo .env no encontrado"
        log "Copia .env.example a .env y configura tus credenciales:"
        echo "cp .env.example .env"
        echo "nano .env"
    fi
    
    # Verificar docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        log "Archivo docker-compose.yml encontrado"
    else
        error "Archivo docker-compose.yml no encontrado"
    fi
    
    # Verificar estado de servicios
    log "Estado actual de servicios:"
    $COMPOSE_CMD ps
}

# Opción 6: Ver logs en tiempo real
watch_logs() {
    log "Mostrando logs de pgAdmin en tiempo real (Ctrl+C para salir)..."
    $COMPOSE_CMD logs -f pgadmin
}

# Función principal
main() {
    while true; do
        show_menu
        read -p "Selecciona una opción [1-7]: " choice
        
        case $choice in
            1)
                restart_pgadmin
                ;;
            2)
                recreate_pgadmin
                ;;
            3)
                fix_permissions
                ;;
            4)
                clean_volumes
                ;;
            5)
                verify_config
                ;;
            6)
                watch_logs
                ;;
            7)
                log "Saliendo..."
                exit 0
                ;;
            *)
                error "Opción inválida. Por favor selecciona 1-7"
                ;;
        esac
        
        echo ""
        read -p "Presiona Enter para continuar..."
        echo ""
    done
}

# Ejecutar función principal
main "$@"
