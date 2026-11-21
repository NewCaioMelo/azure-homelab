#!/usr/bin/env bash
# Cria a infraestrutura do state remoto do Terraform no Azure.
# Executar UMA vez (cada execução gera um Storage Account com nome novo).
set -euo pipefail

LOCATION="northcentralus"
RG="rg-tfstate"
SA="sttfstate$(openssl rand -hex 3)"   # nome precisa ser único no mundo todo
CONTAINER="tfstate"

echo ">> Resource Group $RG"
az group create -n "$RG" -l "$LOCATION" -o none

echo ">> Storage Account $SA (sem acesso público e sem chave compartilhada)"
az storage account create -n "$SA" -g "$RG" -l "$LOCATION" \
  --sku Standard_LRS --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --allow-shared-key-access false -o none

echo ">> Versionamento de blobs (permite recuperar versões antigas do state)"
az storage account blob-service-properties update \
  -n "$SA" -g "$RG" --enable-versioning true -o none

echo ">> Permissão de dados (Entra ID) para o usuário atual"
SA_ID=$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)
ME=$(az ad signed-in-user show --query id -o tsv)
az role assignment create --assignee-object-id "$ME" \
  --assignee-principal-type User \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none

echo ">> Aguardando a permissão propagar (60s)"
sleep 60

echo ">> Container $CONTAINER"
az storage container create -n "$CONTAINER" \
  --account-name "$SA" --auth-mode login -o none

echo
echo "Pronto! Anote o nome do Storage Account: $SA"
