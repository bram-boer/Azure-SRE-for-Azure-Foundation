// Copy to an ignored *.local.bicepparam file and replace every placeholder.
// Deploy this module at resource-group scope in each approved source subscription.
using 'event-alerts.bicep'

param activate = false
param actionGroupIds = [
  '/subscriptions/<subscription-id>/resourceGroups/<monitoring-rg>/providers/Microsoft.Insights/actionGroups/<on-call>'
]
param activityRules = loadJsonContent('event-alerts.json').activityRules

// Keep only rules whose source telemetry, thresholds and evaluation intervals are validated.
param metricRules = [
  {
    name: 'SRE-W1-storage-availability'
    description: 'Storage availability below the approved target; investigate affected flows and tier requirements.'
    enabled: true
    resourceId: '/subscriptions/<subscription-id>/resourceGroups/<storage-rg>/providers/Microsoft.Storage/storageAccounts/<account>'
    resourceType: 'Microsoft.Storage/storageAccounts'
    resourceRegion: '<storage-region>'
    severity: 2
    metricNamespace: 'Microsoft.Storage/storageAccounts'
    metricName: 'Availability'
    aggregation: 'Average'
    operator: 'LessThan'
    threshold: 99
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
  }
]

param logRules = [
  {
    name: 'SRE-UC08-aks-scheduling-failure'
    description: 'Scheduling or scale-up failure in the approved AKS cluster. Requires collected KubeEvents.'
    enabled: true
    workspaceId: '/subscriptions/<subscription-id>/resourceGroups/<monitoring-rg>/providers/Microsoft.OperationalInsights/workspaces/<aks-workspace>'
    location: '<workspace-region>'
    severity: 2
    query: '''
      KubeEvents
      | where TimeGenerated > ago(5m)
      | where _ResourceId =~ '/subscriptions/<subscription-id>/resourceGroups/<aks-rg>/providers/Microsoft.ContainerService/managedClusters/<cluster>'
      | where Reason in ('FailedScheduling', 'FailedScaleUp')
      | project TimeGenerated, _ResourceId, Reason, Message, Name, Namespace
      '''
    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'
    threshold: 0
  }
  {
    name: 'SRE-UC05-expected-heartbeat-missing'
    description: 'An independently registered VM has not sent a heartbeat in 15 minutes, including never-seen sources. Validate onboarding and ingestion grace.'
    enabled: true
    workspaceId: '/subscriptions/<subscription-id>/resourceGroups/<monitoring-rg>/providers/Microsoft.OperationalInsights/workspaces/<management-workspace>'
    location: '<workspace-region>'
    severity: 2
    query: '''
      let Expected = datatable(ResourceId:string) [
        '/subscriptions/<subscription-id>/resourcegroups/<vm-rg>/providers/microsoft.compute/virtualmachines/<vm>'
      ];
      let Seen = Heartbeat
      | where TimeGenerated > ago(15m)
      | summarize LastSeen = max(TimeGenerated) by ResourceId = tolower(_ResourceId);
      Expected
      | extend ResourceId = tolower(ResourceId)
      | join kind=leftouter Seen on ResourceId
      | where isnull(LastSeen)
      | project ResourceId, LastSeen
      '''
    evaluationFrequency: 'PT5M'
    windowSize: 'PT15M'
    threshold: 0
  }
]
