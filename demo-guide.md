# Demo guide - the starter kit in practice

**Reference date: 20-10-2026.** This is a scripted demo path for the reference deployment in [infra\sre-agent\README.md](infra/sre-agent/README.md). Each demo states the **action** that triggers the agent, the **expected behaviour** and **how the agent should solve it**. The demos cover the five WAF pillars and the ALZ platform (AMBA alerts, management-group guardrails, vending readiness, AKS).

> Run these only in a sandbox or non-production subscription, with the agent in **Review** mode. Every incident investigation and every task run consumes Azure Agent Units (AAU) against the 2,000 AAU monthly cap. All Azure demo resources go into one throwaway resource group, `rg-sre-demo`, which you delete at the end. The one exception is demo 5, which deploys a uniquely named namespace into an existing non-production AKS cluster; deleting `rg-sre-demo` does not remove it, so clean it up separately.

## How the agent "solves" in this kit

The reference agent's Bicep assigns subscription **Reader** only (check for an auto-added **Monitoring Contributor**, see demo 0), with access level Low and **Review** mode. So "solving" means:

1. **Detect.** An alert arrives through a response plan, or a scheduled task runs.
2. **Investigate.** The agent correlates the Activity Log, Resource Graph `resourcechanges`, metrics, logs and knowledge files.
3. **Explain.** It reports the cause, the impact, the WAF checklist code and the owner.
4. **Propose.** It suggests a fix: an IaC change, a CLI command or a policy assignment.
5. **Human decision.** A person applies the fix through the normal change and pipeline process.

The agent cannot change resources. Demo 9 shows the optional approval flow, where you grant temporary write access to the demo resource group only.

## Demo map

| # | Demo | Trigger | Path in the agent | Framework | Duration |
|---|---|---|---|---|---|
| 0 | Alert-intake smoke test | Regenerate a workspace key (AMBA alert) | `rp-log-analytics` > observability | ALZ AMBA, WAF SE | 10 min |
| 1 | Outside the ALZ guardrails | Chat prompt | vending-governance | ALZ / CAF Govern, UC02 | 5 min |
| 2 | Security drift | Create insecure resources, then **Run now** `w2-security-drift-daily` | waf-security | WAF Security (W2) | 10 min |
| 3 | Out-of-band change | Portal change, then **Run now** `w4-out-of-band-changes-daily` | waf-opex | WAF Operational Excellence (W4), UC04 | 10 min |
| 4 | Resource Health incident | Deallocate a demo VM (AMBA alert) | `rp-resource-health` > waf-reliability | WAF Reliability (W1), UC10 | 15 min |
| 5 | AKS CPU saturation | CPU stress pods (metric alert) | `rp-aks-platform` > aks-platform | AKS accelerator, UC08, UC05 | 20 min |
| 6 | Capacity headroom | **Run now** `w5-capacity-headroom-weekly` after demo 5 | waf-performance | WAF Performance Efficiency (W5) | 5 min |
| 7 | Cost waste | Orphaned disk and public IP, then **Run now** `w3-cost-waste-weekly` | waf-cost | WAF Cost Optimization (W3), UC11 | 5 min |
| 8 | Close the loop | **Run now** `uc12-incident-to-waf-monthly` | platform-orchestrator | UC12, CCoE backlog | 5 min |
| 9 | Optional: approve a fix | Temporary Contributor on `rg-sre-demo` | Review-mode approval | WAF OE, change control | 10 min |

**Suggested 60-minute storyline:**

| Audience | Demos | Message |
|---|---|---|
| CCoE | 1, 2, 3 | Guardrail and drift visibility |
| Platform team | 0, 4, 5 | Incident triage on existing AMBA alerts |
| Platform team and CCoE | 6, 7, 8 | Proactive capacity, cost and an improvement backlog |

## Preparation (once)

```powershell
$sub = '<subscription-id>'; $loc = 'swedencentral'; $rg = 'rg-sre-demo'
az account set --subscription $sub
az group create -n $rg -l $loc --tags purpose=sre-demo owner=<your-alias> costCenter=<cc> -o none
```

Checks before the audience arrives:

| Check | Where |
|---|---|
| Agent is **Running** | `https://sre.azure.com` |
| Incident platform shows **Azure Monitor** | **Builder > Incident platform** |
| The 8 response plans are enabled in Review mode, and there is **no** `quickstart` plan | **Incidents > Triggers + response plans** |
| The 8 scheduled tasks exist | **Automation**. For each demo, select the task and choose **Run now**. |

