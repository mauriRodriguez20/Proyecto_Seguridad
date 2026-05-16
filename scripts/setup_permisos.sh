#!/bin/bash
# =============================================================
# setup_permisos.sh — Permisos por usuario/grupo en server-interno
# Proyecto Final - Seguridad Informática
# Universidad Autónoma de Occidente
#
# Política de acceso:
#   grupo vpn_admin  → acceso total a /srv/datos/admin y /srv/datos/compartido
#   grupo vpn_users  → acceso solo a /srv/datos/compartido (lectura/escritura)
#   sin grupo        → sin acceso a ningún recurso interno
# =============================================================

set -e

echo "============================================="
echo " Configurando permisos por usuario/grupo"
echo "============================================="

# -------------------------------------------------------
# 1. Crear grupos de acceso VPN
# -------------------------------------------------------
echo "[1/5] Creando grupos vpn_admin y vpn_users..."

groupadd --system vpn_admin 2>/dev/null || echo "  Grupo vpn_admin ya existe"
groupadd --system vpn_users 2>/dev/null || echo "  Grupo vpn_users ya existe"

# -------------------------------------------------------
# 2. Crear usuarios de prueba
# -------------------------------------------------------
echo "[2/5] Creando usuarios de prueba..."

# Usuario administrador
if ! id "admin_vpn" &>/dev/null; then
    useradd -m -s /bin/bash -G vpn_admin,vpn_users admin_vpn
    echo "admin_vpn:Admin1234!" | chpasswd
    echo "  Usuario admin_vpn creado"
else
    echo "  Usuario admin_vpn ya existe"
fi

# Usuario normal
if ! id "user_vpn" &>/dev/null; then
    useradd -m -s /bin/bash -G vpn_users user_vpn
    echo "user_vpn:User1234!" | chpasswd
    echo "  Usuario user_vpn creado"
else
    echo "  Usuario user_vpn ya existe"
fi

# Usuario sin permisos (para demostrar denegación)
if ! id "invitado_vpn" &>/dev/null; then
    useradd -m -s /bin/bash invitado_vpn
    echo "invitado_vpn:Guest1234!" | chpasswd
    echo "  Usuario invitado_vpn creado (sin grupos VPN)"
else
    echo "  Usuario invitado_vpn ya existe"
fi

# -------------------------------------------------------
# 3. Crear estructura de directorios de recursos internos
# -------------------------------------------------------
echo "[3/5] Creando estructura de directorios internos..."

mkdir -p /srv/datos/admin
mkdir -p /srv/datos/compartido
mkdir -p /srv/datos/publico

# Contenido de prueba
cat > /srv/datos/admin/secreto.txt <<EOF
=== RECURSO CONFIDENCIAL - SOLO ADMINISTRADORES ===
Credenciales de base de datos interna:
  Host: 192.168.56.20
  DB:   bd_produccion
  User: dbadmin
  Pass: [solo para personal autorizado]

Este archivo solo debe ser accesible por el grupo vpn_admin.
EOF

cat > /srv/datos/compartido/informe.txt <<EOF
=== RECURSO COMPARTIDO - USUARIOS VPN ===
Informe mensual de actividad - $(date +%B/%Y)

Este archivo es accesible para todos los usuarios con acceso VPN
(grupos vpn_admin y vpn_users).
EOF

cat > /srv/datos/publico/bienvenida.txt <<EOF
=== RECURSO PÚBLICO ===
Bienvenido al servidor interno.
Para acceder a recursos adicionales necesitas credenciales VPN válidas.
EOF

# -------------------------------------------------------
# 4. Aplicar permisos y propietarios
# -------------------------------------------------------
echo "[4/5] Aplicando permisos a directorios y archivos..."

