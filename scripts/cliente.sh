#!/bin/bash
# =============================================================
# cliente.sh — Provisioning del Cliente VPN (WireGuard)
# =============================================================
# Este script configura la máquina cliente para conectarse
# al servidor VPN usando WireGuard.
# Las claves ya están pre-generadas en /vagrant/keys/
# La conexión NO se activa automáticamente al provisionar,
# se activa manualmente con: sudo wg-quick up wg0
# =============================================================

set -e

echo "============================================"
echo "  Configurando cliente VPN (WireGuard)"
echo "============================================"

# ---- 1. Actualizar e instalar dependencias ----
echo "[1/5] Instalando paquetes..."
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools net-tools \
  tcpdump curl wget

# ---- 2. Leer claves pre-generadas del repositorio ----
echo "[2/5] Cargando claves pre-generadas..."

CLIENT_PRIVATE_KEY=$(cat /vagrant/keys/client_private.key | tr -d '\n')
SERVER_PUBLIC_KEY=$(cat /vagrant/keys/server_public.key | tr -d '\n')

if [ -z "$CLIENT_PRIVATE_KEY" ] || [ -z "$SERVER_PUBLIC_KEY" ]; then
  echo "ERROR: No se encontraron las claves en /vagrant/keys/"
  echo "Asegúrate de que los archivos existan en la carpeta keys/"
  exit 1
fi

echo "  Claves del cliente cargadas correctamente."

# ---- 3. Obtener la IP del servidor VPN (interfaz NAT de Vagrant) ----
# En Vagrant, la VM server-vpn tiene NAT en eth0 (10.0.2.15 es la default)
# Pero para que el cliente se conecte, necesita la IP real de la VM server-vpn.
# Vagrant asigna la IP del host al gateway NAT, pero entre VMs usamos
# la IP de la red interna del host (forwarding de puerto o IP directa).
# 
# NOTA: En este setup, el cliente se conecta al server-vpn via la interfaz
# NAT de VirtualBox. La IP del server-vpn en la red NAT de Vagrant es 10.0.2.15
# pero eso aplica a AMBAS VMs. Usaremos la IP privada del servidor: 192.168.56.10
# que aunque normalmente no sería accesible, en el entorno Vagrant con VirtualBox
# el host puede rutear entre redes host-only.
#
# Para una demostración más realista, el servidor VPN expondría un puerto
# al host (port forwarding), y el cliente se conectaría via 127.0.0.1:<puerto>.
# Esa configuración queda documentada en config/notas_red.md

SERVER_VPN_IP="10.10.10.10"

# ---- 4. Crear configuración WireGuard del cliente ----
echo "[4/5] Creando configuración WireGuard del cliente..."

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
# IP del cliente dentro del túnel VPN
Address = 10.8.0.2/24

# Clave privada del cliente (pre-generada, no cambiar)
PrivateKey = ${CLIENT_PRIVATE_KEY}

# Servidor DNS (opcional, usa el del sistema si no se especifica)
# DNS = 8.8.8.8

# ---- Peer: server-vpn ----
[Peer]
# Clave pública del servidor VPN (pre-generada, no cambiar)
PublicKey = ${SERVER_PUBLIC_KEY}

# Endpoint: IP y puerto del servidor VPN
# En entorno Vagrant con VirtualBox: IP de la interfaz host-only del server-vpn
Endpoint = ${SERVER_VPN_IP}:51820

# Tráfico que va por el túnel:
# 10.8.0.0/24 = red VPN (comunicación con el servidor VPN)
# 192.168.56.0/24 = red interna (recursos internos via VPN)
# Para rutear TODO el tráfico por la VPN, cambiar a: 0.0.0.0/0
AllowedIPs = 10.8.0.0/24, 192.168.56.0/24

# Mantiene el túnel activo
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf

# ---- 5. Crear script de utilidad para el cliente ----
echo "[5/5] Creando scripts de utilidad..."

cat > /home/vagrant/conectar_vpn.sh << 'SCRIPT'
#!/bin/bash
echo "Activando conexión VPN..."
sudo wg-quick up wg0
echo ""
echo "Estado de la VPN:"
sudo wg show
echo ""
echo "Probando conectividad con server-vpn (10.8.0.1):"
ping -c 3 10.8.0.1
echo ""
echo "Probando acceso a server-interno (192.168.56.20):"
curl -s http://192.168.56.20 | grep -o '<title>.*</title>' || echo "No se pudo acceder (VPN no activa o error)"
SCRIPT

cat > /home/vagrant/desconectar_vpn.sh << 'SCRIPT'
#!/bin/bash
echo "Desactivando conexión VPN..."
sudo wg-quick down wg0
echo "VPN desconectada."
SCRIPT

chmod +x /home/vagrant/conectar_vpn.sh
chmod +x /home/vagrant/desconectar_vpn.sh
chown vagrant:vagrant /home/vagrant/conectar_vpn.sh
chown vagrant:vagrant /home/vagrant/desconectar_vpn.sh

echo ""
echo "============================================"
echo "  cliente configurado correctamente"
echo "============================================"
echo "  IP (sin VPN)  : Solo NAT (10.0.2.x)"
echo "  IP (con VPN)  : 10.8.0.2"
echo "  Servidor VPN  : 192.168.56.10:51820"
echo ""
echo "  Para conectar la VPN:"
echo "    vagrant ssh cliente"
echo "    sudo wg-quick up wg0"
echo "    (o usar: ./conectar_vpn.sh)"
echo "============================================"