---

## Demo 0 - Alert-intake smoke test (ALZ AMBA, WAF Security)

**Purpose:** prove the full chain end to end: AMBA alert, then Azure Monitor, then response plan, then custom agent. Run this first. If it fails, fix intake before running the other alert demos.

**Action**

```powershell
az monitor log-analytics workspace create -g $rg -n law-sre-demo -l $loc -o none
$ws = az monitor log-analytics workspace show -g $rg -n law-sre-demo --query id -o tsv
az rest --method post --url "https://management.azure.com$ws/regenerateSharedKey?api-version=2020-08-01" -o none
```

**What fires:** the AMBA activity-log alert `ActivityLAWorkspaceRegenKey`, at subscription scope. Its target resource type is `Microsoft.OperationalInsights/workspaces`, so it matches the `rp-log-analytics` response plan.

**Expected behaviour (within about 5 minutes; the scanner runs every minute)**

- An incident thread appears under **Incidents**. The rich card shows the severity, the alert title and the `rp-log-analytics` response plan.
- The **observability** custom agent investigates:
  - who regenerated the key (Activity Log `caller`), when, and from which client
  - whether the workspace is a central ALZ workspace or a demo workspace
  - which agents or data sources still depend on shared-key ingestion, such as the legacy Log Analytics agent

**How the agent should solve it**

- Classify the event as a planned demo action by a known user. There is no compromise indicator.
- Recommend controls:
  - disable local authentication on workspaces and ingest only through Azure Monitor Agent with data collection rules (WAF **SE:05**, identity and access)
  - rotate keys only through a pipeline
  - keep the AMBA rule
- Propose the IaC change, such as `features.disableLocalAuth: true` on the workspace, for a human to apply.

**If no thread appears after 10 minutes:**

1. Confirm that the alert fired in **Monitor > Alerts**.
2. Check that the plan is enabled.
3. Check the agent identities' effective roles: `az role assignment list --assignee-object-id <principal-id> --all`. The Learn troubleshooting note says the managed identity may need **Monitoring Contributor** on the subscription for alert intake. The kit's Bicep assigns Reader only, but setting the incident platform can add Monitoring Contributor automatically, as it did in the reference sandbox. If it is missing, decide whether to grant it, which also lets the agent acknowledge and close alerts and edit alert rules, or a custom role limited to `Microsoft.AlertsManagement/alerts/*`. Record either way as an access change.

---

## Demo 1 - Outside the ALZ guardrails (CAF Govern, UC02)

**Purpose:** show that the agent can assess a subscription against the ALZ baseline, which is what you need right after subscription vending.

**Action:** ask the agent in chat, or invoke the `vending-governance` custom agent in the **Test playground**:

> Assess subscription `<subscription-id>` for landing-zone readiness. Report its management-group placement and ancestry, the policy assignments that apply (inherited and direct), Defender for Cloud plans, diagnostic settings for the Activity Log, required tags and a budget. Compare against the Azure landing zone baseline and list gaps with owners.

**Expected behaviour:** the agent reads Resource Graph (`resourcecontainers`, `policyresources`) and the Activity Log configuration. In the reference sandbox on 20-10-2026, the subscription sits in the **`<platform-management-mg>`** management group, under `<platform-mg>` and `<root-mg>`. However, **no ALZ policy assignments are inherited from the management groups**: only Defender for Cloud subscription assignments apply.

**How the agent should solve it**

- Flag "ALZ hierarchy present, guardrails not assigned" as the main governance gap. This is CAF Govern; deny-by-policy is the preventive control that the later demos show missing.
- Propose assigning the ALZ policy set at the management-group level through the ALZ IaC (AVM pattern modules), owned by the CCoE, and not per subscription.
- Note that demos 2 and 3 would be **denied or audited** in a governed landing zone. This contrast is useful for the CCoE audience.

---

## Demo 2 - Security drift (WAF Security, W2)

**Action:** create deliberately weak resources, then run the task.

