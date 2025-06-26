#!/bin/bash

#===============================================================================
# SCRIPT DE MANTENIMIENTO PARA POSTGRESQL DOCKER
# Descripción: Herramientas de mantenimiento y administración
# Autor: Administrador de Sistemas
# Fecha: $(date +%Y-%m-%d)
#===============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables
CONTAINER_NAME="postgresql_db"
PGADMIN_CONTAINER="pgadmin_web"
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

# Mostrar ayuda
show_help() {
    echo "Uso: $0 [comando]"
    echo ""
    echo "Comandos disponibles:"
    echo "  status          Mostrar estado de los servicios"
    echo "  logs            Mostrar logs de los servicios"
    echo "  restart         Reiniciar los servicios"
    echo "  update          Actualizar imágenes Docker"
    echo "  cleanup         Limpiar recursos Docker no utilizados"
    echo "  security        Verificar configuración de seguridad"
    echo "  backup          Crear backup de emergencia"
    echo "  monitor         Mostrar monitoreo en tiempo real"
    echo "  maintenance     Ejecutar tareas de mantenimiento de PostgreSQL"
    echo "  health          Verificar salud del sistema"
    echo ""
    echo "Ejemplos:"
    echo "  $0 status"
    echo "  $0 logs postgres"
    echo "  $0 restart"
}

# Cargar variables de entorno
load_env() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    else
        warning "Archivo $ENV_FILE no encontrado"
    fi
}

# Mostrar estado de servicios
show_status() {
    log "=== ESTADO DE SERVICIOS ==="
    docker-compose ps
    
    echo ""
    log "=== HEALTH CHECKS ==="
    docker inspect $CONTAINER_NAME --format='{{.State.Health.Status}}' 2>/dev/null || echo "No disponible"
    
    echo ""
    log "=== USO DE RECURSOS ==="
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" $CONTAINER_NAME $PGLADMIN_CONTAINER 2>/dev/null
}

# Mostrar logs
show_logs() {
    local service="$1"
    if [[ -n "$service" ]]; then
        log "Mostrando logs de $service..."
        docker-compose logs -f "$service"
    else
        log "Mostrando logs de todos los servicios..."
        docker-compose logs -f
    fi
}

# Reiniciar servicios
restart_services() {
    log "Reiniciando servicios PostgreSQL..."
    docker-compose restart
    
    # Esperar que estén listos
    sleep 5
    show_status
}

# Actualizar imágenes
update_images() {
    log "Actualizando imágenes Docker..."
    docker-compose pull
    
    read -p "¿Reiniciar servicios con las nuevas imágenes? [y/N]: " restart_confirm
    if [[ $restart_confirm =~ ^[Yy]$ ]]; then
        docker-compose down
        docker-compose up -d
        log "Servicios actualizados y reiniciados"
    fi
}

# Limpiar recursos Docker
cleanup_docker() {
    log "Limpiando recursos Docker no utilizados..."
    
    # Limpiar contenedores parados
    docker container prune -f
    
    # Limpiar imágenes no utilizadas
    docker image prune -f
    
    # Limpiar volumes no utilizados (cuidado!)
    read -p "¿Limpiar volumes no utilizados? (PELIGROSO) [y/N]: " clean_volumes
    if [[ $clean_volumes =~ ^[Yy]$ ]]; then
        docker volume prune -f
    fi
    
    # Limpiar redes no utilizadas
    docker network prune -f
    
    log "Limpieza completada"
}

# Verificar configuración de seguridad
check_security() {
    log "=== VERIFICACIÓN DE SEGURIDAD ==="
    
    # Verificar UFW
    if command -v ufw &> /dev/null; then
        echo ""
        info "Estado de UFW:"
        ufw status | grep -E "(5432|5050|Status)"
    fi
    
    # Verificar Fail2Ban
    if command -v fail2ban-client &> /dev/null; then
        echo ""
        info "Estado de Fail2Ban:"
        fail2ban-client status 2>/dev/null || echo "No configurado"
        fail2ban-client status postgresql 2>/dev/null || echo "Jail postgresql no encontrado"
    fi
    
    # Verificar configuración de Docker
    echo ""
    info "Configuración de seguridad Docker:"
    docker inspect $CONTAINER_NAME --format='{{.HostConfig.SecurityOpt}}' 2>/dev/null
    
    # Verificar permisos de archivos
    echo ""
    info "Permisos de archivos críticos:"
    ls -la .env 2>/dev/null || echo ".env no encontrado"
    ls -la docker-compose.yml
}

# Backup de emergencia
emergency_backup() {
    log "Creando backup de emergencia..."
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="./emergency_backups"
    
    mkdir -p "$backup_dir"
    
    # Backup de la base de datos principal
    if docker exec $CONTAINER_NAME pg_dumpall -U "$POSTGRES_USER" > "$backup_dir/emergency_backup_$timestamp.sql"; then
        log "Backup de emergencia creado: $backup_dir/emergency_backup_$timestamp.sql"
    else
        error "Error al crear backup de emergencia"
    fi
}

