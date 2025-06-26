#!/bin/bash

#===============================================================================
# SCRIPT DE DIAGNÓSTICO PARA PGADMIN REMOTO
# Descripción: Diagnostica problemas con pgAdmin en servidor remoto
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

echo "==============================================================================="
echo "DIAGNÓSTICO DE PGADMIN - SERVIDOR REMOTO"
echo "==============================================================================="
echo ""

# Variables
COMPOSE_CMD=""
ENV_FILE=".env"

# Detectar comando de Docker Compose
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    error "Docker Compose no está disponible"
    exit 1
fi

log "Usando comando: $COMPOSE_CMD"
echo ""

# 1. Verificar estado de contenedores
log "1. Verificando estado de contenedores..."
echo "----------------------------------------"
$COMPOSE_CMD ps
echo ""

# 2. Verificar logs de pgAdmin
log "2. Logs de pgAdmin (últimas 50 líneas)..."
echo "----------------------------------------"
$COMPOSE_CMD logs --tail=50 pgadmin
echo ""

# 3. Verificar permisos de volúmenes
log "3. Verificando permisos de volúmenes..."
echo "----------------------------------------"
if [ -d "pgladmin_data" ]; then
    ls -la pgladmin_data/
    echo ""
    echo "Propietario del directorio pgladmin_data:"
    stat -c "%U:%G (%u:%g)" pgladmin_data/ 2>/dev/null || stat -f "%Su:%Sg (%u:%g)" pgladmin_data/
else
    warning "Directorio pgladmin_data no existe"
fi
echo ""

# 4. Verificar conectividad interna
log "4. Verificando conectividad entre contenedores..."
echo "----------------------------------------"
if docker ps --format "table {{.Names}}\t{{.Status}}" | grep -q pgadmin; then
    # Verificar si pgAdmin puede resolver el nombre del contenedor postgres
    docker exec -it $(docker ps --filter "name=pgadmin" --format "{{.ID}}") nslookup postgres 2>/dev/null || echo "No se pudo resolver 'postgres' desde pgAdmin"
    echo ""
    
    # Verificar conectividad de red
    docker exec -it $(docker ps --filter "name=pgadmin" --format "{{.ID}}") ping -c 2 postgres 2>/dev/null || echo "No se puede hacer ping a postgres desde pgAdmin"
else
    warning "Contenedor pgAdmin no está ejecutándose"
fi
echo ""

# 5. Verificar puertos y firewall
log "5. Verificando puertos y acceso..."
echo "----------------------------------------"
if [ -f "$ENV_FILE" ]; then
    source $ENV_FILE
    PGADMIN_PORT=${PGADMIN_PORT:-5050}
    
    echo "Puerto configurado para pgAdmin: $PGADMIN_PORT"
    
    # Verificar si el puerto está en uso
    if command -v netstat &> /dev/null; then
        netstat -tlnp | grep ":$PGADMIN_PORT " || echo "Puerto $PGADMIN_PORT no está en uso"
    elif command -v ss &> /dev/null; then
        ss -tlnp | grep ":$PGADMIN_PORT " || echo "Puerto $PGADMIN_PORT no está en uso"
    fi
    
    echo ""
    
    # Verificar acceso local
    if command -v curl &> /dev/null; then
        echo "Probando acceso local a pgAdmin..."
        curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" http://localhost:$PGADMIN_PORT/ --connect-timeout 5 || echo "No se puede conectar localmente"
    fi
else
    warning "Archivo .env no encontrado"
fi
echo ""

# 6. Verificar espacio en disco
log "6. Verificando espacio en disco..."
echo "----------------------------------------"
df -h .
echo ""

# 7. Verificar memoria y recursos
log "7. Verificando recursos del sistema..."
echo "----------------------------------------"
free -h
echo ""
echo "Uso de CPU y memoria por contenedores:"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
echo ""

# 8. Verificar configuración de pgAdmin
log "8. Verificando configuración de pgAdmin..."
echo "----------------------------------------"
if [ -f "$ENV_FILE" ]; then
    source $ENV_FILE
    echo "Email configurado: ${PGADMIN_EMAIL:-No configurado}"
    echo "Puerto configurado: ${PGADMIN_PORT:-5050}"
    
    # Verificar si las credenciales están configuradas
    if [ -z "$PGADMIN_EMAIL" ] || [ -z "$PGADMIN_PASSWORD" ]; then
        error "Credenciales de pgAdmin no están completamente configuradas en .env"
    fi
else
    error "No se pudo cargar archivo .env"
fi
echo ""

# 9. Verificar logs del sistema
log "9. Verificando logs del sistema (si están disponibles)..."
echo "----------------------------------------"
if [ -f "/var/log/syslog" ]; then
    tail -20 /var/log/syslog | grep -i pgadmin || echo "No hay logs de pgAdmin en syslog"
elif [ -f "/var/log/messages" ]; then
    tail -20 /var/log/messages | grep -i pgadmin || echo "No hay logs de pgAdmin en messages"
else
    echo "Logs del sistema no accesibles"
fi
echo ""

# 10. Sugerencias de solución
log "10. SUGERENCIAS DE SOLUCIÓN:"
echo "----------------------------------------"
echo "a) Reiniciar solo pgAdmin:"
echo "   $COMPOSE_CMD restart pgadmin"
echo ""
echo "b) Recrear el contenedor de pgAdmin:"
echo "   $COMPOSE_CMD stop pgadmin"
echo "   $COMPOSE_CMD rm -f pgadmin"
echo "   rm -rf pgladmin_data/"
echo "   $COMPOSE_CMD up -d pgadmin"
echo ""
echo "c) Verificar y corregir permisos:"
echo "   sudo chown -R 5050:5050 pgladmin_data/"
echo ""
echo "d) Verificar conectividad desde tu Mac:"
echo "   curl -v http://IP_DEL_SERVIDOR:$PGADMIN_PORT/"
echo ""
echo "e) Si el problema persiste, revisar logs completos:"
echo "   $COMPOSE_CMD logs pgadmin > pgadmin_full.log"
echo ""

log "Diagnóstico completado. Revisa los resultados arriba."
