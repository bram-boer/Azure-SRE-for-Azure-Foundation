<#
.SYNOPSIS
  Applies the starter-kit data-plane configuration (custom agents, scheduled tasks, response plans, knowledge) to a deployed Azure SRE Agent.
.DESCRIPTION
  Idempotent PUTs against the agent data plane, following the route shapes used by the official templates
  (https://github.com/microsoft/sre-agent, sreagent-templates/bicep/Apply-Extras.ps1).
  Requires a data-plane token. If it fails with a claims challenge, sign in once with:
    az login --tenant <tenantId> --scope "https://azuresre.dev/.default"
.EXAMPLE
  .\Apply-DataPlane.ps1 -SubscriptionId <subId> -ResourceGroup rg-platform-sreagent -AgentName sre-platform-ops -TenantId <tenantId>
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SubscriptionId,
    [Parameter(Mandatory)] [string] $ResourceGroup,
    [Parameter(Mandatory)] [string] $AgentName,
    [Parameter(Mandatory)] [string] $TenantId,
    [string] $KitRoot = (Resolve-Path "$PSScriptRoot\..\..\..").Path,
    [switch] $SkipKnowledge,
    [switch] $UseEventDrivenResponsePlans,
    [switch] $RestoreLegacyResponsePlans,
    [string] $ScheduledTasksFile = "$PSScriptRoot\scheduled-tasks.json",
    [switch] $ConfirmScheduleCutover
)
$ErrorActionPreference = 'Stop'

if ($UseEventDrivenResponsePlans -and $RestoreLegacyResponsePlans) {
    throw 'Select event-driven routing or explicit legacy rollback, not both.'
}
$st = Get-Content $ScheduledTasksFile -Raw | ConvertFrom-Json
foreach ($t in $st.scheduledTasks) {
    if ($t.isEnabled -isnot [bool]) { throw "Task '$($t.name)' must declare a boolean isEnabled." }
}
if (@($st.scheduledTasks | Where-Object { -not $_.isEnabled }).Count -and -not $ConfirmScheduleCutover) {
    throw 'Disabled schedules require -ConfirmScheduleCutover after owner acceptance of replacement detection, including freshness/deadline coverage.'
}
$legacyPlans = Get-Content "$PSScriptRoot\response-plans.json" -Raw | ConvertFrom-Json
$eventPlans = Get-Content "$PSScriptRoot\event-response-plans.json" -Raw | ConvertFrom-Json
$rp = if ($UseEventDrivenResponsePlans) { $eventPlans } else { $legacyPlans }
$inactivePlans = if ($UseEventDrivenResponsePlans) { $legacyPlans } else { $eventPlans }
$sa = Get-Content "$PSScriptRoot\subagents.json" -Raw | ConvertFrom-Json
foreach ($p in $rp.responsePlans) {
    if ($p.handlingAgent -notin $sa.subagents.name) { throw "Unknown handling agent '$($p.handlingAgent)'." }
}

$agentUrl = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.App/agents/${AgentName}?api-version=2025-05-01-preview"
$endpoint = az rest --method get --url $agentUrl --query properties.agentEndpoint -o tsv
if (-not $endpoint) { throw "Agent endpoint not found for $AgentName." }
$token = az account get-access-token --resource https://azuresre.dev --tenant $TenantId --query accessToken -o tsv
if ($LASTEXITCODE -ne 0 -or -not $token) { throw "No data-plane token. Run: az login --tenant $TenantId --scope `"https://azuresre.dev/.default`"" }
$headers = @{ Authorization = "Bearer $token" }
$failures = [System.Collections.Generic.List[string]]::new()

$planList = Invoke-RestMethod -TimeoutSec 60 -Uri "$endpoint/api/v2/extendedAgent/incidentFilters" -Headers $headers
if ($null -eq $planList -or 'value' -notin $planList.PSObject.Properties.Name) {
    throw 'Unexpected incident-filter list response; refusing to change routing without an inventory.'
}
$existing = @($planList.value)
$known = @($legacyPlans.responsePlans.name) + @($eventPlans.responsePlans.name)
$unmanaged = @($existing | Where-Object { $_.name -notin $known -and $_.properties.isEnabled -ne $false })
if ($UseEventDrivenResponsePlans -and $unmanaged.Count) {
    throw "Disable or explicitly manage these potentially overlapping response plans before migration: $($unmanaged.name -join ', ')."
}
if (-not $UseEventDrivenResponsePlans -and -not $RestoreLegacyResponsePlans -and
    @($existing | Where-Object { $_.name -in $eventPlans.responsePlans.name -and $_.properties.isEnabled -ne $false }).Count) {
    throw 'Event-driven routing already exists. Reapply with -UseEventDrivenResponsePlans, or explicitly roll back with -RestoreLegacyResponsePlans.'
}

function Put-Extended([string]$Kind, [string]$Name, [string]$Type, [hashtable]$Properties) {
    $body = @{ name = $Name; type = $Type; tags = @(); properties = $Properties } | ConvertTo-Json -Depth 20 -Compress
    $url = "$endpoint/api/v2/extendedAgent/$Kind/$([uri]::EscapeDataString($Name))"
    try {
        $null = Invoke-RestMethod -TimeoutSec 60 -Uri $url -Method Put -Headers $headers -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes($body))
        Write-Host "  ok $Kind/$Name"
    } catch {
        $failures.Add("$Kind/$Name - $($_.Exception.Message) $($_.ErrorDetails.Message)")
        Write-Host "  FAILED $Kind/$Name - $($_.Exception.Message)" -ForegroundColor Red
    }
}

