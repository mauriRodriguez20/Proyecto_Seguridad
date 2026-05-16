#!/bin/bash
# =============================================================
# setup_logs.sh — Sistema de logs para el servidor VPN (WireGuard)
# Proyecto Final - Seguridad Informática
# Universidad Autónoma de Occidente
#
# Registra:
#   - Conexiones exitosas (peer conectado, handshake completado)
#   - Desconexiones (peer sin actividad reciente)
#   - Intentos fallidos (paquetes rechazados por iptables)
#   - Transferencia de datos por peer
# =============================================================

set -e

echo "============================================="
echo " Configurando sistema de logs VPN"
echo "============================================="

LOG_DIR="/var/log/vpn"
mkdir -p "$LOG_DIR"

# -------------------------------------------------------
# 1. Instalar dependencias
# -------------------------------------------------------
echo "[1/5] Instalando dependencias..."
apt-get install -y iptables-persistent rsyslog -qq

# -------------------------------------------------------
# 2. Crear script de monitoreo de peers WireGuard
#    Detecta conexiones y desconexiones comparando handshakes
# -------------------------------------------------------
echo "[2/5] Creando script monitor de peers..."

cat > /usr/local/bin/wg_monitor.sh <<'MONITOR'
#!/bin/bash
# ================================================================
# wg_monitor.sh — Monitor de conexiones WireGuard
# Ejecutado periódicamente por systemd timer
# ================================================================

LOG_FILE="/var/log/vpn/conexiones.log"
STATE_DIR="/var/run/wg_monitor"
INTERFACE="wg0"
# Tiempo máximo sin handshake para considerar desconexión (segundos)
TIMEOUT_SEGUNDOS=180

mkdir -p "$STATE_DIR"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    echo "$(timestamp) $1" | tee -a "$LOG_FILE"
}

# Mapa de peers conocidos (clave pública → nombre legible)
# Ajustar con las claves reales del proyecto
declare -A PEER_NOMBRES
if [ -f /etc/wg_peers.conf ]; then
    while IFS='=' read -r clave nombre; do
        PEER_NOMBRES["$clave"]="$nombre"
    done < /etc/wg_peers.conf
fi

nombre_peer() {
    local pub_key="$1"
    local short_key="${pub_key:0:8}..."
    echo "${PEER_NOMBRES[$pub_key]:-Peer($short_key)}"
}

# Obtener estado actual de todos los peers
wg show "$INTERFACE" peers 2>/dev/null | while read -r PEER_KEY; do

    NOMBRE=$(nombre_peer "$PEER_KEY")
    HANDSHAKE=$(wg show "$INTERFACE" latest-handshakes 2>/dev/null | grep "$PEER_KEY" | awk '{print $2}')
    ENDPOINT=$(wg show "$INTERFACE" endpoints 2>/dev/null | grep "$PEER_KEY" | awk '{print $2}')
    TRANSFER=$(wg show "$INTERFACE" transfer 2>/dev/null | grep "$PEER_KEY" | awk '{print "RX="$2"B TX="$3"B"}')

    STATE_FILE="$STATE_DIR/${PEER_KEY:0:16}"
    NOW=$(date +%s)

    if [ -z "$HANDSHAKE" ] || [ "$HANDSHAKE" -eq 0 ]; then
        # Peer registrado pero nunca ha hecho handshake
        if [ ! -f "${STATE_FILE}.connected" ]; then
            log "INFO  | $NOMBRE | Estado: ESPERANDO HANDSHAKE | Endpoint: ${ENDPOINT:-desconocido}"
        fi
        continue
    fi

    SEGUNDOS_DESDE_HANDSHAKE=$(( NOW - HANDSHAKE ))

    if [ "$SEGUNDOS_DESDE_HANDSHAKE" -le "$TIMEOUT_SEGUNDOS" ]; then
        # Peer activo (handshake reciente)
        if [ ! -f "${STATE_FILE}.connected" ]; then
            # Transición: desconectado → conectado
            log "CONN  | $NOMBRE | CONECTADO | Endpoint: ${ENDPOINT:-desconocido} | $TRANSFER"
            touch "${STATE_FILE}.connected"
            rm -f "${STATE_FILE}.disconnected"
        fi
        # Actualizar log de actividad cada vez que está conectado
        log "DATA  | $NOMBRE | Activo | Ultimo handshake: hace ${SEGUNDOS_DESDE_HANDSHAKE}s | $TRANSFER"
    else
        # Peer inactivo (sin handshake reciente)
        if [ -f "${STATE_FILE}.connected" ]; then
            # Transición: conectado → desconectado
            log "DISC  | $NOMBRE | DESCONECTADO | Ultimo handshake: hace ${SEGUNDOS_DESDE_HANDSHAKE}s | $TRANSFER"
            rm -f "${STATE_FILE}.connected"
            touch "${STATE_FILE}.disconnected"
        fi
    fi
