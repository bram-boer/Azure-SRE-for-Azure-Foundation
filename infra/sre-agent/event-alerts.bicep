targetScope = 'resourceGroup'

type activityRule = {
  name: string
  description: string
  enabled: bool
  category: 'Administrative' | 'ResourceHealth' | 'ServiceHealth'
  operations: string[]
  status: string
}

type metricRule = {
  name: string
  description: string
  enabled: bool
  resourceId: string
  resourceType: string
  resourceRegion: string
  severity: 0 | 1 | 2 | 3 | 4
  metricNamespace: string
  metricName: string
  aggregation: 'Average' | 'Count' | 'Minimum' | 'Maximum' | 'Total'
  operator: 'Equals' | 'GreaterThan' | 'GreaterThanOrEqual' | 'LessThan' | 'LessThanOrEqual'
  threshold: int
  evaluationFrequency: string
  windowSize: string
}

type logRule = {
  name: string
  description: string
  enabled: bool
  workspaceId: string
  location: string
  severity: 0 | 1 | 2 | 3 | 4
  query: string
  evaluationFrequency: string
  windowSize: string
  threshold: int
}

@description('Approved source subscription. Deploy once in each source subscription; scopes are not inferred from connectors.')
param sourceSubscriptionId string = subscription().subscriptionId

@description('Existing action groups for independent human notification. Azure Monitor incident intake is configured separately on the agent.')
@minLength(1)
param actionGroupIds string[]

@description('Leave false until response-plan routing and independent on-call delivery pass sandbox acceptance.')
param activate bool = false

param activityRules activityRule[]
param metricRules metricRule[] = []
param logRules logRule[] = []
param tags object = {}

resource activityAlerts 'Microsoft.Insights/activityLogAlerts@2020-10-01' = [for rule in activityRules: {
  name: rule.name
  location: 'global'
  tags: tags
  properties: {
    description: rule.description
    enabled: activate && rule.enabled
    scopes: [ '/subscriptions/${sourceSubscriptionId}' ]
    condition: {
      allOf: concat(
        [ { field: 'category', equals: rule.category } ],
        empty(rule.status) ? [] : [ { field: 'status', equals: rule.status } ],
        empty(rule.operations) ? [] : [
          {
            anyOf: map(rule.operations, operation => {
              field: 'operationName'
              equals: operation
            })
          }
        ]
      )
    }
    actions: {
      actionGroups: [for id in actionGroupIds: { actionGroupId: id }]
    }
  }
}]

resource metricAlerts 'Microsoft.Insights/metricAlerts@2018-03-01' = [for rule in metricRules: {
  name: rule.name
  location: 'global'
  tags: tags
  properties: {
    description: rule.description
    enabled: activate && rule.enabled
    severity: rule.severity
    scopes: [ rule.resourceId ]
    targetResourceType: rule.resourceType
    targetResourceRegion: rule.resourceRegion
    evaluationFrequency: rule.evaluationFrequency
    windowSize: rule.windowSize
    autoMitigate: true
    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'
      allOf: [
        {
          name: 'threshold'
          metricNamespace: rule.metricNamespace
          metricName: rule.metricName
          timeAggregation: rule.aggregation
          operator: rule.operator
          threshold: rule.threshold
          criterionType: 'StaticThresholdCriterion'
          skipMetricValidation: false
        }
      ]
    }
    actions: [for id in actionGroupIds: { actionGroupId: id }]
  }
}]

resource logAlerts 'Microsoft.Insights/scheduledQueryRules@2023-12-01' = [for rule in logRules: {
  name: rule.name
  location: rule.location
  tags: tags
  kind: 'LogAlert'
  properties: {
    displayName: rule.name
    description: rule.description
    enabled: activate && rule.enabled
    severity: rule.severity
    scopes: [ rule.workspaceId ]
    evaluationFrequency: rule.evaluationFrequency
    windowSize: rule.windowSize
    autoMitigate: true
    skipQueryValidation: false
    criteria: {
      allOf: [
        {
          query: rule.query
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: rule.threshold
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: { actionGroups: actionGroupIds }
  }
}]

output activityAlertIds array = [for (rule, i) in activityRules: activityAlerts[i].id]
output metricAlertIds array = [for (rule, i) in metricRules: metricAlerts[i].id]
output logAlertIds array = [for (rule, i) in logRules: logAlerts[i].id]
