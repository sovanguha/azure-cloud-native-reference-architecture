// ============================================================
// AKS Cluster Module
// Features: KEDA add-on, Workload Identity, Key Vault CSI Driver
//           Container Insights, Managed Identity (no service principal)
// ============================================================

param clusterName string
param location string
param tags object
param nodeVmSize string
param minNodeCount int
param maxNodeCount int
param logAnalyticsWorkspaceId string
param keyVaultName string

@description('Kubernetes version')
param kubernetesVersion string = '1.29'

// ── Managed Identity for AKS ─────────────────────────────────
resource aksIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: '${clusterName}-identity'
  location: location
  tags: tags
}

// ── AKS Cluster ───────────────────────────────────────────────
resource aksCluster 'Microsoft.ContainerService/managedClusters@2024-01-01' = {
  name: clusterName
  location: location
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksIdentity.id}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: clusterName
    enableRBAC: true

    // ── System Node Pool ──────────────────────────────────────
    agentPoolProfiles: [
      {
        name: 'system'
        mode: 'System'
        count: minNodeCount
        minCount: minNodeCount
        maxCount: 3
        enableAutoScaling: true
        vmSize: nodeVmSize
        osType: 'Linux'
        osDiskSizeGB: 128
        type: 'VirtualMachineScaleSets'
        availabilityZones: ['1', '2', '3']
        nodeTaints: ['CriticalAddonsOnly=true:NoSchedule']
        upgradeSettings: {
          maxSurge: '1'
        }
      }
      {
        // ── Worker Node Pool ───────────────────────────────────
        name: 'workers'
        mode: 'User'
        count: 2
        minCount: 0                // Scale to zero when no workloads
        maxCount: maxNodeCount
        enableAutoScaling: true
        vmSize: nodeVmSize
        osType: 'Linux'
        osDiskSizeGB: 128
        type: 'VirtualMachineScaleSets'
        availabilityZones: ['1', '2', '3']
        upgradeSettings: {
          maxSurge: '25%'
        }
      }
    ]

    // ── OIDC + Workload Identity ─────────────────────────────
    // Required for KEDA → Service Bus Managed Identity auth
    oidcIssuerProfile: {
      enabled: true
    }
    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    // ── Add-ons ──────────────────────────────────────────────
    addonProfiles: {
      // Container Insights → Log Analytics
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspaceId
        }
      }
      // Azure Key Vault CSI Driver (no secrets in K8s Secrets)
      azureKeyvaultSecretsProvider: {
        enabled: true
        config: {
          enableSecretRotation: 'true'
          rotationPollInterval: '2m'
        }
      }
    }

    // ── KEDA Add-on (event-driven autoscaling) ────────────────
    workloadAutoScalerProfile: {
      keda: {
        enabled: true
      }
    }

    // ── Network Configuration ─────────────────────────────────
    networkProfile: {
      networkPlugin: 'azure'
      networkPolicy: 'azure'
      loadBalancerSku: 'standard'
    }

    // ── Auto-upgrade ──────────────────────────────────────────
    autoUpgradeProfile: {
      upgradeChannel: 'patch'
    }
  }
}

// ── Key Vault RBAC: AKS Managed Identity → Key Vault Secrets User ─
resource kvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aksIdentity.id, 'Key Vault Secrets User')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6'  // Key Vault Secrets User
    )
    principalId: aksCluster.properties.identityProfile.kubeletidentity.objectId
    principalType: 'ServicePrincipal'
  }
}

// ── Outputs ──────────────────────────────────────────────────
output clusterName string = aksCluster.name
output clusterFqdn string = aksCluster.properties.fqdn
output clusterOidcIssuer string = aksCluster.properties.oidcIssuerProfile.issuerURL
output kubeletIdentityObjectId string = aksCluster.properties.identityProfile.kubeletidentity.objectId
