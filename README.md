# Azure Homelab

Laboratórios práticos de **Azure, redes em nuvem e Infraestrutura como Código (Terraform)**, integrando a nuvem com um homelab real (servidor Debian/OpenMediaVault, Tailscale e rede IoT isolada com MikroTik).

Cada lab é criado do zero com código, testado, documentado com evidências e destruído ao final para não gerar custo.

## Labs

| # | Lab | Tecnologias | Status |
|---|---|---|---|
| 1 | [VNet segmentada + VM com SSH restrito](lab1-vnet-vm/) | Terraform, VNet, Subnets, NSG, VM Linux, SSH com chave | ✅ Concluído |
| 2 | State remoto + pipeline CI/CD | Azure Storage, GitHub Actions, OIDC | 🔜 Em breve |
| 3 | Rede híbrida: homelab ↔ Azure por VPN | VNet, VPN/WireGuard, rotas | 🔜 Em breve |
| 4 | Servidor on-premises gerenciado pelo Azure Arc | Azure Arc, Azure Monitor, Policy | 🔜 Em breve |

## Ferramentas

- Azure CLI e Portal
- Terraform (provider `azurerm` 4.x)
- WSL (Ubuntu 24.04), Git e GitHub

## Boas práticas seguidas

- Nenhum segredo no repositório: `tfstate`, IPs de origem e ID da assinatura ficam fora do Git
- `terraform plan -out` antes de todo `apply`
- Ambientes efêmeros: `terraform destroy` ao fim de cada sessão
- Cada lab documenta os problemas reais encontrados e como foram resolvidos

