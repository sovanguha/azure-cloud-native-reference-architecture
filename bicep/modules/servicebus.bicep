// ============================================================
// Azure Service Bus Module
// Topics: orders  Subscriptions: payment, inventory, notification, bridge
// Partition Key = orderId (set by publisher, enforced by convention)
// ============================================================

param namespaceName string
param location string
param tags object
param logAnalyticsWorkspaceId string

@allowed(['Standard', 'Premium'])
param skuName string = 'Standard'

// ── Namespace ─────────────────────────────────────────────────
resource serviceBusNamespace 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: namespaceName
  location: location
  tags: tags
  sku: {
    name: skuName
    tier: skuName
    // Premium: 1 messaging unit minimum for private endpoints
    capacity: skuName == 'Premium' ? 1 : 0
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: skuName == 'Premium' ? 'Disabled' : 'Enabled'
    disableLocalAuth: true  // Force Managed Identity auth — no connection strings
  }
}

// ── Orders Topic ──────────────────────────────────────────────
resource ordersTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBusNamespace
  name: 'orders'
  properties: {
    defaultMessageTimeToLive: 'P14D'      // 14-day retention
    maxSizeInMegabytes: 5120
    requiresDuplicateDetection: true
    duplicateDetectionHistoryTimeWindow: 'PT10M'
    supportOrdering: true                  // Required for partitionKey ordering
    enablePartitioning: skuName == 'Standard'  // Premium uses premium partitioning
  }
}

// ── Payment Subscription ──────────────────────────────────────
resource paymentSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: ordersTopic
  name: 'payment-subscription'
  properties: {
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
    deadLetteringOnFilterEvaluationExceptions: true
    lockDuration: 'PT5M'     // 5 min lock — payment processing may take time
    defaultMessageTimeToLive: 'P7D'
    enableBatchedOperations: true
  }
}

// ── Inventory Subscription ────────────────────────────────────
resource inventorySubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: ordersTopic
  name: 'inventory-subscription'
  properties: {
    maxDeliveryCount: 5
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT2M'
    defaultMessageTimeToLive: 'P7D'
    enableBatchedOperations: true
  }
}

// ── Notification Subscription ─────────────────────────────────
resource notificationSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: ordersTopic
  name: 'notification-subscription'
  properties: {
    maxDeliveryCount: 3       // Fewer retries — notification failure is lower severity
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT1M'
    defaultMessageTimeToLive: 'P3D'
    enableBatchedOperations: true
  }
}

// ── Bridge Subscription (→ Kafka) ─────────────────────────────
resource bridgeSubscription 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: ordersTopic
  name: 'bridge-subscription'
  properties: {
    maxDeliveryCount: 10
    deadLetteringOnMessageExpiration: true
    lockDuration: 'PT3M'
    defaultMessageTimeToLive: 'P7D'
    enableBatchedOperations: true
  }
}

// ── Diagnostics → Log Analytics ───────────────────────────────
resource diagnostics 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: 'sb-diagnostics'
  scope: serviceBusNamespace
  properties: {
    workspaceId: logAnalyticsWorkspaceId
    logs: [
      { category: 'OperationalLogs'; enabled: true }
      { category: 'VNetAndIPFilteringLogs'; enabled: true }
    ]
    metrics: [
      { category: 'AllMetrics'; enabled: true }
    ]
  }
}

// ── Outputs ──────────────────────────────────────────────────
output namespaceName string = serviceBusNamespace.name
output namespaceId string = serviceBusNamespace.id
output topicName string = ordersTopic.name