# /srv/datos/admin → solo vpn_admin (modo 750: rwxr-x---)
chown -R root:vpn_admin /srv/datos/admin
chmod 750 /srv/datos/admin
chmod 640 /srv/datos/admin/*
echo "  /srv/datos/admin  → grupo vpn_admin (rwx r-x ---)"

# /srv/datos/compartido → vpn_users (incluyendo admins) (modo 770: rwxrwx---)
chown -R root:vpn_users /srv/datos/compartido
chmod 770 /srv/datos/compartido
chmod 660 /srv/datos/compartido/*
echo "  /srv/datos/compartido → grupo vpn_users (rwx rwx ---)"

# /srv/datos/publico → todos pueden leer (modo 755)
chown -R root:root /srv/datos/publico
chmod 755 /srv/datos/publico
chmod 644 /srv/datos/publico/*
echo "  /srv/datos/publico → lectura pública (rwx r-x r-x)"

# -------------------------------------------------------
# 5. Configurar nginx para servir recursos con autenticación HTTP básica
#    (simula un servidor de archivos web interno con control de acceso)
# -------------------------------------------------------
echo "[5/5] Configurando servidor web con autenticación por grupo..."

apt-get install -y nginx apache2-utils -qq

# Crear archivo de contraseñas para autenticación HTTP básica
# Grupo admin
htpasswd -cb /etc/nginx/.htpasswd_admin admin_vpn Admin1234!

# Grupo users (acceso compartido)
htpasswd -cb /etc/nginx/.htpasswd_users user_vpn User1234!
htpasswd -b  /etc/nginx/.htpasswd_users admin_vpn Admin1234!

chmod 640 /etc/nginx/.htpasswd_admin /etc/nginx/.htpasswd_users
chown root:www-data /etc/nginx/.htpasswd_admin /etc/nginx/.htpasswd_users

# Configuración nginx con zonas protegidas por grupo
cat > /etc/nginx/sites-available/servidor_interno <<'NGINX'
# ================================================================
# Servidor Interno - Control de acceso por zona
# ================================================================

server {
    listen 80;
    server_name servidor-interno;

    # Zona pública (sin autenticación)
    location /publico/ {
        alias /srv/datos/publico/;
        autoindex on;
        add_header X-Zona "publica" always;
    }

    # Zona compartida (requiere grupo vpn_users o vpn_admin)
    location /compartido/ {
        alias /srv/datos/compartido/;
        autoindex on;
        auth_basic           "Acceso VPN - Usuarios";
        auth_basic_user_file /etc/nginx/.htpasswd_users;
        add_header X-Zona "compartida" always;
    }

    # Zona admin (requiere grupo vpn_admin)
    location /admin/ {
        alias /srv/datos/admin/;
        autoindex on;
        auth_basic           "Acceso VPN - Solo Administradores";
        auth_basic_user_file /etc/nginx/.htpasswd_admin;
        add_header X-Zona "admin" always;
    }

    # Página de inicio informativa
    location / {
        return 200 '<html><body>
<h2>Servidor Interno - Universidad Autonoma de Occidente</h2>
<p>Zonas disponibles:</p>
<ul>
  <li><a href="/publico/">/publico/</a> - Sin autenticacion</li>
  <li><a href="/compartido/">/compartido/</a> - Usuarios VPN (vpn_users)</li>
  <li><a href="/admin/">/admin/</a> - Solo administradores (vpn_admin)</li>
</ul>
<p>Acceso concedido a traves de la VPN</p>
</body></html>';
        add_header Content-Type text/html;
    }

    # Registrar accesos en log separado
    access_log /var/log/nginx/servidor_interno_access.log;
    error_log  /var/log/nginx/servidor_interno_error.log;
}
NGINX

# Activar sitio
ln -sf /etc/nginx/sites-available/servidor_interno /etc/nginx/sites-enabled/servidor_interno
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx
systemctl enable nginx

echo ""
echo "============================================="
echo " Permisos configurados correctamente"
echo "============================================="
echo ""
echo " Usuarios creados:"
echo "   admin_vpn  / Admin1234!  → grupo vpn_admin + vpn_users"
echo "   user_vpn   / User1234!   → grupo vpn_users"
echo "   invitado_vpn / Guest1234! → sin grupos (acceso denegado)"
echo ""
echo " Recursos internos:"
echo "   http://192.168.56.20/publico/    → acceso libre"
echo "   http://192.168.56.20/compartido/ → requiere vpn_users"
echo "   http://192.168.56.20/admin/      → requiere vpn_admin"
echo ""
echo " Verificar permisos del sistema de archivos:"
echo "   ls -la /srv/datos/"
echo "============================================="
