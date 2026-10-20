using 'main.bicep'

param agentName = 'sre-platform-ops'
param agentResourceGroupName = 'rg-platform-sreagent'
param location = 'swedencentral'
param monthlyAgentUnitLimit = 2000
param defaultModelProvider = 'MicrosoftFoundry'
param defaultModelName = 'Automatic'
param incidentPlatformType = 'AzMonitor'
// Replace with your ALZ management workspace (AMBA, Activity Log) and AKS / Container insights workspace IDs.
param logAnalyticsWorkspaceIds = [
  '/subscriptions/<subscription-id>/resourceGroups/<rg-management>/providers/Microsoft.OperationalInsights/workspaces/<law-management>'
  '/subscriptions/<subscription-id>/resourceGroups/<rg-aks-monitoring>/providers/Microsoft.OperationalInsights/workspaces/<law-aks>'
]
