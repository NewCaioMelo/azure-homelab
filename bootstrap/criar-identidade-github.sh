#!/usr/bin/env bash
# Cria uma identidade gerenciada (User-Assigned Managed Identity) para o
# GitHub Actions acessar o Azure via OIDC, SEM senha ou segredo armazenado.
# O GitHub troca um token de curta duração por um token do Azure, e o Azure
# só aceita tokens vindos deste repositório (federated credentials).
set -euo pipefail

REPO="NewCaioMelo/azure-homelab"
LOCATION="northcentralus"
RG="rg-tfstate"
SA="sttfstate63a9f3"
ID_NAME="id-github-actions"
ISSUER="https://token.actions.githubusercontent.com"
AUDIENCE="api://AzureADTokenExchange"

echo ">> Registrando o provider de identidades gerenciadas"
az provider register -n Microsoft.ManagedIdentity --wait

echo ">> Identidade $ID_NAME"
az identity create -n "$ID_NAME" -g "$RG" -l "$LOCATION" -o none
CLIENT_ID=$(az identity show -n "$ID_NAME" -g "$RG" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show -n "$ID_NAME" -g "$RG" --query principalId -o tsv)
SUB_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)

# O GitHub passou a emitir o "subject" do token com os IDs imutáveis do dono e do
# repositório (repo:dono@ID/repo@ID:...). Montamos o prefixo no mesmo formato.
OWNER="${REPO%%/*}"; NAME="${REPO##*/}"
OWNER_ID=$(gh api "users/$OWNER" -q .id)
REPO_ID=$(gh api "repos/$REPO" -q .id)
SUBJ="repo:${OWNER}@${OWNER_ID}/${NAME}@${REPO_ID}"

echo ">> Federated credentials (quem pode usar a identidade)"
az identity federated-credential create -n github-main \
  --identity-name "$ID_NAME" -g "$RG" --issuer "$ISSUER" --audiences "$AUDIENCE" \
  --subject "${SUBJ}:ref:refs/heads/main" -o none
az identity federated-credential create -n github-pr \
  --identity-name "$ID_NAME" -g "$RG" --issuer "$ISSUER" --audiences "$AUDIENCE" \
  --subject "${SUBJ}:pull_request" -o none
az identity federated-credential create -n github-env-lab \
  --identity-name "$ID_NAME" -g "$RG" --issuer "$ISSUER" --audiences "$AUDIENCE" \
  --subject "${SUBJ}:environment:lab" -o none

echo ">> Aguardando a identidade propagar (30s)"
sleep 30

echo ">> Permissões (RBAC)"
az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Contributor" --scope "/subscriptions/$SUB_ID" -o none
SA_ID=$(az storage account show -n "$SA" -g "$RG" --query id -o tsv)
az role assignment create --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Contributor" --scope "$SA_ID" -o none

echo ">> Gravando os IDs como secrets do repositório (via gh CLI)"
gh secret set AZURE_CLIENT_ID       --body "$CLIENT_ID" -R "$REPO"
gh secret set AZURE_TENANT_ID       --body "$TENANT_ID" -R "$REPO"
gh secret set AZURE_SUBSCRIPTION_ID --body "$SUB_ID"    -R "$REPO"

echo
echo "Pronto! Identidade $ID_NAME criada e secrets gravados no GitHub."
