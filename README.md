# Proyecto Final — Seguridad Informática
**Universidad Autónoma de Occidente — Cali, Colombia**

Implementación de una VPN con WireGuard usando Vagrant + VirtualBox.

---

## Requisitos

- [Vagrant] Instalado
- [VirtualBox] Instalado

---

## Topología de red

```
[cliente]                    [server-vpn]                  [server-interno]
10.10.10.20 ──(internet)──▶  10.10.10.10 ──(red interna)──▶ 192.168.56.20
10.8.0.2 (túnel VPN)         10.8.0.1    (túnel VPN)        (solo via VPN)
                             192.168.56.10
```

| VM | IP externa | IP interna | IP VPN | Rol |
|----|-----------|------------|--------|-----|
| server-vpn | 10.10.10.10 | 192.168.56.10 | 10.8.0.1 | Gateway WireGuard |
| server-interno | — | 192.168.56.20 | — | Recursos internos |
| cliente | 10.10.10.20 | — | 10.8.0.2 | Usuario remoto |

---

## Levantar el proyecto por primera vez

```bash
git clone https://github.com/mauriRodriguez20/Proyecto_Seguridad.git
cd Proyecto_Seguridad
```

Levantar las VMs **una por una** en este orden para que el provisioning corra correctamente:

```bash
vagrant up server-vpn --provision
```

Esperar que termine completamente y que aparezca `server-vpn configurado correctamente`. Luego:

```bash
vagrant up server-interno --provision
```

Esperar que aparezca `server-interno configurado correctamente`. Luego:

```bash
vagrant up cliente --provision
```

Esperar que aparezca `cliente configurado correctamente`.

Verificar que las 3 estén corriendo:

```bash
vagrant status
```

Deben aparecer las 3 en estado `running`.

> ⚠️ La primera vez tarda bastante porque descarga la box de Ubuntu 22.04
> y instala todos los paquetes. **No interrumpir el proceso** — si se interrumpe,
> dpkg puede quedar corrupto y hay que repararlo manualmente entrando por ssh a la vm afectada y
> ejecutar  `sudo dpkg --configure -a`.

---

## Apagar y volver a levantar (segunda vez en adelante)

**Apagar:**
```bash
vagrant halt
```

**Volver a levantar** (no re-ejecuta los scripts, arranca las VMs tal cual):
```bash
vagrant up
```



---

## Pruebas del túnel VPN

### 1. Verificar que el servidor VPN está activo

```bash
vagrant ssh server-vpn
sudo wg show
```

Debe mostrar la interfaz `wg0`, el puerto `51820` y el peer (cliente) registrado.

```bash
exit
```

---

### 2. Probar que SIN VPN no hay acceso al servidor interno

```bash
vagrant ssh cliente
curl --connect-timeout 5 http://192.168.56.20
```

**Resultado esperado:** `Connection timeout` — el servidor interno es invisible desde fuera.

---

### 3. Activar la VPN y verificar el túnel

```bash
sudo wg-quick up wg0
sudo wg show
```

Debe mostrar el peer con `latest handshake` reciente y bytes transferidos.

---

### 4. Verificar conectividad con el servidor VPN por el túnel

```bash
ping -c 4 10.8.0.1
```

**Resultado esperado:** 4 paquetes enviados, 0% packet loss.

---

### 5. Acceder al servidor interno a través de la VPN

```bash
curl http://192.168.56.20
```

**Resultado esperado:** HTML del servidor interno con el mensaje
`"Acceso concedido a través de la VPN"`.

---

### 6. Capturar tráfico cifrado con tcpdump

Abrir una segunda terminal y entrar al server-vpn:

```bash
vagrant ssh server-vpn
sudo tcpdump -i enp0s8 -n port 51820
```

Desde el cliente (primera terminal) genera tráfico:

```bash
curl http://192.168.56.20
```

**Resultado esperado:** En el server-vpn se verán paquetes UDP en el puerto 51820.
El contenido es ilegible — está cifrado por WireGuard. Nadie puede interceptar los datos.

---

### 7. Desactivar la VPN y confirmar que se pierde el acceso

```bash
sudo wg-quick down wg0
curl --connect-timeout 5 http://192.168.56.20
```

**Resultado esperado:** `Connection timeout` de nuevo — sin VPN, sin acceso.

---

## Nota sobre las claves

Las claves WireGuard están pre-generadas en `keys/` y versionadas en el repo.
Esto garantiza que todos los miembros del equipo usen exactamente las mismas claves
y el túnel funcione sin reconfiguración.

> ⚠️ Esto es válido solo para entornos de laboratorio académico.
> En producción, las claves privadas **nunca** se versionan en un repositorio.