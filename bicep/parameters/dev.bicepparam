// ============================================================
// Dev Environment Parameters
// ============================================================
using '../main.bicep'

param environment = 'dev'
param location = 'uksouth'
param appName = 'orderplatform'
param aksNodeVmSize = 'Standard_D2s_v5'   // Smaller for dev
param aksMinNodeCount = 1
param aksMaxNodeCount = 5
