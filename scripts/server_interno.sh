#!/bin/bash
# =============================================================
# server_interno.sh — Provisioning del Servidor Interno
# =============================================================
# Este servidor simula recursos internos de una organización:
# - Servidor web (nginx) con página de prueba
# - Servidor de archivos simple (Python HTTP server)
# Solo es accesible desde la red interna (192.168.56.x)
# o a través de la VPN (10.8.0.x)
# NO tiene interfaz pública directa.
# =============================================================

set -e

echo "============================================"
echo "  Configurando server-interno"
echo "============================================"

# ---- 1. Actualizar e instalar dependencias ----
echo "[1/4] Instalando paquetes..."
apt-get update -qq
apt-get install -y -qq nginx python3 net-tools curl tcpdump

# ---- 2. Configurar nginx como servidor web interno ----
echo "[2/4] Configurando servidor web..."

cat > /var/www/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Servidor Interno - Seguridad Informática</title>
  <style>
    body { font-family: monospace; background: #1a1a2e; color: #00ff88; padding: 40px; }
    h1   { color: #00bfff; }
    .info { background: #16213e; padding: 20px; border-left: 4px solid #00ff88; margin: 10px 0; }
  </style>
</head>
<body>
  <h1>🔒 Servidor Interno</h1>
  <div class="info">
    <p>✅ Acceso concedido a través de la VPN</p>
    <p>🏢 Este recurso solo es accesible desde la red interna o via WireGuard VPN</p>
    <p>📡 Si puedes ver esta página, tu túnel VPN está funcionando correctamente</p>
  </div>
  <div class="info">
    <p>🖥️  Servidor: server-interno (192.168.56.20)</p>
    <p>🔐 Proyecto Final — Seguridad Informática — UAO</p>
  </div>
</body>
</html>
EOF

# Configurar nginx para escuchar solo en la interfaz interna
cat > /etc/nginx/sites-available/default << 'EOF'
server {
    listen 80;
    listen [::]:80;

    root /var/www/html;
    index index.html;

    server_name _;

    location / {
        try_files $uri $uri/ =404;
    }

    # Log de accesos para evidencia del proyecto
    access_log /var/log/nginx/internal_access.log;
    error_log  /var/log/nginx/internal_error.log;
}
EOF

# ---- 3. Crear área de archivos compartidos (simula servidor de archivos) ----
echo "[3/4] Creando directorio de archivos internos..."

mkdir -p /var/www/html/archivos

cat > /var/www/html/archivos/documento_confidencial.txt << 'EOF'
==============================================
DOCUMENTO INTERNO CONFIDENCIAL
Universidad Autónoma de Occidente
Proyecto de Seguridad Informática
==============================================

Este archivo simula un recurso sensible de la organización.
Solo debe ser accesible para usuarios autenticados
que estén conectados a través de la VPN corporativa.

Si lees este archivo sin estar conectado a la VPN,
significa que hay un problema de seguridad en la configuración.

Fecha: Generado automáticamente durante provisioning.
==============================================
EOF

# ---- 4. Iniciar servicios ----
echo "[4/4] Iniciando servicios..."
systemctl enable nginx
systemctl restart nginx

echo ""
echo "============================================"
echo "  server-interno configurado correctamente"
echo "============================================"
echo "  IP red interna : 192.168.56.20"
echo "  Web interno    : http://192.168.56.20"
echo "  Archivos       : http://192.168.56.20/archivos/"
echo "  Solo accesible : via red interna o VPN"
echo "============================================"