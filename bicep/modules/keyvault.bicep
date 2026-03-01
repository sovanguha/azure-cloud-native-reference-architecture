// ============================================================
// Azure Key Vault Module
// RBAC-based access (not access policies — deprecated model)
// Soft-delete + purge protection enabled
// Diagnostics → Log Analytics
// ============================================================

param keyVaultName string
param location string
param tags object
param logAnalyticsWorkspaceId string

@description('Object ID of the AKS kubelet identity for secret access')
param aksKubeletObjectId string = ''

// ── Key Vault ─────────────────────────────────────────────────
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    tenantId: subscription().tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }

    // RBAC model — no access policies
    enableRbacAuthorization: true

    // Soft-delete: 90 days, purge protection on
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enablePurgeProtection: true

    // Network: allow Azure services (AKS workloads use private endpoint in prod)
    networkAcls: {
      bypass: 'AzureServices'
      defaultAction: 'Allow'  // Tighten in prod with private endpoint
    }

    publicNetworkAccess: 'Enabled'  // Override in prod
  }
}

// ── RBAC: AKS Kubelet → Key Vault Secrets User ───────────────
// Only assign if kubelet identity is provided
resource aksKvSecretsUser 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(aksKubeletObjectId)) {
  name: guid(keyVault.id, aksKubeletObjectId, 'KeyVaultSecretsUser')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'  // Key Vault Secrets User
    )
    principalId: aksKubeletObjectId
    principalType: 'ServicePrincipal'
  }
}

// ── Diagnostics → Log Analytics ───────────────────────────────
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'kv-diagnostics'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'AuditEvent'; enabled: true }
      { category: 'AzurePolicyEvaluationDetails'; enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics'; enabled: true }
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────
output keyVaultName string = keyVault.name
output keyVaultId string = keyVault.id
output keyVaultUri string = keyVault.properties.vaultUri
