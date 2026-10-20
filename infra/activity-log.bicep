targetScope = 'subscription'

@description('Existing destination workspace resource ID. Apply once per approved source subscription.')
param workspaceResourceId string

@description('Use a distinct name and inspect existing diagnostic settings to avoid duplicate ingestion.')
param diagnosticSettingName string = 'sre-pilot-activity-log'

resource activityLog 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = {
  name: diagnosticSettingName
  properties: {
    workspaceId: workspaceResourceId
    logs: [
      {
        category: 'Administrative'
        enabled: true
      }
      {
        category: 'Policy'
        enabled: true
      }
      {
        category: 'ServiceHealth'
        enabled: true
      }
      {
        category: 'ResourceHealth'
        enabled: true
      }
    ]
  }
}

output diagnosticSettingId string = activityLog.id
