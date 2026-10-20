// Resource-group-scoped core: identity, telemetry, SRE Agent, admin role.
// Derived from https://github.com/microsoft/sre-agent/tree/main/sreagent-templates (bicep/agent-core.bicep).

param agentName string
param location string
param suffix string
param monthlyAgentUnitLimit int
param defaultModelProvider string
param defaultModelName string
param tags object
param managedSubscriptionId string

@description('Existing Log Analytics workspaces (resource IDs) the agent queries through a LogAnalytics connector.')
param logAnalyticsWorkspaceIds array = []

@description('Incident platform. AzMonitor routes fired Azure Monitor alerts to response plans; None disables incident intake.')
@allowed([ 'AzMonitor', 'None' ])
param incidentPlatformType string = 'AzMonitor'

@description('Look-back window in days for the Azure Monitor connector.')
param azureMonitorLookbackDays int = 7

var monitoringReaderRoleId = '43d0d8ad-25c7-4714-9337-8ba259a9fe05'
var sreAgentAdministratorRoleId = 'e79298df-d852-4c6d-84f9-5d13249d1e55'

resource law 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: 'law-${agentName}-${suffix}'
  location: location
  tags: tags
  properties: {
    sku: { name: 'PerGB2018' }
    retentionInDays: 30
  }
}

resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'appi-${agentName}-${suffix}'
  location: location
  kind: 'web'
  tags: tags
  properties: {
    Application_Type: 'web'
    Request_Source: 'SreAgent'
    WorkspaceResourceId: law.id
  }
}

#disable-next-line BCP073
resource identity 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  name: 'id-${agentName}'
  location: location
  tags: tags
  properties: { isolationScope: 'Regional' }
}

resource monitoringReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(resourceGroup().id, identity.id, monitoringReaderRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', monitoringReaderRoleId)
    principalId: identity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

#disable-next-line BCP081
resource sreAgent 'Microsoft.App/agents@2025-05-01-preview' = {
  name: agentName
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned, UserAssigned'
    userAssignedIdentities: { '${identity.id}': {} }
  }
  properties: {
    knowledgeGraphConfiguration: {
      identity: identity.id
      managedResources: [ '/subscriptions/${managedSubscriptionId}' ]
    }
    // Low = read-only investigation; Review = human approval before any action.
    actionConfiguration: {
      accessLevel: 'Low'
      identity: identity.id
      mode: 'Review'
    }
    logConfiguration: {
      applicationInsightsConfiguration: {
        appId: appInsights.properties.AppId
        connectionString: appInsights.properties.ConnectionString
        applicationInsightsResourceId: appInsights.id
      }
    }
    // Same shape the official Apply-Extras script PATCHes; kept in IaC so redeployments preserve it.
    incidentManagementConfiguration: incidentPlatformType == 'None' ? null : {
      type: incidentPlatformType
      connectionName: toLower(incidentPlatformType)
    }
    upgradeChannel: 'Stable'
    monthlyAgentUnitLimit: monthlyAgentUnitLimit
    defaultModel: {
      provider: defaultModelProvider
      name: defaultModelName
    }
    experimentalSettings: {
      EnableWorkspaceTools: true
      EnableHttpTriggers: true
      EnableV2AgentLoop: true
    }
  }
  dependsOn: [ monitoringReader ]
}

resource adminRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(sreAgent.id, deployer().objectId, sreAgentAdministratorRoleId)
  scope: sreAgent
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', sreAgentAdministratorRoleId)
    principalId: deployer().objectId
    principalType: 'User'
  }
}

// Connectors (typed shape from the official agent-extensions.bicep). 'system' = the agent's
// system-assigned identity, which holds Reader on the subscription (main.bicep).
// The platform auto-creates 'law' and 'appinsights' connectors for the agent's own telemetry
// (logConfiguration), so only the Azure Monitor and existing platform workspaces are added here.
#disable-next-line BCP081
resource azureMonitorConnector 'Microsoft.App/agents/connectors@2025-05-01-preview' = {
  parent: sreAgent
  name: 'azure-monitor'
  properties: {
    dataConnectorType: 'AzureMonitor'
    dataSource: '/subscriptions/${managedSubscriptionId}'
    extendedProperties: {
      armResourceId: '/subscriptions/${managedSubscriptionId}'
      lookbackDays: azureMonitorLookbackDays
    }
    identity: 'system'
  }
}

#disable-next-line BCP081
@batchSize(1)
resource logAnalyticsConnectors 'Microsoft.App/agents/connectors@2025-05-01-preview' = [for wsId in logAnalyticsWorkspaceIds: {
  parent: sreAgent
  name: 'law-${take(toLower(last(split(wsId, '/'))), 28)}'
  properties: {
    dataConnectorType: 'LogAnalytics'
    dataSource: wsId
    extendedProperties: {
      armResourceId: wsId
      resource: { name: last(split(wsId, '/')) }
    }
    identity: 'system'
  }
  dependsOn: [ azureMonitorConnector ]
}]

output agentId string = sreAgent.id
output agentSystemPrincipalId string = sreAgent.identity.principalId
output uamiPrincipalId string = identity.properties.principalId
output uamiId string = identity.id
output lawId string = law.id
