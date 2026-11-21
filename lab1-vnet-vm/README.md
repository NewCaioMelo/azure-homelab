# Lab 1: VNet segmentada + VM Linux com acesso SSH restrito (Terraform)

Infraestrutura básica de rede no Azure criada 100% como código com Terraform: rede virtual segmentada em subnets, firewall de rede (NSG) e uma VM Linux acessível por SSH **somente a partir de um IP autorizado**.

## Arquitetura

![Topologia](img/topologia.png)

| Recurso | Nome | Detalhe |
|---|---|---|
| Resource Group | `rg-lab1` | North Central US |
| Virtual Network | `vnet-lab1` | `10.10.0.0/16` |
| Subnet (aplicação) | `snet-web` | `10.10.1.0/24`, com NSG |
| Subnet (dados) | `snet-db` | `10.10.2.0/24` |
| Network Security Group | `nsg-web` | associado à subnet `snet-web` |
| Regra NSG | `permitir-ssh-casa` | TCP 22, origem = IP informado via variável, prioridade 100 |
| VM | `vm-web` | Ubuntu 24.04 LTS, autenticação só por chave SSH (ed25519) |
| IP público | `pip-vm-web` | Standard, estático |

## O que este lab demonstra

- **Infraestrutura como código:** todo o ambiente sobe com `terraform apply` e é removido com `terraform destroy`.
- **Segmentação de rede:** subnets separadas por função (web e banco).
- **Menor privilégio na rede:** o NSG libera SSH apenas para um `/32`; todo o resto cai na regra padrão `DenyAllInBound` (65500).
- **Segurança de credenciais:** sem senha na VM (só chave pública), IP de origem e ID da assinatura fora do código (variáveis/ambiente), `tfstate` fora do Git.
- **Variáveis:** tamanho da VM e IP autorizado parametrizados.

## Como executar

Pré-requisitos: Azure CLI, Terraform >= 1.5, chave SSH em `~/.ssh/id_ed25519.pub`.

```bash
az login
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)

terraform init
terraform plan -var="meu_ip=$(curl -4 -s ifconfig.me)/32" -out=plano
terraform apply plano

ssh caio@$(terraform output -raw ip_publico)

terraform destroy -var="meu_ip=0.0.0.0/32"
```

## Validação

| Teste | Resultado esperado | Evidência |
|---|---|---|
| SSH a partir do IP autorizado | Conecta | ![ssh ok](img/ssh-ok.png) |
| SSH a partir de outra rede (4G) | `Connection timed out` (pacote descartado pelo NSG) | ![ssh bloqueado](img/ssh-bloqueado.jpeg) |
| Regras efetivas do NSG | Regra 100 acima das regras padrão | ![nsg](img/nsg-regras.png) |
| VM provisionada | `Apply complete!` com o IP público de saída | ![vm up](img/vm-up.png) |
| Recursos criados | 6 recursos no `rg-lab1` | ![recursos](img/recursos.png) |
| Limpeza | `Destroy complete! Resources: 10 destroyed.` | ![destroy](img/destroy.png) |

O timeout (e não "connection refused") mostra que o bloqueio aconteceu no NSG, antes do pacote chegar à VM.

## Problemas encontrados e soluções

| Problema | Causa | Solução |
|---|---|---|
| `terraform plan` muito lento / interrompido | O provider tenta registrar dezenas de Resource Providers numa assinatura nova | `resource_provider_registrations = "none"` e registro manual só de `Microsoft.Network`, `Compute` e `Storage` |
| `SkuNotAvailable` para `Standard_B1s` e `Standard_B2ats_v2` em Brazil South | Falta de capacidade na região | Tamanho da VM virou variável (`tamanho`) para trocar sem editar código |
| `RequestDisallowedByAzure` em East US | Assinatura Azure for Students só permite 5 regiões | Consulta à policy (`az policy assignment list`) e migração para `northcentralus` |

## Próximos passos

- NSG próprio para `snet-db` liberando só tráfego vindo de `snet-web`
- State remoto em Azure Storage
- Pipeline no GitHub Actions (plan em PR, apply no merge)
