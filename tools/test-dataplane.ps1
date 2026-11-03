<#
.SYNOPSIS
  Offline regression checks for Apply-DataPlane.ps1. No Azure connection or test framework required.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$data = Join-Path $root 'infra/sre-agent/dataplane'
$apply = Join-Path $data 'Apply-DataPlane.ps1'
$legacy = Get-Content "$data/response-plans.json" -Raw | ConvertFrom-Json
$events = Get-Content "$data/event-response-plans.json" -Raw | ConvertFrom-Json
$tasks = Get-Content "$data/scheduled-tasks.json" -Raw | ConvertFrom-Json
$temp = [IO.Path]::GetTempFileName()
$global:SreDataPlaneTest = @{
    writes = [Collections.Generic.List[object]]::new()
    existing = @()
    failName = ''
    invalidList = $false
}

function Assert($Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
}

function az {
    $global:LASTEXITCODE = 0
    if ($args[0] -eq 'rest') { return 'https://example.invalid' }
    return 'offline-test-token'
}

function Invoke-RestMethod {
    param($TimeoutSec, $Uri, $Method, $Headers, $ContentType, $Body)
    if (-not $Method) {
        if ($global:SreDataPlaneTest.invalidList) { return [pscustomobject]@{ unexpected = @() } }
        return [pscustomobject]@{ value = $global:SreDataPlaneTest.existing }
    }
    $item = [Text.Encoding]::UTF8.GetString($Body) | ConvertFrom-Json
    $global:SreDataPlaneTest.writes.Add($item)
    if ($item.name -eq $global:SreDataPlaneTest.failName) { throw 'Injected PUT failure' }
}

function Run-Apply([hashtable]$Options = @{}, [string]$ExpectedError = '') {
    $global:SreDataPlaneTest.writes.Clear()
    $params = @{
        SubscriptionId = 'offline'
        ResourceGroup = 'offline'
        AgentName = 'offline'
        TenantId = 'offline'
        SkipKnowledge = $true
        KitRoot = $root
    }
    foreach ($key in $Options.Keys) { $params[$key] = $Options[$key] }
    $caught = ''
    try { & $apply @params | Out-Null } catch { $caught = $_.Exception.Message }
    if ($ExpectedError) {
        Assert ($caught -like "*$ExpectedError*") "Expected '$ExpectedError', got '$caught'."
    } else {
        Assert (-not $caught) "Unexpected failure: $caught"
    }
}

try {
    $agentNames = (Get-Content "$data/subagents.json" -Raw | ConvertFrom-Json).subagents.name
    foreach ($p in $events.responsePlans) {
        Assert ($p.handlingAgent -in $agentNames) "Unknown agent for $($p.name)"
    }
    $sourceRules = (Get-Content "$root/infra/sre-agent/event-alerts.json" -Raw | ConvertFrom-Json).activityRules
    foreach ($rule in $sourceRules) {
        $matches = @($events.responsePlans | Where-Object { $rule.name.Contains($_.titleContains) })
        Assert ($matches.Count -eq 1) "Ambiguous or missing route for $($rule.name)"
    }
    $operations = @($sourceRules | ForEach-Object {
        $rule = $_
        $_.operations | ForEach-Object { "$($rule.category)|$($rule.status)|$_" }
    })
    Assert (@($operations | Group-Object | Where-Object Count -gt 1).Count -eq 0) 'Overlapping starter operations'

    Run-Apply
    $writtenTasks = @($global:SreDataPlaneTest.writes | Where-Object type -eq 'ScheduledTask')
    Assert ($writtenTasks.Count -eq 8) 'Default apply must preserve eight legacy tasks'
    Assert (@($global:SreDataPlaneTest.writes | Where-Object { $_.properties.agentMode -and $_.properties.agentMode -ne 'Review' }).Count -eq 0) 'Non-Review mode'

    $tasks.scheduledTasks[0].isEnabled = $false
    $tasks | ConvertTo-Json -Depth 20 | Set-Content $temp
    Run-Apply @{ ScheduledTasksFile = $temp } 'ConfirmScheduleCutover'
    Assert ($global:SreDataPlaneTest.writes.Count -eq 0) 'Unconfirmed cutover performed writes'

    $global:SreDataPlaneTest.existing = @($legacy.responsePlans | ForEach-Object {
        [pscustomobject]@{ name = $_.name; properties = @{ isEnabled = $true } }
    })
    Run-Apply @{ UseEventDrivenResponsePlans = $true; ScheduledTasksFile = $temp; ConfirmScheduleCutover = $true }
    $plans = @($global:SreDataPlaneTest.writes | Where-Object type -eq 'IncidentFilter')
    Assert (@($plans | Where-Object { $_.name -in $events.responsePlans.name -and $_.properties.isEnabled }).Count -eq 17) 'Event routes not enabled'
    Assert (@($plans | Where-Object { $_.name -in $legacy.responsePlans.name -and -not $_.properties.isEnabled }).Count -eq 8) 'Legacy routes not retired'
    $persisted = $global:SreDataPlaneTest.writes | Where-Object { $_.name -eq $tasks.scheduledTasks[0].name }
    Assert ($persisted.properties.isEnabled -eq $false) 'Disabled schedule was re-enabled'

    $global:SreDataPlaneTest.failName = $events.responsePlans[0].name
    Run-Apply @{ UseEventDrivenResponsePlans = $true } 'data-plane item(s) failed'
    Assert (@($global:SreDataPlaneTest.writes | Where-Object type -eq 'ScheduledTask').Count -eq 0) 'Schedule changed after route failure'
    Assert (@($global:SreDataPlaneTest.writes | Where-Object { $_.type -eq 'IncidentFilter' -and -not $_.properties.isEnabled }).Count -eq 0) 'Legacy route retired after route failure'
    $global:SreDataPlaneTest.failName = ''

    $global:SreDataPlaneTest.existing = @([pscustomobject]@{ name = 'quickstart'; properties = @{ isEnabled = $true } })
    Run-Apply @{ UseEventDrivenResponsePlans = $true } 'overlapping response plans'
    Assert ($global:SreDataPlaneTest.writes.Count -eq 0) 'Unmanaged route did not block migration'

    $global:SreDataPlaneTest.existing = @($events.responsePlans | ForEach-Object {
        [pscustomobject]@{ name = $_.name; properties = @{ isEnabled = $true } }
    })
    Run-Apply @{} 'Event-driven routing already exists'
    Assert ($global:SreDataPlaneTest.writes.Count -eq 0) 'Default apply reverted event routing'
    Run-Apply @{ RestoreLegacyResponsePlans = $true }
    Assert (@($global:SreDataPlaneTest.writes | Where-Object { $_.name -in $events.responsePlans.name -and -not $_.properties.isEnabled }).Count -eq 17) 'Explicit rollback did not retire event routes'

    $global:SreDataPlaneTest.invalidList = $true
    Run-Apply @{ UseEventDrivenResponsePlans = $true } 'Unexpected incident-filter list response'
    Assert ($global:SreDataPlaneTest.writes.Count -eq 0) 'Malformed inventory allowed writes'
    $global:SreDataPlaneTest.invalidList = $false
    Run-Apply @{ UseEventDrivenResponsePlans = $true; RestoreLegacyResponsePlans = $true } 'not both'
    Assert ($global:SreDataPlaneTest.writes.Count -eq 0) 'Conflicting routing flags allowed writes'
    Write-Host 'PASS: routing, Review mode, schedule persistence, cutover guards, failure handling and explicit rollback.'
} finally {
    Remove-Item -LiteralPath $temp
    Remove-Variable -Name SreDataPlaneTest -Scope Global
}