done
MONITOR

chmod +x /usr/local/bin/wg_monitor.sh

# -------------------------------------------------------
# 3. Crear archivo de mapeo de peers a nombres legibles
#    (se genera automáticamente desde la config de WireGuard)
# -------------------------------------------------------
echo "[3/5] Generando mapeo de peers conocidos..."

cat > /etc/wg_peers.conf <<'PEERS'
# Formato: CLAVE_PUBLICA=NOMBRE_LEGIBLE
# Agregar aquí las claves públicas de los peers del proyecto
# Ejemplo (reemplazar con claves reales de keys/):
# abc123defg456...=cliente-01
# xyz789uvw012...=cliente-admin
PEERS

# Si ya existe wg0, extraer peers reales automáticamente
if command -v wg &>/dev/null && wg show wg0 &>/dev/null 2>&1; then
    wg show wg0 peers | while IFS= read -r key; do
        short="${key:0:8}"
        grep -q "^$key=" /etc/wg_peers.conf 2>/dev/null || \
            echo "${key}=peer-${short}" >> /etc/wg_peers.conf
    done
fi

# -------------------------------------------------------
# 4. Configurar iptables para registrar paquetes rechazados
#    (intentos de acceso sin VPN / fuera de política)
# -------------------------------------------------------
echo "[4/5] Configurando iptables para log de intentos fallidos..."

# Log de paquetes rechazados hacia la red interna sin VPN
# (tráfico directo a 192.168.56.0/24 que no viene del túnel wg0)

# Eliminar reglas previas del proyecto si existen
iptables -D FORWARD -s 10.10.10.0/24 -d 192.168.56.0/24 \
    -m state --state NEW -j LOG 2>/dev/null || true
iptables -D FORWARD -s 10.10.10.0/24 -d 192.168.56.0/24 \
    -j DROP 2>/dev/null || true

# Agregar reglas de logging ANTES del DROP
iptables -I FORWARD 1 \
    -s 10.10.10.0/24 \
    -d 192.168.56.0/24 \
    -m state --state NEW \
    -j LOG \
    --log-prefix "[VPN-INTENTO-BLOQUEADO] " \
    --log-level 4

# Guardar reglas
iptables-save > /etc/iptables/rules.v4

# Configurar rsyslog para capturar los logs de iptables en archivo separado
cat > /etc/rsyslog.d/30-vpn-firewall.conf <<'RSYSLOG'
# Capturar logs de iptables marcados con [VPN-INTENTO-BLOQUEADO]
:msg, contains, "VPN-INTENTO-BLOQUEADO" /var/log/vpn/intentos_fallidos.log
& stop
RSYSLOG

systemctl restart rsyslog

# -------------------------------------------------------
# 5. Configurar systemd timer para ejecutar el monitor
#    cada 60 segundos
# -------------------------------------------------------
echo "[5/5] Configurando systemd timer para monitor continuo..."

# Servicio
cat > /etc/systemd/system/wg-monitor.service <<'SERVICE'
[Unit]
Description=Monitor de conexiones WireGuard VPN
After=network.target wg-quick@wg0.service
Requires=wg-quick@wg0.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/wg_monitor.sh
StandardOutput=journal
StandardError=journal
SERVICE

