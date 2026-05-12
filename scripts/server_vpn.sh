#!/bin/bash
# =============================================================
# server_vpn.sh — Provisioning del Servidor VPN (WireGuard)
# =============================================================
# Este script se ejecuta UNA sola vez cuando se hace vagrant up.
# Las claves ya están pre-generadas en /vagrant/keys/
# NO se generan claves nuevas en cada ejecución.
# =============================================================

set -e  # Detener si ocurre algún error

echo "============================================"
echo "  Configurando server-vpn con WireGuard"
echo "============================================"

# ---- 1. Actualizar e instalar dependencias ----
echo "[1/6] Instalando paquetes..."
apt-get update -qq
apt-get install -y -qq wireguard wireguard-tools iptables net-tools \
  tcpdump wireshark-common curl wget

# ---- 2. Leer claves pre-generadas del repositorio ----
echo "[2/6] Cargando claves pre-generadas..."

SERVER_PRIVATE_KEY=$(cat /vagrant/keys/server_private.key | tr -d '\n')
CLIENT_PUBLIC_KEY=$(cat /vagrant/keys/client_public.key | tr -d '\n')

if [ -z "$SERVER_PRIVATE_KEY" ] || [ -z "$CLIENT_PUBLIC_KEY" ]; then
  echo "ERROR: No se encontraron las claves en /vagrant/keys/"
  echo "Asegúrate de que los archivos existan en la carpeta keys/"
  exit 1
fi

echo "  Clave del servidor cargada correctamente."

# ---- 3. Habilitar IP forwarding (necesario para ruteo VPN) ----
echo "[3/6] Habilitando IP forwarding..."
echo "net.ipv4.ip_forward=1" > /etc/sysctl.d/99-wireguard.conf
sysctl -p /etc/sysctl.d/99-wireguard.conf

# ---- 4. Crear configuración de WireGuard ----
echo "[4/6] Creando configuración WireGuard..."

mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
# Dirección IP del servidor dentro del túnel VPN
Address = 10.8.0.1/24

# Puerto en el que escucha el servidor VPN
ListenPort = 51820

# Clave privada del servidor (pre-generada, no cambiar)
PrivateKey = ${SERVER_PRIVATE_KEY}

# Reglas de firewall: permitir tráfico desde/hacia la VPN
# y hacer NAT para que clientes VPN accedan a la red interna
PostUp   = iptables -A FORWARD -i wg0 -j ACCEPT; \
           iptables -A FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -A POSTROUTING -o enp0s8 -j MASQUERADE; \
           iptables -t nat -A POSTROUTING -o enp0s9 -j MASQUERADE

PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; \
           iptables -D FORWARD -o wg0 -j ACCEPT; \
           iptables -t nat -D POSTROUTING -o enp0s8 -j MASQUERADE; \
           iptables -t nat -D POSTROUTING -o enp0s9 -j MASQUERADE

# ---- Peer: cliente ----
[Peer]
# Clave pública del cliente (pre-generada, no cambiar)
PublicKey = ${CLIENT_PUBLIC_KEY}

# IP que tendrá el cliente dentro del túnel VPN
AllowedIPs = 10.8.0.2/32

# PersistentKeepalive mantiene el túnel activo
PersistentKeepalive = 25
EOF

chmod 600 /etc/wireguard/wg0.conf

# ---- 5. Habilitar e iniciar WireGuard ----
echo "[5/6] Iniciando WireGuard..."
systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# ---- 6. Verificar que el servicio esté activo ----
echo "[6/6] Verificando estado..."
sleep 2

if systemctl is-active --quiet wg-quick@wg0; then
  echo ""
  echo "============================================"
  echo "  server-vpn configurado correctamente"
  echo "============================================"
  echo "  Interfaz VPN : wg0"
  echo "  IP VPN       : 10.8.0.1"
  echo "  Puerto       : 51820/UDP"
  echo "  Red interna  : 192.168.56.10"
  echo "============================================"
  wg show wg0
else
  echo "ERROR: WireGuard no pudo iniciar."
  journalctl -u wg-quick@wg0 --no-pager -n 20
  exit 1
fi