# Monitoreo en tiempo real
monitor_real_time() {
    log "Iniciando monitoreo en tiempo real (Ctrl+C para salir)..."
    
    while true; do
        clear
        echo "=== MONITOREO POSTGRESQL - $(date) ==="
        echo ""
        
        # Estado de contenedores
        docker-compose ps
        echo ""
        
        # Recursos
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" $CONTAINER_NAME $PGLADMIN_CONTAINER 2>/dev/null
        echo ""
        
        # Conexiones activas
        if docker exec $CONTAINER_NAME psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "SELECT count(*) as conexiones_activas FROM pg_stat_activity;" 2>/dev/null; then
            echo ""
        fi
        
        # Últimos logs (5 líneas)
        echo "Últimos logs:"
        docker logs --tail 5 $CONTAINER_NAME 2>/dev/null
        
        sleep 10
    done
}

# Mantenimiento de PostgreSQL
postgresql_maintenance() {
    log "Ejecutando tareas de mantenimiento de PostgreSQL..."
    
    # VACUUM y ANALYZE
    log "Ejecutando VACUUM ANALYZE..."
    docker exec $CONTAINER_NAME psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "VACUUM ANALYZE;" 2>/dev/null || warning "Error en VACUUM ANALYZE"
    
    # Reindexar
    read -p "¿Ejecutar REINDEX? (puede tardar) [y/N]: " reindex_confirm
    if [[ $reindex_confirm =~ ^[Yy]$ ]]; then
        log "Ejecutando REINDEX..."
        docker exec $CONTAINER_NAME psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "REINDEX DATABASE \"$POSTGRES_DB\";" 2>/dev/null || warning "Error en REINDEX"
    fi
    
    # Estadísticas de la base de datos
    log "Estadísticas de la base de datos:"
    docker exec $CONTAINER_NAME psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "
        SELECT 
            schemaname,
            tablename,
            n_tup_ins as inserciones,
            n_tup_upd as actualizaciones,
            n_tup_del as eliminaciones
        FROM pg_stat_user_tables 
        ORDER BY n_tup_ins + n_tup_upd + n_tup_del DESC 
        LIMIT 10;
    " 2>/dev/null || warning "Error al obtener estadísticas"
}

# Verificar salud del sistema
health_check() {
    log "=== VERIFICACIÓN DE SALUD DEL SISTEMA ==="
    
    local issues=0
    
    # Verificar contenedores
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "Contenedor PostgreSQL no está ejecutándose"
        ((issues++))
    else
        log "✓ Contenedor PostgreSQL está activo"
    fi
    
    if ! docker ps | grep -q "$PGLADMIN_CONTAINER"; then
        error "Contenedor pgAdmin no está ejecutándose"
        ((issues++))
    else
        log "✓ Contenedor pgAdmin está activo"
    fi
    
    # Verificar conectividad
    if docker exec $CONTAINER_NAME pg_isready -U "$POSTGRES_USER" &>/dev/null; then
        log "✓ PostgreSQL acepta conexiones"
    else
        error "PostgreSQL no acepta conexiones"
        ((issues++))
    fi
    
    # Verificar espacio en disco
    local disk_usage=$(df -h . | tail -1 | awk '{print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 90 ]]; then
        error "Espacio en disco crítico: ${disk_usage}%"
        ((issues++))
    elif [[ $disk_usage -gt 80 ]]; then
        warning "Espacio en disco alto: ${disk_usage}%"
    else
        log "✓ Espacio en disco adecuado: ${disk_usage}%"
    fi
    
    # Verificar memoria
    local memory_usage=$(docker stats --no-stream --format "{{.MemPerc}}" $CONTAINER_NAME 2>/dev/null | sed 's/%//')
    if [[ -n "$memory_usage" ]] && [[ $(echo "$memory_usage > 90" | bc 2>/dev/null) -eq 1 ]]; then
        error "Uso de memoria crítico: ${memory_usage}%"
        ((issues++))
    fi
    
    echo ""
    if [[ $issues -eq 0 ]]; then
        log "✓ Sistema saludable - No se encontraron problemas"
    else
        error "Se encontraron $issues problema(s)"
    fi
}

# Función principal
main() {
    load_env
    
    case "${1:-status}" in
        status)
            show_status
            ;;
        logs)
            show_logs "$2"
            ;;
        restart)
            restart_services
            ;;
        update)
            update_images
            ;;
        cleanup)
            cleanup_docker
            ;;
        security)
            check_security
            ;;
        backup)
            emergency_backup
            ;;
        monitor)
            monitor_real_time
            ;;
        maintenance)
            postgresql_maintenance
            ;;
        health)
            health_check
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Comando desconocido: $1"
            show_help
            exit 1
            ;;
    esac
}

# Ejecutar función principal
main "$@"
