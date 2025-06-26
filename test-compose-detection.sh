#!/bin/bash

# Script de prueba para verificar la detección de Docker Compose

# Variable global para comando de Docker Compose
COMPOSE_CMD=""

# Verificar Docker Compose (nuevo comando integrado o legacy standalone)
if docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
    echo "✓ Docker Compose integrado detectado"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
    echo "✓ Docker Compose standalone detectado"
    echo "⚠️ Se recomienda usar 'docker compose' en lugar de 'docker-compose'"
else
    echo "✗ Docker Compose no está instalado"
    exit 1
fi

echo "Comando a usar: $COMPOSE_CMD"
echo "Versión: $($COMPOSE_CMD version)"
