targetScope = 'resourceGroup'

@description('Azure region for telemetry. This does not select the SRE Agent region or guarantee its data residency.')
param location string = resourceGroup().location

@description('Name of a NEW pilot workspace. Prefer existing ALZ monitoring in production.')
@minLength(4)
@maxLength(63)
param workspaceName string

@description('Explicit network choice. Disabled requires a separately configured AMPLS/private endpoint and a working agent query path.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForQuery string

@description('Explicit network choice. Disabled requires private ingestion connectivity before collection works.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccessForIngestion string

@description('Retention for the pilot; confirm table-specific and regulatory requirements before production.')
@minValue(30)
@maxValue(730)
param retentionInDays int = 30

@description('Tags without customer names, secrets, or other sensitive identifiers.')
param tags object = {
  environment: 'sandbox'
  purpose: 'sre-foundation-pilot'
}

module workspace 'br/public:avm/res/operational-insights/workspace:0.16.1' = {
  name: 'sre-pilot-workspace'
  params: {
    name: workspaceName
    location: location
    skuName: 'PerGB2018'
    dataRetention: retentionInDays
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    features: {
      disableLocalAuth: true
      enableLogAccessUsingOnlyResourcePermissions: false
    }
    tags: tags
  }
}

output workspaceResourceId string = workspace.outputs.resourceId