# 1. Custom agents. Hand-offs are not supported in workspace mode; the orchestrator delegates via Task-based subagents.
$ordered = @($sa.subagents)
Write-Host "custom agents: $($ordered.Count)"
foreach ($a in $ordered) {
    Put-Extended -Kind 'agents' -Name $a.name -Type 'ExtendedAgent' -Properties @{
        instructions       = "$($a.instructions)`n`n$($sa.commonRules)`n`nEvent-driven investigations: follow event-driven-triggers.md. Focus on the affected resources and approved event window, not a full estate scan. Log connectors are evidence sources, not triggers. Verify actor principal IDs and deployment correlation before calling a change out-of-band; portal/CLI labels alone are insufficient. Mark incomplete post-deployment windows as pending, not healthy. Delegate W3 cost evidence to finops and W5 AI/AKS evidence to the domain specialists. A resolved Monitor signal is not human-confirmed incident closure."
        handoffDescription = $a.handoffDescription
        handoffs           = @($a.handoffs)
        tools              = @($sa.tools)
    }
}

# 2. Response plans. Activate selected routes before retiring known alternative routes.
Write-Host "response plans: $($rp.responsePlans.Count)"
foreach ($p in $rp.responsePlans) {
    $props = @{}
    $rp.defaults.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
    $props.agentMode = 'Review'
    $props.handlingAgent = $p.handlingAgent
    if ($p.titleContains) { $props.titleContains = $p.titleContains }
    if ($p.targetResourceType) { $props.azMonitorFilterSettings = @{ targetResourceType = $p.targetResourceType } }
    Put-Extended -Kind 'incidentFilters' -Name $p.name -Type 'IncidentFilter' -Properties $props
}
if (-not $failures.Count) {
    foreach ($p in $inactivePlans.responsePlans | Where-Object { $_.name -in $existing.name }) {
        $props = @{}
        $inactivePlans.defaults.PSObject.Properties | ForEach-Object { $props[$_.Name] = $_.Value }
        $props.agentMode = 'Review'
        $props.handlingAgent = $p.handlingAgent
        $props.isEnabled = $false
        if ($p.titleContains) { $props.titleContains = $p.titleContains }
        if ($p.targetResourceType) { $props.azMonitorFilterSettings = @{ targetResourceType = $p.targetResourceType } }
        Put-Extended -Kind 'incidentFilters' -Name $p.name -Type 'IncidentFilter' -Properties $props
    }
}
foreach ($e in $unmanaged) {
    Write-Host "  WARNING unmanaged response plan '$($e.name)' (e.g. auto-created quickstart) can double-route incidents; review or delete it in Builder > Incident response plans." -ForegroundColor Yellow
}

# 3. Knowledge files (Knowledge Sources). Contain no secrets or customer names.
if (-not $SkipKnowledge) {
    $files = @(
        @{ name = 'use-cases.md';             path = "$KitRoot\use-cases.md" },
        @{ name = 'waf-pillar-use-cases.md';  path = "$KitRoot\waf-pillar-use-cases.md" },
        @{ name = 'agent-topology.md';        path = "$KitRoot\agent-topology.md" },
        @{ name = 'event-driven-triggers.md'; path = "$KitRoot\event-driven-triggers.md" },
        @{ name = 'starter-queries.md';       path = "$KitRoot\queries\starter-queries.kql"; wrap = $true }
    )
    Write-Host "knowledge: $($files.Count)"
    foreach ($f in $files) {
        $content = Get-Content $f.path -Raw -Encoding utf8
        if ($f.wrap) { $content = "# Validated starter queries (Azure Resource Graph / KQL)`n`n``````kusto`n$content`n``````" }
        $id = ($f.name.ToLower() -replace '[^a-z0-9-]', '-') -replace '-+', '-' -replace '^-|-$', ''
        Put-Extended -Kind 'connectors' -Name $id -Type 'KnowledgeItem' -Properties @{
            dataConnectorType  = 'KnowledgeFile'
            dataSource         = $id
            extendedProperties = @{
                displayName = $f.name
                fileName    = $f.name
                fileContent = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
                contentType = 'text/markdown'
            }
        }
    }
}

# 4. Apply persisted schedule flags only after all replacement configuration succeeded.
if (-not $failures.Count) {
    Write-Host "scheduled tasks: $($st.scheduledTasks.Count)"
    foreach ($t in $st.scheduledTasks) {
        Put-Extended -Kind 'scheduledtasks' -Name $t.name -Type 'ScheduledTask' -Properties @{
            name           = $t.name
            description    = $t.description
            cronExpression = $t.cron
            agentPrompt    = $t.prompt
            agent          = $t.agent
            agentMode      = 'Review'
            isEnabled      = $t.isEnabled
        }
    }
}
if ($failures.Count) {
    $failures | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "$($failures.Count) data-plane item(s) failed. No schedule updates were attempted after earlier configuration failures; inspect partial updates before retrying."
}
Write-Host "`nAll data-plane items applied." -ForegroundColor Green
