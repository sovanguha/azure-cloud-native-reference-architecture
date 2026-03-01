// ============================================================
// Azure Cloud-Native Reference Architecture
// Main Deployment Template
// Author: Sovan Guha (AZ-305)
// ============================================================

targetScope = 'resourceGroup'

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Application name prefix')
param appName string = 'orderplatform'

@description('AKS node pool VM size')
param aksNodeVmSize string = 'Standard_D4s_v5'

@description('Minimum node count for AKS system pool')
@minValue(1)
@maxValue(5)
param aksMinNodeCount int = 1

@description('Maximum node count for AKS user pool')
@minValue(3)
@maxValue(50)
param aksMaxNodeCount int = 10

var resourcePrefix = '${appName}-${environment}'
var tags = {
  Environment: environment
  Application: appName
  ManagedBy: 'Bicep'
  Architect: 'Sovan Guha'
  CostCentre: 'platform-engineering'
}

// ── Log Analytics Workspace (deploy first — others depend on it) ──
module monitoring 'modules/monitoring.bicep' = {
  name: 'monitoring-deployment'
  params: {
    workspaceName: '${resourcePrefix}-logs'
    location: location
    tags: tags
    retentionDays: environment == 'prod' ? 90 : 30
  }
}

// ── Key Vault ─────────────────────────────────────────────────
module keyVault 'modules/keyvault.bicep' = {
  name: 'keyvault-deployment'
  params: {
    keyVaultName: '${resourcePrefix}-kv'
    location: location
    tags: tags
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

// ── Service Bus ───────────────────────────────────────────────
module serviceBus 'modules/servicebus.bicep' = {
  name: 'servicebus-deployment'
  params: {
    namespaceName: '${resourcePrefix}-sb'
    location: location
    tags: tags
    skuName: environment == 'prod' ? 'Premium' : 'Standard'
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
  }
}

// ── AKS Cluster ───────────────────────────────────────────────
module aks 'modules/aks.bicep' = {
  name: 'aks-deployment'
  params: {
    clusterName: '${resourcePrefix}-aks'
    location: location
    tags: tags
    nodeVmSize: aksNodeVmSize
    minNodeCount: aksMinNodeCount
    maxNodeCount: aksMaxNodeCount
    logAnalyticsWorkspaceId: monitoring.outputs.workspaceId
    keyVaultName: keyVault.outputs.keyVaultName
  }
}

// ── Outputs ───────────────────────────────────────────────────
output aksClusterName string = aks.outputs.clusterName
output aksClusterFqdn string = aks.outputs.clusterFqdn
output serviceBusNamespace string = serviceBus.outputs.namespaceName
output keyVaultUri string = keyVault.outputs.keyVaultUri
output logAnalyticsWorkspaceId string = monitoring.outputs.workspaceId