```powershell
$sa = "stsredemo$((Get-Random -Maximum 99999))"
az storage account create -g $rg -n $sa -l $loc --sku Standard_LRS --allow-blob-public-access true --allow-shared-key-access true --public-network-access Enabled --min-tls-version TLS1_2 -o none
az network nsg create -g $rg -n nsg-sre-demo -l $loc -o none
az network nsg rule create -g $rg --nsg-name nsg-sre-demo -n allow-rdp-internet --priority 100 --access Allow --protocol Tcp --direction Inbound --source-address-prefixes Internet --destination-port-ranges 3389 -o none
```

Then go to **Automation**, select `w2-security-drift-daily` and choose **Run now**.

**Expected behaviour:** the **waf-security** agent reports drift against the security baseline:

- blob public access is allowed and shared-key access is enabled on the storage account
- public network access is open
- RDP (3389) is open from the Internet on `nsg-sre-demo`

Each finding includes evidence (the resource ID, the property and the Resource Graph change record), the WAF Security checklist code (for example **SE:06** network controls and **SE:05** identity and access), the owner, and any Defender for Cloud recommendations that are already raised.

**How the agent should solve it**

- Propose IaC fixes: `allowBlobPublicAccess: false`, `allowSharedKeyAccess: false`, a private endpoint or `publicNetworkAccess: Disabled`, and removing the NSG rule in favour of Azure Bastion.
- Propose the preventive control: assign the matching ALZ policies at the landing-zone management group, for example deny storage public access and deny management ports from the Internet.
- Recommend fixing the policy assignment first (demo 1), rather than each resource.

---

## Demo 3 - Out-of-band change (WAF Operational Excellence, W4, UC04)

**Action:** make a manual portal change outside any pipeline. In the portal, open `nsg-sre-demo` and change the priority of `allow-rdp-internet` to 110. Also add a tag `changedBy=portal` to the storage account. Then run `w4-out-of-band-changes-daily` with **Run now**.

**Expected behaviour:** the **waf-opex** agent queries Resource Graph `resourcechanges` (`changedBy`, `clientType`, `changeType`). It lists the changes made through the **Azure Portal** by a user identity, not by the deployment pipeline's identity. It also lists the CLI-created resources from demo 2 as unmanaged, with no deployment record.

**How the agent should solve it**

- Classify each change as drift from IaC (WAF **OE:05** infrastructure as code, **OE:11** safe deployment).
- Propose either backporting the change into the IaC repository or reverting it through the pipeline.
- Recommend controls: a Deny or Audit policy, or a read-only lock on platform resource groups, plus a post-deployment HTTP trigger from the pipeline (W4 gate).

---

## Demo 4 - Resource Health incident (WAF Reliability, W1, UC10)

**Action:** create a small single-instance VM with no zone and no backup, then deallocate it.

```powershell
az vm create -g $rg -n vm-sre-demo -l $loc --image Ubuntu2204 --size Standard_B1s --admin-username azureuser --generate-ssh-keys --public-ip-address '""' --nsg '""' -o none
az vm deallocate -g $rg -n vm-sre-demo
```

**What fires:** the AMBA rule `ResourceHealthUnhealthyAlert` includes `UserInitiated` events, so the deallocation raises a Resource Health **Unavailable** event. The alert title contains `ResourceHealth`, so it matches `rp-resource-health`, which hands it to **waf-reliability**.

**Expected behaviour:**

- The agent reads the Resource Health event (cause `UserInitiated`) and finds the matching `deallocate` operation and caller in the Activity Log.
- It concludes that there was **no platform fault**.
- It then checks the reliability posture of the resource:
  - single instance, no availability zone and no availability set
  - no Recovery Services or Backup vault protection (UC10)
  - no reliability-tier tag, so the target is unknown (WAF **RE:04**)

**How the agent should solve it**

- Close as expected or planned. In Review mode it only **proposes** closing; it acts on the alert only if it holds Monitoring Contributor and you approve.
- Report the gaps with an IaC proposal: **RE:05** redundancy, and **RE:09** disaster recovery. For RE:09 the gap is a documented, tested recovery plan aligned with recovery targets; backup protection is one required control once those targets are set. Request a reliability tier from the owner.
- **Noise finding (WAF OE):** the AMBA rule alerts on user-initiated events. In this subscription it fired repeatedly for AKS node scale sets up to 18-10-2026. The agent should propose tuning: exclude `UserInitiated`, or scope the rule to platform resources, and let the merge window of 1 hour group repeats.

---

## Demo 5 - AKS CPU saturation (AKS accelerator, UC08, UC05)