# Timer (cada 60 segundos)
cat > /etc/systemd/system/wg-monitor.timer <<'TIMER'
[Unit]
Description=Ejecutar monitor VPN cada 60 segundos
After=wg-quick@wg0.service

[Timer]
OnBootSec=30
OnUnitActiveSec=60
Unit=wg-monitor.service

[Install]
WantedBy=multi-user.target
TIMER

systemctl daemon-reload
systemctl enable wg-monitor.timer
systemctl start wg-monitor.timer || true

# -------------------------------------------------------
# 6. Script de utilidad: consultar logs fácilmente
# -------------------------------------------------------
cat > /usr/local/bin/vpn_logs <<'VPNLOGS'
#!/bin/bash
# Utilidad para consultar los logs VPN
# Uso: vpn_logs [conexiones|fallidos|todo|resumen]

LOG_DIR="/var/log/vpn"
MODO="${1:-resumen}"

case "$MODO" in
    conexiones)
        echo "=== Conexiones y desconexiones VPN ==="
        grep -E "^.*(CONN|DISC).*" "$LOG_DIR/conexiones.log" 2>/dev/null | tail -50
        ;;
    actividad)
        echo "=== Actividad reciente de peers ==="
        grep "DATA" "$LOG_DIR/conexiones.log" 2>/dev/null | tail -30
        ;;
    fallidos)
        echo "=== Intentos de acceso bloqueados ==="
        cat "$LOG_DIR/intentos_fallidos.log" 2>/dev/null | tail -50
        ;;
    todo)
        echo "=== Log completo ==="
        cat "$LOG_DIR/conexiones.log" 2>/dev/null | tail -100
        ;;
    resumen)
        echo "============================================="
        echo "  RESUMEN SISTEMA DE LOGS VPN"
        echo "============================================="
        echo ""
        echo "--- Peers conectados ahora ---"
        wg show wg0 2>/dev/null || echo "  WireGuard no activo"
        echo ""
        echo "--- Últimas 10 conexiones/desconexiones ---"
        grep -E "CONN|DISC" "$LOG_DIR/conexiones.log" 2>/dev/null | tail -10 \
            || echo "  Sin registros aún"
        echo ""
        echo "--- Últimos 5 intentos bloqueados ---"
        tail -5 "$LOG_DIR/intentos_fallidos.log" 2>/dev/null \
            || echo "  Sin intentos bloqueados registrados"
        echo ""
        echo "--- Archivos de log ---"
        ls -lh "$LOG_DIR/" 2>/dev/null
        echo "============================================="
        ;;
    *)
        echo "Uso: vpn_logs [conexiones|actividad|fallidos|todo|resumen]"
        ;;
esac
VPNLOGS

chmod +x /usr/local/bin/vpn_logs

# -------------------------------------------------------
# 7. Configurar logrotate para los logs VPN
# -------------------------------------------------------
cat > /etc/logrotate.d/vpn <<'LOGROTATE'
/var/log/vpn/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 root adm
    dateext
    postrotate
        systemctl restart rsyslog >/dev/null 2>&1 || true
    endscript
}
LOGROTATE

echo ""
echo "============================================="
echo " Sistema de logs configurado correctamente"
echo "============================================="
echo ""
echo " Archivos de log:"
echo "   /var/log/vpn/conexiones.log      → conexiones y desconexiones"
echo "   /var/log/vpn/intentos_fallidos.log → accesos bloqueados"
echo ""
echo " Comandos de consulta:"
echo "   vpn_logs resumen     → estado general"
echo "   vpn_logs conexiones  → solo CONN / DISC"
echo "   vpn_logs fallidos    → intentos bloqueados"
echo "   vpn_logs actividad   → tráfico por peer"
echo "   vpn_logs todo        → log completo"
echo ""
echo " Timer activo: wg-monitor.timer (cada 60 segundos)"
echo "   systemctl status wg-monitor.timer"
echo "============================================="
