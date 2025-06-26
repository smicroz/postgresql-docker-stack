# EJEMPLOS DE USO - PostgreSQL Docker

## Configuración inicial completa

```bash
# 1. Clonar/descargar el proyecto
cd postgresql

# 2. Configurar variables de entorno
cp .env.example .env
nano .env  # Editar con tus credenciales

# 3. Inicio rápido (detecta automáticamente si hay hardening)
./quick-start.sh

# 4. Si tienes hardening aplicado y necesitas configurar manualmente
sudo ./configure-post-hardening.sh
```

## Uso diario

### Comandos básicos
```bash
# Ver estado
./maintenance.sh status

# Ver logs en tiempo real
./maintenance.sh logs

# Reiniciar servicios
./maintenance.sh restart

# Verificar salud del sistema
./maintenance.sh health
```

### Backups
```bash
# Backup automático diario (recomendado)
./backup.sh --all --compress

# Backup de emergencia
./maintenance.sh backup

# Backup con retención de 30 días
./backup.sh --all --retention 30
```

### Monitoreo
```bash
# Monitoreo en tiempo real
./maintenance.sh monitor

# Verificar seguridad
./maintenance.sh security

# Monitoreo del sistema (post-hardening)
sudo /usr/local/bin/postgresql-monitor.sh
```

## Conexiones a la base de datos

### Desde psql
```bash
# Conectar a PostgreSQL desde el host
psql -h localhost -p 5432 -U tu_usuario -d tu_base_datos

# Conectar desde dentro del contenedor
docker-compose exec postgres psql -U tu_usuario -d tu_base_datos
```

### Desde aplicaciones Python
```python
import psycopg2

conn = psycopg2.connect(
    host="localhost",
    port=5432,
    database="tu_base_datos",
    user="tu_usuario",
    password="tu_contraseña"
)
```

### String de conexión
```
postgresql://usuario:contraseña@localhost:5432/base_datos
```

## Configuración de pgAdmin

1. Acceder a http://localhost:5050
2. Usar las credenciales del archivo .env
3. Agregar servidor PostgreSQL:
   - Host: postgres (nombre del contenedor)
   - Puerto: 5432
   - Usuario/Contraseña: del archivo .env

## Mantenimiento programado

### Cron jobs recomendados
```bash
# Editar crontab
crontab -e

# Backup diario a las 2 AM
0 2 * * * cd /ruta/a/postgresql && ./backup.sh --all --compress

# Verificación de salud cada hora
0 * * * * cd /ruta/a/postgresql && ./maintenance.sh health >> /var/log/postgresql-health.log

# Mantenimiento de PostgreSQL semanal (domingos a las 3 AM)
0 3 * * 0 cd /ruta/a/postgresql && ./maintenance.sh maintenance
```

## Troubleshooting común

### No puedo conectarme después del hardening
```bash
# Verificar reglas UFW
sudo ufw status | grep 5432

# Si no hay reglas, ejecutar post-hardening
sudo ./configure-post-hardening.sh

# Verificar que los contenedores estén corriendo
./maintenance.sh status
```

### pgAdmin no carga
```bash
# Verificar logs de pgAdmin
./maintenance.sh logs pgadmin

# Verificar puerto UFW
sudo ufw status | grep 5050

# Reiniciar pgAdmin
docker-compose restart pgadmin
```

### Error de autenticación
```bash
# Verificar variables de entorno
cat .env

# Reiniciar PostgreSQL
docker-compose restart postgres

# Verificar logs
./maintenance.sh logs postgres
```

### Espacio en disco lleno
```bash
# Limpiar logs antiguos
./maintenance.sh cleanup

# Limpiar backups antiguos
find ./backups -name "*.sql*" -mtime +7 -delete

# Ver uso de espacio
du -sh ./backups
```

## Configuraciones avanzadas

### Optimización de PostgreSQL
Agregar a `init-scripts/01-optimizations.sql`:
```sql
-- Configuraciones de rendimiento
ALTER SYSTEM SET shared_buffers = '256MB';
ALTER SYSTEM SET work_mem = '4MB';
ALTER SYSTEM SET maintenance_work_mem = '64MB';
ALTER SYSTEM SET checkpoint_completion_target = 0.9;
SELECT pg_reload_conf();
```

### Scripts de inicialización personalizados
```sql
-- init-scripts/02-users.sql
CREATE USER app_user WITH PASSWORD 'app_password';
CREATE DATABASE app_db OWNER app_user;
GRANT ALL PRIVILEGES ON DATABASE app_db TO app_user;
```

### Configuración de SSL (producción)
```bash
# Generar certificados SSL
openssl req -new -x509 -days 365 -nodes -text -out server.crt -keyout server.key -subj "/CN=localhost"

# Mover a volumen PostgreSQL
# (configuración adicional requerida en postgresql.conf)
```

## Scripts de desarrollo útiles

### Script de reset completo
```bash
#!/bin/bash
# reset-dev.sh
echo "⚠️  RESET COMPLETO - SE PERDERÁN TODOS LOS DATOS"
read -p "¿Continuar? [y/N]: " confirm
if [[ $confirm =~ ^[Yy]$ ]]; then
    docker-compose down -v
    docker-compose up -d
    echo "✅ Reset completado"
fi
```

### Script de carga de datos de prueba
```bash
#!/bin/bash
# load-test-data.sh
echo "Cargando datos de prueba..."
docker-compose exec postgres psql -U $POSTGRES_USER -d $POSTGRES_DB << 'EOF'
CREATE TABLE IF NOT EXISTS test_table (
    id SERIAL PRIMARY KEY,
    name VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO test_table (name) VALUES 
    ('Test 1'),
    ('Test 2'),
    ('Test 3');
    
SELECT * FROM test_table;
EOF
echo "✅ Datos de prueba cargados"
```