**Target:** `<aks-cluster>`, a non-production cluster with one node, no autoscaler and Azure RBAC. It has the metric alert `cpu usage percentage - <aks-cluster>`: average above 95% over 5 minutes, Sev3. Use only a non-production cluster.

> This demo **modifies an existing cluster**. It is not contained in `rg-sre-demo`, so it needs its own cleanup step.

**Action:** generate a unique namespace, confirm that it does not exist yet, write `stress.yaml`, and apply it through AKS run command. No local kubeconfig is needed.

```powershell
$aksRg = '<aks-resource-group>'; $aks = '<aks-cluster>'
$ns = "sre-demo-$(Get-Random -Minimum 1000 -Maximum 9999)"
# Must return NotFound before you continue; otherwise pick another name.
az aks command invoke -g $aksRg -n $aks --command "kubectl get namespace $ns"
@"
apiVersion: v1
kind: Namespace
metadata: { name: $ns, labels: { purpose: sre-demo } }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: cpu-stress, namespace: $ns, labels: { app: cpu-stress, purpose: sre-demo } }
spec:
  replicas: 6
  selector: { matchLabels: { app: cpu-stress } }
  template:
    metadata: { labels: { app: cpu-stress } }
    spec:
      containers:
      - name: burn
        image: mcr.microsoft.com/cbl-mariner/busybox:1.35
        command: ["sh", "-c", "while true; do :; done"]
"@ | Set-Content stress.yaml
az aks command invoke -g $aksRg -n $aks --command "kubectl apply -f stress.yaml" --file stress.yaml
```

Wait 10-15 minutes for the 5-minute evaluation window and scanner pickup.

**Expected behaviour:** the metric alert fires on `Microsoft.ContainerService/managedClusters`, so `rp-aks-platform` hands it to **aks-platform**.

- The agent confirms node CPU saturation from platform metrics.
- It correlates the timing with the run-command operation in the Activity Log.
- It finds that **Container insights is not enabled** on this cluster, so `KubePodInventory` and `KubeEvents` are missing. It reports this as a **monitoring blind spot** (UC05).
- Without an AKS RBAC role, it cannot list pods through Kubernetes Azure RBAC. It should state this limitation rather than guess.

**How the agent should solve it**

- **Immediate proposal for a human:** `kubectl scale deploy cpu-stress -n <namespace> --replicas=0`, or delete the demo namespace.
- **Structural proposals:**
  - enable the cluster autoscaler or add a user node pool, and set CPU requests and limits with a namespace `LimitRange` (WAF **PE:05** scaling, **RE:05**)
  - enable Container insights or managed Prometheus, as in the AKS baseline (UC05)
  - for pod-level evidence, assign the agent **Azure Kubernetes Service RBAC Reader**, which is a separate access decision

**Cleanup:**

```powershell
az aks command invoke -g $aksRg -n $aks --command "kubectl delete namespace $ns"
```

---

## Demo 6 - Capacity headroom (WAF Performance Efficiency, W5)

**Action:** run `w5-capacity-headroom-weekly` with **Run now**, ideally while demo 5 is still running.

**Expected behaviour:** the **waf-performance** agent reports, per limit, the current usage, headroom, threshold (70% warning, 85% critical) and owner. On a first run it should state **"insufficient history"** for trend and projected exhaustion; those need several retained scheduled observations.

- regional vCPU quota (for example, Sweden Central total cores 0 of 100 at preparation time)
- subnet IP usage in the hub and AKS virtual networks
- AKS node CPU headroom: the single node is saturated, with no autoscaler

It classifies the AKS saturation as **demand** (the demo load) on a cluster that lacks **configuration** headroom, not as a quota problem.

**How the agent should solve it:** propose autoscaler bounds and node-pool sizing in IaC (**PE:02** capacity planning, **PE:05**). It does not file quota requests.

---

## Demo 7 - Cost waste (WAF Cost Optimization, W3, UC11)

**Action**

```powershell
az disk create -g $rg -n disk-sre-orphan -l $loc --size-gb 32 --sku Standard_LRS -o none
az network public-ip create -g $rg -n pip-sre-orphan -l $loc --sku Standard -o none
```

Then run `w3-cost-waste-weekly` with **Run now**. The deallocated VM from demo 4 also counts here.

**Expected behaviour:** the **waf-cost** agent lists:

- the unattached managed disk and the unassociated Standard public IP as **orphans**
- the disks of the deallocated VM as **continuing cost requiring owner review**, not orphans: the VM still needs them to restart
- resources in AKS node resource groups (`MC_*`) **excluded** from orphan recommendations, because AKS may manage them; at most it flags them for AKS-owner validation

For each, it gives an estimated monthly EUR cost from retail prices and the age. Resource-group tags are not inherited automatically, so it reports **missing `owner` and `costCenter` tags** on the new resources rather than inventing an owner.

**How the agent should solve it**

- Propose deletion or right-sizing as a change ticket or IaC removal. It does not delete anything.
- Propose a tagging policy (Modify or inherit tags) and budgets per landing zone (WAF **CO:03** cost data, **CO:07** component costs).
- Show the agent's own cost line so FinOps sees the full picture.

---

## Demo 8 - Close the loop (UC12)

**Action:** run `uc12-incident-to-waf-monthly` with **Run now** after the other demos.

**Expected behaviour:** the **platform-orchestrator** collects the demo incidents and task threads. It maps each one to:

- a WAF pillar and checklist code (SE, OE, RE, PE, CO)
- the platform control that would have prevented it
- a proposed reusable standard

**How the agent should solve it:** produce a prioritized **CCoE backlog**, for example:

1. Assign the ALZ policy set at the management groups.
2. Disable workspace local authentication.
3. Tune the AMBA Resource Health rule.
4. Enable AKS autoscaler and Container insights in the AKS accelerator parameters.
5. Add tag inheritance and budgets to subscription vending.

This is the CCoE benefit: one recurring, evidence-linked improvement list instead of scattered incident notes.

---

## Demo 9 - Optional: approve a proposed fix (Review mode)

Run this only to show the approval flow, with the access change recorded. You need Owner, User Access Administrator or Role Based Access Control Administrator on `rg-sre-demo` to assign the role. Role assignments can take several minutes to propagate.

```powershell
# Grant only the user-assigned identity the agent uses for Azure actions (actionConfiguration.identity), scoped to the demo RG.
$scope = az group show -n $rg --query id -o tsv
$mi = az identity show -g rg-platform-sreagent -n id-sre-platform-ops --query principalId -o tsv
az role assignment create --assignee-object-id $mi --assignee-principal-type ServicePrincipal --role Contributor --scope $scope -o none
```

In the demo 2 thread, ask: *"Change the allow-rdp-internet rule on nsg-sre-demo to Deny."*

> The SRE Agent blocks all `delete` and `remove` commands, whatever its RBAC or approval. Demo deletions such as `disk-sre-orphan` stay a manual or IaC step.

**Expected behaviour:**

- The agent proposes the exact command, for example `az network nsg rule update -g rg-sre-demo --nsg-name nsg-sre-demo -n allow-rdp-internet --access Deny`, and shows **Approve** and **Deny**.
- After approval, it runs it only within `rg-sre-demo` and verifies the result.
- The action is logged as `AgentAzCliExecution` in the agent's Application Insights.
- An attempt against any other resource group fails on RBAC. This is a useful negative test.

**Afterwards:** remove the role assignment.

```powershell
az role assignment delete --assignee-object-id $mi --role Contributor --scope $scope
```

---

## Cleanup

```powershell
# $aksRg, $aks and $ns come from demo 5; skip this line if you did not run it.
az aks command invoke -g $aksRg -n $aks --command "kubectl delete namespace $ns --ignore-not-found"
az group delete -n rg-sre-demo --yes --no-wait
```

Deleting `law-sre-demo` as part of the resource group fires the AMBA `ActivityLAWorkspaceDelete` alert. That gives a final `rp-log-analytics` thread, which you can use as a closing example, or ignore. Review the AAU consumption on the agent's **Monitor** page after the session.

## Success criteria for the demo

| Criterion | Evidence |
|---|---|
| Alerts reach the right custom agent | Thread shows the expected response plan (demos 0, 4, 5) |
| Findings cite evidence, not guesses | Resource IDs, Activity Log callers, change records, metrics |
| Limits are stated | No Container insights, no Kubernetes RBAC, effective roles as recorded |
| No unapproved change | No `AgentAzCliExecution` events, except in demo 9 after approval |
| CCoE output | UC12 backlog with WAF codes and owners |
| Cost stays within plan | AAU consumption on the **Monitor** page within the cap |
