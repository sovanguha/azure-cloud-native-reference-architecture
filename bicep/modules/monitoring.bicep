// ============================================================
// Monitoring Module
// Log Analytics Workspace + Application Insights
// Alert rules for DLQ depth, consumer lag, circuit breaker
// ============================================================

param workspaceName string
param location string
param tags object

@description('Log retention in days')
@minValue(30)
@maxValue(730)
param retentionDays int = 90

@description('Email address for critical alerts')
param alertEmailAddress string = ''

// ── Log Analytics Workspace ───────────────────────────────────
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: workspaceName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionDays
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ── Application Insights ──────────────────────────────────────
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${workspaceName}-ai'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    RetentionInDays: retentionDays
    SamplingPercentage: 100
  }
}

// ── Action Group (alert notifications) ───────────────────────
resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (!empty(alertEmailAddress)) {
  name: '${workspaceName}-alerts'
  location: 'global'
  tags: tags
  properties: {
    groupShortName: 'platform'
    enabled: true
    emailReceivers: [
      {
        name: 'PlatformArchitect'
        emailAddress: alertEmailAddress
        useCommonAlertSchema: true
      }
    ]
  }
}

// ── Alert: Service Bus DLQ Depth > 10 ────────────────────────
resource dlqAlert 'Microsoft.Insights/scheduledQueryRules@2023-03-15-preview' = {
  name: '${workspaceName}-dlq-alert'
  location: location
  tags: tags
  properties: {
    displayName: 'Service Bus DLQ Depth Exceeded'
    description: 'Alert when any Service Bus subscription DLQ exceeds 10 messages'
    severity: 2  // Warning
    enabled: true
    evaluationFrequency: 'PT5M'
    windowSize: 'PT5M'
    criteria: {
      allOf: [
        {
          query: '''
            AzureMetrics
            | where ResourceProvider == "MICROSOFT.SERVICEBUS"
            | where MetricName == "DeadletteredMessages"
            | where Total > 10
            | project TimeGenerated, Resource, Total
          '''
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
        }
      ]
    }
    actions: !empty(alertEmailAddress) ? {
      actionGroups: [actionGroup.id]
    } : {}
    scopes: [logAnalyticsWorkspace.id]
  }
}

// ── Outputs ──────────────────────────────────────────────────
output workspaceId string = logAnalyticsWorkspace.id
output workspaceName string = logAnalyticsWorkspace.name
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appInsightsInstrumentationKey string = appInsights.properties.InstrumentationKey
