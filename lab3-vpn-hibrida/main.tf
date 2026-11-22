# Lab 3: rede híbrida homelab <-> Azure com WireGuard numa NVA (Network Virtual Appliance)
terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "rg-tfstate"
    storage_account_name = "sttfstate63a9f3"
    container_name       = "tfstate"
    key                  = "lab3-vpn-hibrida.tfstate"
    use_azuread_auth     = true
  }
}

provider "azurerm" {
  features {}
  resource_provider_registrations = "none"
}

# ---------------- Variáveis ----------------

variable "meu_ip" {
  description = "IP público de casa (CIDR /32): origem do túnel e do SSH de administração"
  type        = string
}

variable "home_public_key" {
  description = "Chave PÚBLICA WireGuard do servidor de casa"
  type        = string
}

variable "home_cidr" {
  description = "Rede local de casa"
  type        = string
  default     = "192.168.1.0/24"
}

variable "tunnel_cidr" {
  description = "Rede do túnel WireGuard"
  type        = string
  default     = "10.99.0.0/24"
}

variable "tamanho" {
  type    = string
  default = "Standard_B2ats_v2"
}

variable "ssh_public_key" {
  description = "Chave SSH pública. Se vazio, usa ~/.ssh/id_ed25519.pub"
  type        = string
  default     = ""
}

locals {
  location       = "northcentralus"
  nva_ip_privado = "10.20.1.4"
  app_ip_privado = "10.20.2.4"
  ssh_public_key = coalesce(var.ssh_public_key, try(file(pathexpand("~/.ssh/id_ed25519.pub")), null))
}

# ---------------- Rede ----------------

resource "azurerm_resource_group" "lab" {
  name     = "rg-lab3"
  location = local.location
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-lab3"
  address_space       = ["10.20.0.0/16"]
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
}

resource "azurerm_subnet" "nva" {
  name                 = "snet-nva"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.20.1.0/24"]
}

resource "azurerm_subnet" "app" {
  name                 = "snet-app"
  resource_group_name  = azurerm_resource_group.lab.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = ["10.20.2.0/24"]
}

# ---------------- NVA (gateway VPN WireGuard) ----------------

resource "azurerm_network_security_group" "nva" {
  name                = "nsg-nva"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  security_rule {
    name                       = "wireguard-de-casa"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Udp"
    source_port_range          = "*"
    destination_port_range     = "51820"
    source_address_prefix      = var.meu_ip
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "ssh-de-casa"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.meu_ip
    destination_address_prefix = "*"
  }

  # Tráfego que veio pelo túnel e está sendo encaminhado (casa -> app)
  security_rule {
    name                       = "encaminhar-de-casa"
    priority                   = 120
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.home_cidr, var.tunnel_cidr]
    destination_address_prefix = "VirtualNetwork"
  }

  # Tráfego que vem da VNet com destino à casa (ex.: VM app -> 192.168.1.6)
  security_rule {
    name                         = "vnet-para-casa"
    priority                     = 130
    direction                    = "Inbound"
    access                       = "Allow"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "10.20.0.0/16"
    destination_address_prefixes = [var.home_cidr, var.tunnel_cidr]
  }

  # SAÍDA da NVA: pacotes encaminhados têm origem/destino fora da VNet
  # (192.168.1.0/24 e 10.99.0.0/24 não fazem parte da tag VirtualNetwork),
  # então a regra padrão AllowVnetOutBound não cobre esse tráfego.
  security_rule {
    name                       = "saida-casa-para-vnet"
    priority                   = 100
    direction                  = "Outbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.home_cidr, var.tunnel_cidr]
    destination_address_prefix = "10.20.0.0/16"
  }

  security_rule {
    name                         = "saida-vnet-para-casa"
    priority                     = 110
    direction                    = "Outbound"
    access                       = "Allow"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "10.20.0.0/16"
    destination_address_prefixes = [var.home_cidr, var.tunnel_cidr]
  }
}

resource "azurerm_subnet_network_security_group_association" "nva" {
  subnet_id                 = azurerm_subnet.nva.id
  network_security_group_id = azurerm_network_security_group.nva.id
}

resource "azurerm_public_ip" "nva" {
  name                = "pip-nva"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "nva" {
  name                  = "nic-nva"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  ip_forwarding_enabled = true # sem isso o Azure descarta pacotes que não são para a própria VM

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.nva.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.nva_ip_privado
    public_ip_address_id          = azurerm_public_ip.nva.id
  }
}

resource "azurerm_linux_virtual_machine" "nva" {
  name                  = "vm-nva"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.tamanho
  admin_username        = "caio"
  network_interface_ids = [azurerm_network_interface.nva.id]

  custom_data = base64encode(templatefile("${path.module}/cloud-init-nva.yaml", {
    home_public_key = var.home_public_key
    home_cidr       = var.home_cidr
  }))

  admin_ssh_key {
    username   = "caio"
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# ---------------- App (VM privada, sem IP público) ----------------

resource "azurerm_network_security_group" "app" {
  name                = "nsg-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  # Origem on-prem via NVA NÃO entra na tag VirtualNetwork: precisa de regra explícita
  security_rule {
    name                       = "de-casa-via-vpn"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefixes    = [var.home_cidr, var.tunnel_cidr]
    destination_address_prefix = "*"
  }

  security_rule {
    name                         = "saida-para-casa-via-vpn"
    priority                     = 100
    direction                    = "Outbound"
    access                       = "Allow"
    protocol                     = "*"
    source_port_range            = "*"
    destination_port_range       = "*"
    source_address_prefix        = "*"
    destination_address_prefixes = [var.home_cidr, var.tunnel_cidr]
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

# UDR: o caminho para a casa passa pela NVA
resource "azurerm_route_table" "app" {
  name                = "rt-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  route {
    name                   = "para-casa"
    address_prefix         = var.home_cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.nva_ip_privado
  }

  route {
    name                   = "para-tunel"
    address_prefix         = var.tunnel_cidr
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.nva_ip_privado
  }
}

resource "azurerm_subnet_route_table_association" "app" {
  subnet_id      = azurerm_subnet.app.id
  route_table_id = azurerm_route_table.app.id
}

resource "azurerm_network_interface" "app" {
  name                = "nic-app"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Static"
    private_ip_address            = local.app_ip_privado
  }
}

resource "azurerm_linux_virtual_machine" "app" {
  name                  = "vm-app"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.tamanho
  admin_username        = "caio"
  network_interface_ids = [azurerm_network_interface.app.id]

  admin_ssh_key {
    username   = "caio"
    public_key = local.ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }
}

# ---------------- Saídas ----------------

output "nva_ip_publico" {
  value = azurerm_public_ip.nva.ip_address
}

output "app_ip_privado" {
  value = local.app_ip_privado
}
