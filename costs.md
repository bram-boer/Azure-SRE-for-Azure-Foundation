# Cost model and pilot business case

**Public retail snapshot: 20-10-2026.** Indicative consumption estimates, not a contractual quote. Prices exclude VAT, agreement discounts, support, monitoring, networking, ITSM, pipelines, AKS, AI/model services, and staff. A price meter's existence is **not** proof that a region/model combination is available or satisfies residency requirements.

## Verified inputs

Microsoft documents a fixed **4 Azure Agent Units (AAU) per agent-hour** plus token-metered active flow. Always-on charges continue while the agent exists, including when it is stopped or its active-flow allocation is exhausted. Source: [pricing and billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing).

The static [public pricing page](https://azure.microsoft.com/en-us/pricing/details/sre-agent/) returned `$-` placeholders. The public Azure Retail Prices API **did return concrete SRE rates**, under `serviceName = Foundry Tools`, `productName = Azure Agent Unit`, `skuName = SRE`, `meterName = SRE Agent Unit`, unit `1`, consumption:

| Meter region | EUR / AAU | USD / AAU | Effective from | Meter ID |
|---|---:|---:|---|---|
| West Europe | EUR 0.1197 | USD 0.1360 | 01-10-2026 | `c3f2b2bb-8469-569f-8da9-f2cc2d24faa0` |
| France Central | EUR 0.0968 | USD 0.1100 | 01-07-2026 | `4fd357fd-bd40-5df2-b636-2b63258d52e9` |

These are independently returned EUR and USD retail prices, **not a currency conversion estimated by this kit**. Searching only `serviceName` for "SRE" returned no results; do not interpret that as a free or unpriced service.

Reproduce with these public, unauthenticated queries:

- [EUR SRE meters](https://prices.azure.com/api/retail/prices?currencyCode=%27EUR%27&$filter=productName%20eq%20%27Azure%20Agent%20Unit%27%20and%20skuName%20eq%20%27SRE%27%20and%20%28armRegionName%20eq%20%27westeurope%27%20or%20armRegionName%20eq%20%27francecentral%27%29)
- [USD SRE meters](https://prices.azure.com/api/retail/prices?currencyCode=%27USD%27&$filter=productName%20eq%20%27Azure%20Agent%20Unit%27%20and%20skuName%20eq%20%27SRE%27%20and%20%28armRegionName%20eq%20%27westeurope%27%20or%20armRegionName%20eq%20%27francecentral%27%29)
- [Retail Prices API documentation](https://learn.microsoft.com/en-us/rest/api/cost-management/retail-prices/azure-retail-prices)

## Illustrative one-agent month

Assumptions: 730 provisioned hours; 30 investigations; 100 quick questions; no other tasks, triggers, retries, or remediation; no trial discount. Investigation and quick-question token counts are the **illustrative scenarios** in the billing documentation, not measured expectations for this platform.

For GPT 5.3 Codex / GPT 5.2's documented rate:

```text
Always-on AAU = 730 * 4 = 2,920
Investigation AAU = 0.200*35 + 0.015*280 + 0.150*3.5 + 0.050*0 = 11.725
Quick-question AAU = 0.020*35 + 0.002*280 + 0.015*3.5 + 0.005*0 = 1.3125
Active AAU = 30*11.725 + 100*1.3125 = 483
Monthly AAU = 2,920 + 483 = 3,403
```

The documentation's scenario table rounds the AAUs. This calculation uses the unrounded published token rates. Model availability and provider selection must be verified in the target agent.

| Scenario | Monthly AAU | West Europe | France Central |
|---|---:|---:|---:|
| Always-on only | 2,920 | EUR 349.52 / USD 397.12 | EUR 282.66 / USD 321.20 |
| Illustrative GPT-rate month | 3,403 | EUR 407.34 / USD 462.81 | EUR 329.41 / USD 374.33 |
| Same token volumes, documented Opus 4.6 rates | 4,355 | EUR 521.29 / USD 592.28 | EUR 421.56 / USD 479.05 |

**Agent-only pilot ballpark: approximately EUR 330-522/month** for the specified activity and these two retail regions. This is **not total platform cost**. Do not pick a provider or region solely on token price: investigation quality, number of tool calls, availability, and approved processing geography matter.

```text
Total incremental EUR/month =
  agent AAU * verified regional EUR/AAU
  + extra ingestion GB * regional ingestion EUR/GB
  + billable retention/query/export/Prometheus/alert charges
  + private endpoints/network transfer/automation/ITSM
  + incremental pilot AKS/AI test capacity
```

Reuse ALZ monitoring where authorized; do not treat sunk platform cost as free incremental telemetry. Insert real regional calculator/agreement inputs for the excluded terms before approving a total budget.

## Reference deployment region and cap (20-10-2026)

The reference deployment (`infra\sre-agent`) uses **Sweden Central**. At deployment time, the `Microsoft.App/agents` resource provider did **not** offer West Europe for this subscription, even though a West Europe price meter exists. EU-relevant monthly always-on prices (2,920 AAU) from the Retail Prices API:

| Regions | Always-on EUR / month |
|---|---:|
| Sweden Central, Poland Central, France Central, UK South, Italy North | EUR 282.66 |
| Spain Central, Switzerland North | EUR 303.10 |
| UK West | EUR 326.46 |

Sweden Central was chosen because it is in the lowest tier, is an EU region, and sits next to the existing management and AMBA resources. The active flow is capped with `monthlyAgentUnitLimit = 2000` (about EUR 194). That gives a **maximum of about EUR 477 per month** for the agent alone. Each scheduled task run and each response-plan investigation consumes active AAU. Response plans merge related alerts within 1 hour and allow at most 2 attempts. Only deleting the resource group stops the always-on charge.

## Controls and commercial uncertainty

In **Settings > Agent consumption**, configure an approved monthly active-flow AAU allocation. The billing documentation describes an allocation range of 500-1,000,000 AAUs; hitting the active-flow limit makes chat/actions unavailable while always-on billing continues. Revalidate current portal behavior before relying on it. A Cost Management budget alert is not this product allocation and is not an automatic spending cap.

Keep the normal human incident process operational if the allocation is exhausted. Start with one trust-boundary-scoped pilot agent, narrow response-plan filters, and bounded investigations; avoid one agent per subscription without justification. Stopping the agent does not remove fixed cost. Deletion stops fixed cost but needs approved retention/export and decommissioning procedures.

**Trial conflict:** the Learn evaluation/billing guidance describes an evaluation waiver for always-on charges, while the fetched public pricing FAQ states that free/trial/Dev/Test AAUs are unavailable. Budget at normal retail unless eligibility and the actual waiver are explicitly confirmed in the tenant and applicable commercial terms. Sources: [evaluation](https://learn.microsoft.com/en-us/azure/sre-agent/evaluate), [billing](https://learn.microsoft.com/en-us/azure/sre-agent/pricing-billing), [public pricing FAQ](https://azure.microsoft.com/en-us/pricing/details/sre-agent/).

## Business-case worksheet

Treat benefits as testable hypotheses. Compare equivalent incident classes and complexity; do not attribute changes in incident mix to the agent.

```text
Monthly labor capacity released =
  comparable incidents * (baseline responder minutes - pilot responder minutes) / 60

Indicative labor value in EUR =
  capacity released * internally approved loaded hourly EUR rate

Net financial benefit =
  realized/accepted labor value + demonstrable avoided cost
  - incremental service cost - setup/maintenance cost
```

Also track evidence accuracy, unauthorized actions (target zero), data-boundary violations (target zero), recurrence, handover quality, and responder trust. Faster explanations without accurate evidence or safer recovery are not success. Released engineering capacity is not automatically a cash saving.
