#!/bin/bash

#===============================================================================
# SCRIPT DE BACKUP PARA POSTGRESQL DOCKER
# Descripción: Crea backups de bases de datos PostgreSQL
# Autor: Administrador de Sistemas
# Fecha: $(date +%Y-%m-%d)
#===============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables por defecto
BACKUP_DIR="./backups"
ENV_FILE=".env"
CONTAINER_NAME="postgresql_db"
RETENTION_DAYS=7

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
    echo "Uso: $0 [opciones]"
    echo ""
    echo "Opciones:"
    echo "  -h, --help              Mostrar esta ayuda"
    echo "  -d, --database DB       Base de datos específica a respaldar"
    echo "  -o, --output DIR        Directorio de salida (default: ./backups)"
    echo "  -r, --retention DAYS    Días de retención (default: 7)"
    echo "  --all                   Respaldar todas las bases de datos"
    echo "  --compress              Comprimir backup con gzip"
    echo ""
    echo "Ejemplos:"
    echo "  $0 --all --compress"
    echo "  $0 -d mydatabase -o /backup"
    echo "  $0 --database mydatabase --retention 30"
}

# Procesar argumentos
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--database)
            SPECIFIC_DB="$2"
            shift 2
            ;;
        -o|--output)
            BACKUP_DIR="$2"
            shift 2
            ;;
        -r|--retention)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --all)
            BACKUP_ALL=true
            shift
            ;;
        --compress)
            COMPRESS=true
            shift
            ;;
        *)
            error "Opción desconocida: $1"
            show_help
            exit 1
            ;;
    esac
done

# Cargar variables de entorno
load_env_variables() {
    if [[ -f "$ENV_FILE" ]]; then
        source "$ENV_FILE"
    else
        error "Archivo $ENV_FILE no encontrado"
        exit 1
    fi
}

# Verificar que el contenedor esté ejecutándose
check_container() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        error "Contenedor $CONTAINER_NAME no está ejecutándose"
        exit 1
    fi
}

# Crear directorio de backup
create_backup_dir() {
    if [[ ! -d "$BACKUP_DIR" ]]; then
        mkdir -p "$BACKUP_DIR"
        log "Directorio de backup creado: $BACKUP_DIR"
    fi
}

# Realizar backup de una base de datos específica
backup_database() {
    local db_name="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/${db_name}_backup_${timestamp}.sql"
    
    log "Iniciando backup de la base de datos: $db_name"
    
    # Ejecutar pg_dump en el contenedor
    if docker exec "$CONTAINER_NAME" pg_dump -U "$POSTGRES_USER" -d "$db_name" > "$backup_file"; then
        log "Backup completado: $backup_file"
        
        # Comprimir si se solicita
        if [[ "$COMPRESS" == "true" ]]; then
            gzip "$backup_file"
            backup_file="${backup_file}.gz"
            log "Backup comprimido: $backup_file"
        fi
        
        # Mostrar tamaño del archivo
        local file_size=$(du -h "$backup_file" | cut -f1)
        info "Tamaño del backup: $file_size"
        
    else
        error "Error al crear backup de $db_name"
        return 1
    fi
}

# Realizar backup de todas las bases de datos
backup_all_databases() {
    log "Obteniendo lista de bases de datos..."
    
    # Obtener lista de bases de datos (excluyendo las del sistema)
    local databases=$(docker exec "$CONTAINER_NAME" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -c "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres', 'template1', 'template0');" | grep -v '^$' | tr -d ' ')
    
    if [[ -z "$databases" ]]; then
        warning "No se encontraron bases de datos de usuario"
        return 1
    fi
    
    log "Bases de datos encontradas:"
    echo "$databases"
    echo ""
    
    # Backup de cada base de datos
    while IFS= read -r db; do
        if [[ -n "$db" ]]; then
            backup_database "$db"
        fi
    done <<< "$databases"
}

# Realizar backup completo del cluster
backup_cluster() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_file="$BACKUP_DIR/cluster_backup_${timestamp}.sql"
    
    log "Iniciando backup completo del cluster PostgreSQL..."
    
    if docker exec "$CONTAINER_NAME" pg_dumpall -U "$POSTGRES_USER" > "$backup_file"; then
        log "Backup del cluster completado: $backup_file"
        
        if [[ "$COMPRESS" == "true" ]]; then
            gzip "$backup_file"
            backup_file="${backup_file}.gz"
            log "Backup comprimido: $backup_file"
        fi
        
        local file_size=$(du -h "$backup_file" | cut -f1)
        info "Tamaño del backup: $file_size"
    else
        error "Error al crear backup del cluster"
        return 1
    fi
}

# Limpiar backups antiguos
cleanup_old_backups() {
    log "Limpiando backups antiguos (retención: $RETENTION_DAYS días)..."
    
    # Buscar y eliminar archivos más antiguos que RETENTION_DAYS
    local deleted_count=$(find "$BACKUP_DIR" -name "*.sql*" -type f -mtime +$RETENTION_DAYS -delete -print | wc -l)
    
    if [[ $deleted_count -gt 0 ]]; then
        log "Se eliminaron $deleted_count backups antiguos"
    else
        info "No hay backups antiguos para eliminar"
    fi
}

# Mostrar estadísticas de backups
show_backup_stats() {
    log "=== ESTADÍSTICAS DE BACKUPS ==="
    
    local total_files=$(find "$BACKUP_DIR" -name "*.sql*" -type f | wc -l)
    local total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1 || echo "0")
    
    info "Total de archivos de backup: $total_files"
    info "Espacio total utilizado: $total_size"
    
    echo ""
    log "Backups más recientes:"
    find "$BACKUP_DIR" -name "*.sql*" -type f -printf "%T@ %p\n" | sort -nr | head -5 | while read timestamp file; do
        local date_formatted=$(date -d @"${timestamp%.*}" '+%Y-%m-%d %H:%M:%S')
        local file_size=$(du -h "$file" | cut -f1)
        echo "  $date_formatted - $(basename "$file") ($file_size)"
    done
}

# Función principal
main() {
    echo "==============================================================================="
    echo "BACKUP DE POSTGRESQL DOCKER"
    echo "==============================================================================="
    
    load_env_variables
    check_container
    create_backup_dir
    
    if [[ -n "$SPECIFIC_DB" ]]; then
        # Backup de base de datos específica
        backup_database "$SPECIFIC_DB"
    elif [[ "$BACKUP_ALL" == "true" ]]; then
        # Backup de todas las bases de datos
        backup_all_databases
        # También hacer backup del cluster completo
        backup_cluster
    else
        # Por defecto, backup de la base de datos principal
        backup_database "$POSTGRES_DB"
    fi
    
    cleanup_old_backups
    show_backup_stats
    
    echo ""
    log "Proceso de backup completado"
}

# Ejecutar función principal
main "$@"
