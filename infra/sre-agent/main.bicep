// Platform-operations SRE Agent for the foundation starter kit.
// Read-only (accessLevel Low, Review mode), subscription-wide Reader.
// Residual risk: Reader (*/read) also grants query access to all log data in every workspace in the
// subscription, so a separate Log Analytics Reader assignment is redundant. To limit log access to
// selected workspaces, replace Reader with a custom role that excludes workspace queries and
// resource-context logs, then grant Log Analytics Reader on the selected workspaces only (see README).
// Deploy:
//   az deployment sub create --location swedencentral --template-file main.bicep --parameters main.bicepparam

targetScope = 'subscription'

@description('Agent name: 2-32 chars, letters, digits and hyphens.')
param agentName string = 'sre-platform-ops'

param agentResourceGroupName string = 'rg-platform-sreagent'

@description('SRE Agent supported region. Sweden Central: lowest EU retail AAU tier, EU region.')
param location string = 'swedencentral'

@description('Monthly active-flow AAU allocation (500-1,000,000). Always-on (4 AAU/h) is billed on top.')
@minValue(500)
param monthlyAgentUnitLimit int = 2000

@description('MicrosoftFoundry keeps processing within the EU Data Boundary; Anthropic is excluded from EUDB.')
@allowed([ 'MicrosoftFoundry', 'Anthropic' ])
param defaultModelProvider string = 'MicrosoftFoundry'

param defaultModelName string = 'Automatic'

@description('Existing Log Analytics workspaces (resource IDs) to connect, e.g. the ALZ management workspace and AKS/Container insights workspaces.')
param logAnalyticsWorkspaceIds array = []

@allowed([ 'AzMonitor', 'None' ])
param incidentPlatformType string = 'AzMonitor'

param tags object = {
  workload: 'sre-agent'
  purpose: 'platform-operations'
  'starter-kit': 'azure-sre-foundation'
}

var readerRoleId = 'acdd72a7-3385-48ef-bd42-f606fba81ae7'
var suffix = take(uniqueString(subscription().subscriptionId, agentResourceGroupName, agentName), 6)

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: agentResourceGroupName
  location: location
  tags: tags
}

module core 'agent.bicep' = {
  name: 'sreagent-core'
  scope: rg
  params: {
    agentName: agentName
    location: location
    suffix: suffix
    monthlyAgentUnitLimit: monthlyAgentUnitLimit
    defaultModelProvider: defaultModelProvider
    defaultModelName: defaultModelName
    tags: tags
    managedSubscriptionId: subscription().subscriptionId
    logAnalyticsWorkspaceIds: logAnalyticsWorkspaceIds
    incidentPlatformType: incidentPlatformType
  }
}

var principalKeys = [ 'uami', 'system' ]

resource subReader 'Microsoft.Authorization/roleAssignments@2022-04-01' = [for key in principalKeys: {
  name: guid(subscription().id, agentName, key, readerRoleId)
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', readerRoleId)
    principalId: key == 'uami' ? core.outputs.uamiPrincipalId : core.outputs.agentSystemPrincipalId
    principalType: 'ServicePrincipal'
  }
}]

output agentId string = core.outputs.agentId
output agentPortalUrl string = 'https://sre.azure.com/#/agent/${subscription().subscriptionId}/${agentResourceGroupName}/${agentName}'
output lawId string = core.outputs.lawId
