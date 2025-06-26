#!/bin/bash

#===============================================================================
# SCRIPT DE PRUEBA DE CONECTIVIDAD REMOTA PARA PGADMIN
# Descripción: Prueba la conectividad desde tu Mac al servidor remoto
# Autor: Administrador de Sistemas
# Fecha: $(date +%Y-%m-%d)
#===============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
echo "PRUEBA DE CONECTIVIDAD REMOTA - PGADMIN"
echo "==============================================================================="
echo ""

# Solicitar información del servidor
read -p "Ingresa la IP o dominio del servidor remoto: " SERVER_IP
read -p "Ingresa el puerto de pgAdmin (por defecto 5050): " PGADMIN_PORT
PGADMIN_PORT=${PGADMIN_PORT:-5050}

echo ""
log "Probando conectividad a $SERVER_IP:$PGADMIN_PORT"
echo ""

# 1. Ping al servidor
log "1. Probando conectividad básica (ping)..."
if ping -c 3 "$SERVER_IP" > /dev/null 2>&1; then
    echo "✅ El servidor responde a ping"
else
    warning "⚠️ El servidor no responde a ping (puede estar bloqueado por firewall)"
fi
echo ""

# 2. Verificar si el puerto está abierto
log "2. Verificando si el puerto $PGADMIN_PORT está abierto..."
if command -v nc &> /dev/null; then
    if nc -z -w5 "$SERVER_IP" "$PGADMIN_PORT" 2>/dev/null; then
        echo "✅ Puerto $PGADMIN_PORT está abierto"
    else
        error "❌ Puerto $PGADMIN_PORT está cerrado o bloqueado"
    fi
elif command -v telnet &> /dev/null; then
    if timeout 5 telnet "$SERVER_IP" "$PGADMIN_PORT" </dev/null 2>/dev/null | grep -q "Connected"; then
        echo "✅ Puerto $PGADMIN_PORT está abierto"
    else
        error "❌ Puerto $PGADMIN_PORT está cerrado o bloqueado"
    fi
else
    warning "nc y telnet no están disponibles, saltando verificación de puerto"
fi
echo ""

# 3. Probar respuesta HTTP
log "3. Probando respuesta HTTP de pgAdmin..."
if command -v curl &> /dev/null; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 "http://$SERVER_IP:$PGADMIN_PORT/" 2>/dev/null)
    
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "✅ pgAdmin responde correctamente (HTTP 200)"
    elif [ "$HTTP_STATUS" = "302" ] || [ "$HTTP_STATUS" = "301" ]; then
        echo "✅ pgAdmin responde con redirección (HTTP $HTTP_STATUS)"
    elif [ "$HTTP_STATUS" = "000" ]; then
        error "❌ No se puede conectar al servidor"
    else
        warning "⚠️ pgAdmin responde pero con estado HTTP: $HTTP_STATUS"
    fi
    
    # Probar también HTTPS por si acaso
    HTTPS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 10 -k "https://$SERVER_IP:$PGADMIN_PORT/" 2>/dev/null)
    if [ "$HTTPS_STATUS" != "000" ] && [ "$HTTPS_STATUS" != "$HTTP_STATUS" ]; then
        echo "ℹ️ También responde en HTTPS con estado: $HTTPS_STATUS"
    fi
else
    warning "curl no está disponible, saltando verificación HTTP"
fi
echo ""

# 4. Verificar DNS (si se usa dominio)
if [[ "$SERVER_IP" =~ ^[a-zA-Z] ]]; then
    log "4. Verificando resolución DNS para $SERVER_IP..."
    if command -v nslookup &> /dev/null; then
        RESOLVED_IP=$(nslookup "$SERVER_IP" | grep "Address:" | tail -1 | awk '{print $2}')
        if [ -n "$RESOLVED_IP" ]; then
            echo "✅ Dominio resuelve a: $RESOLVED_IP"
        else
            error "❌ No se pudo resolver el dominio"
        fi
    elif command -v dig &> /dev/null; then
        RESOLVED_IP=$(dig +short "$SERVER_IP" | tail -1)
        if [ -n "$RESOLVED_IP" ]; then
            echo "✅ Dominio resuelve a: $RESOLVED_IP"
        else
            error "❌ No se pudo resolver el dominio"
        fi
    else
        warning "nslookup y dig no están disponibles"
    fi
    echo ""
fi

# 5. Prueba con navegador
log "5. Instrucciones para probar en navegador:"
echo "----------------------------------------"
echo "Abre tu navegador web e intenta acceder a:"
echo "🌐 http://$SERVER_IP:$PGADMIN_PORT"
echo ""
echo "Si no funciona, también prueba:"
echo "🔒 https://$SERVER_IP:$PGADMIN_PORT"
echo ""

# 6. Sugerencias de troubleshooting
log "6. POSIBLES PROBLEMAS Y SOLUCIONES:"
echo "----------------------------------------"
echo ""
echo "📋 Si el puerto está cerrado:"
echo "   • Verificar que el contenedor esté ejecutándose en el servidor"
echo "   • Revisar reglas de firewall (iptables, ufw, firewalld)"
echo "   • Verificar que el puerto esté mapeado correctamente en docker-compose.yml"
echo ""
echo "📋 Si conecta pero pgAdmin no carga:"
echo "   • Ejecutar en el servidor: ./debug-pgadmin.sh"
echo "   • Revisar logs: docker-compose logs pgadmin"
echo "   • Verificar permisos de directorios"
echo ""
echo "📋 Si aparece 'failed to load preferences':"
echo "   • Limpiar cookies del navegador para este sitio"
echo "   • Probar en modo incógnito/privado"
echo "   • Ejecutar en el servidor: ./fix-pgadmin.sh"
echo ""
echo "📋 Comandos para ejecutar en el servidor remoto:"
echo "   cd /ruta/al/proyecto/postgresql"
echo "   ./debug-pgadmin.sh      # Diagnóstico completo"
echo "   ./fix-pgadmin.sh        # Soluciones rápidas"
echo ""

log "Prueba de conectividad completada."
