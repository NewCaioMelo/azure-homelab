variable "meu_ip" {
  description = "IP público (CIDR /32) autorizado a acessar a VM por SSH"
  type        = string
}

variable "tamanho" {
  description = "Tamanho da VM"
  type        = string
  default     = "Standard_B2ats_v2"
}

variable "ssh_public_key" {
  description = "Chave SSH pública. Se vazio, usa ~/.ssh/id_ed25519.pub (execução local)"
  type        = string
  default     = ""
}

locals {
  ssh_public_key = coalesce(var.ssh_public_key, try(file(pathexpand("~/.ssh/id_ed25519.pub")), null))
}

resource "azurerm_network_security_rule" "ssh" {
  name                        = "permitir-ssh-casa"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "22"
  source_address_prefix       = var.meu_ip
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.lab.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_public_ip" "vm" {
  name                = "pip-vm-web"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  name                = "nic-vm-web"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = azurerm_subnet.web.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}

resource "azurerm_linux_virtual_machine" "web" {
  name                  = "vm-web"
  location              = azurerm_resource_group.lab.location
  resource_group_name   = azurerm_resource_group.lab.name
  size                  = var.tamanho
  admin_username        = "caio"
  network_interface_ids = [azurerm_network_interface.vm.id]

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

output "ip_publico" {
  value = azurerm_public_ip.vm.ip_address
}
