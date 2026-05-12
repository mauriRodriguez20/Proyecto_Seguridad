# -*- mode: ruby -*-
# vi: set ft=ruby :

# =============================================================
# Proyecto Final - Seguridad Informática
# Universidad Autónoma de Occidente
# =============================================================
# Topología:
#
#   [cliente] ----(red-externa/internet simulado)----> [server-vpn] ----> [server-interno]
#   10.10.10.20                                        10.10.10.10        192.168.56.20
#   10.8.0.2 (WG, cuando conectado)                   192.168.56.10      (solo accesible
#                                                      10.8.0.1 (WG)      via VPN)
#
# Redes:
#   red-externa  (10.10.10.0/24) → simula internet entre cliente y server-vpn
#   red-interna  (192.168.56.0/24) → LAN privada entre server-vpn y server-interno
#   red-vpn      (10.8.0.0/24) → túnel WireGuard cifrado
# =============================================================

Vagrant.configure("2") do |config|

  config.vm.box = "ubuntu/jammy64"
  config.vm.box_check_update = false

  # -------------------------------------------------------
  # VM 1: server-vpn
  # -------------------------------------------------------
  config.vm.define "server-vpn" do |vpn|
    vpn.vm.hostname = "server-vpn"

    # Red externa: simula internet (conecta con el cliente)
    vpn.vm.network "private_network", ip: "10.10.10.10",
      virtualbox__intnet: "red-externa"

    # Red interna: conecta con server-interno
    vpn.vm.network "private_network", ip: "192.168.56.10",
      virtualbox__intnet: "red-interna"

    vpn.vm.provider "virtualbox" do |vb|
      vb.name   = "server-vpn"
      vb.memory = "1024"
      vb.cpus   = 1
    end

    vpn.vm.provision "shell", path: "scripts/server_vpn.sh"
  end

  # -------------------------------------------------------
  # VM 2: server-interno
  # -------------------------------------------------------
  config.vm.define "server-interno" do |interno|
    interno.vm.hostname = "server-interno"

    interno.vm.network "private_network", ip: "192.168.56.20",
      virtualbox__intnet: "red-interna"

    interno.vm.provider "virtualbox" do |vb|
      vb.name   = "server-interno"
      vb.memory = "512"
      vb.cpus   = 1
    end

    interno.vm.provision "shell", path: "scripts/server_interno.sh"
  end

  # -------------------------------------------------------
  # VM 3: cliente
  # -------------------------------------------------------
  config.vm.define "cliente" do |cli|
    cli.vm.hostname = "cliente"

    # Red externa: ve al server-vpn pero NO a la red interna directamente
    cli.vm.network "private_network", ip: "10.10.10.20",
      virtualbox__intnet: "red-externa"

    cli.vm.provider "virtualbox" do |vb|
      vb.name   = "cliente-vpn"
      vb.memory = "512"
      vb.cpus   = 1
    end

    cli.vm.provision "shell", path: "scripts/cliente.sh"
  end

end