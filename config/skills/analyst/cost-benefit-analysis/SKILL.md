---
name: cost-benefit-analysis
description: Evaluate costs vs benefits of a proposed change, investment, or decision with quantified ROI
---

# Cost-Benefit Analysis

## When to Use

Use this skill when tasked with evaluating whether a proposed change, investment, initiative, or decision is worth pursuing. This applies to technology migrations, process changes, vendor selections, staffing decisions, feature investments, or any scenario where costs must be weighed against expected benefits.

## Output Template

```markdown
# Cost-Benefit Analysis: [Subject]

**Date:** YYYY-MM-DD
**Analyst:** [agent name]
**Decision:** [what is being evaluated]
**Recommendation:** [Proceed / Do Not Proceed / Proceed with Conditions]

## Executive Summary
[2-3 sentences: what was analyzed, what the numbers show, what is recommended]

## Cost Analysis

| # | Cost Item | Category | One-Time | Recurring (/yr) | Years | Total |
|---|-----------|----------|----------|------------------|-------|-------|
| C1 | ... | direct | $N | $N | N | $N |

**Total Costs:** $N

## Benefit Analysis

| # | Benefit Item | Category | One-Time | Recurring (/yr) | Years | Total |
|---|-------------|----------|----------|------------------|-------|-------|
| B1 | ... | tangible | $N | $N | N | $N |

**Total Benefits:** $N

## Financial Summary
- **Net Present Value (NPV):** $N
- **Return on Investment (ROI):** N%
- **Payback Period:** N months
- **Benefit-Cost Ratio:** N:1

## Risk Factors
| Risk | Impact on Analysis | Adjusted Estimate |
|------|-------------------|-------------------|
| ... | ... | ... |

## Sensitivity Analysis
[How results change if key assumptions vary by +/-20%]

## Recommendation
[Proceed / Do Not Proceed / Proceed with Conditions — with rationale]
```

## Procedure

### 1. Gather Context

```bash
# Read the proposal or decision description
PROPOSAL="${1:-/home/shared/proposal.md}"
echo "=== Proposal ==="
cat "$PROPOSAL" 2>/dev/null || echo "No proposal file found at $PROPOSAL"

echo ""
echo "=== Related Artifacts ==="
bash /home/shared/scripts/artifact.sh list 2>/dev/null | jq -r '.[] | "\(.path) — \(.description)"' 2>/dev/null

echo ""
echo "=== Related Tasks ==="
bash /home/shared/scripts/task.sh list 2>/dev/null | jq '.[] | {id: .id, subject: .subject, status: .status}' 2>/dev/null

echo ""
echo "=== Check for Prior Analysis ==="
find /home/shared -name "*cost*" -o -name "*benefit*" -o -name "*roi*" -o -name "*budget*" 2>/dev/null
```

### 2. Enumerate Costs

Identify costs in three categories:
- **Direct costs:** money spent (licenses, hardware, labor, contracts)
- **Indirect costs:** overhead, training, productivity loss during transition
- **Opportunity costs:** what you give up by choosing this path

```bash
# Create structured cost inventory
cat > /tmp/costs.csv <<'EOF'
id,item,category,one_time,recurring_yearly,years,notes
C1,Software licenses,direct,0,24000,3,Annual SaaS subscription
C2,Migration labor (480 hrs),direct,72000,0,1,3 engineers x 8 weeks x 20 hrs/wk x $150/hr
C3,Staff training,indirect,15000,0,1,2-day workshop for 20 people
C4,Productivity dip during transition,indirect,0,30000,1,Estimated 10% slowdown for 6 months
C5,Feature delay (opportunity cost),opportunity,50000,0,1,3-month delay to roadmap items
EOF

echo "=== Cost Inventory ==="
column -t -s',' /tmp/costs.csv
```

### 3. Enumerate Benefits

Identify benefits in two categories:
- **Tangible benefits:** measurable savings, revenue, time reduction (can assign dollar value)
- **Intangible benefits:** improved morale, better brand perception, reduced risk (describe qualitatively, estimate where possible)

```bash
# Create structured benefit inventory
cat > /tmp/benefits.csv <<'EOF'
id,item,category,one_time,recurring_yearly,years,notes
B1,Reduced infrastructure costs,tangible,0,36000,3,Eliminate 3 legacy servers
B2,Developer productivity gain,tangible,0,60000,3,15% faster feature delivery (4 devs x $100K x 15%)
B3,Reduced incident response time,tangible,0,20000,3,50% fewer P1 incidents x $2K avg cost
B4,Improved developer satisfaction,intangible,0,10000,3,Estimated retention value
B5,Better security posture,intangible,0,15000,3,Reduced breach risk probability
EOF

echo "=== Benefit Inventory ==="
column -t -s',' /tmp/benefits.csv
```

### 4. Compute Totals and ROI

```bash
python3 <<'PYEOF'
import csv
import json

def load_items(path):
    with open(path) as f:
        return list(csv.DictReader(f))

costs = load_items("/tmp/costs.csv")
benefits = load_items("/tmp/benefits.csv")

def total_value(items):
    """Compute undiscounted total for each item and overall."""
    results = []
    for item in items:
        one_time = float(item["one_time"])
        recurring = float(item["recurring_yearly"])
        years = int(item["years"])
        total = one_time + (recurring * years)
        results.append({**item, "total": total})
    grand_total = sum(r["total"] for r in results)
    return results, grand_total

cost_items, total_costs = total_value(costs)
benefit_items, total_benefits = total_value(benefits)

print("=" * 60)
print("COST SUMMARY")
print("=" * 60)
for c in cost_items:
    print(f"  {c['id']}: {c['item']:<45} ${c['total']:>10,.0f}")
print(f"  {'TOTAL COSTS':<49} ${total_costs:>10,.0f}")

print()
print("=" * 60)
print("BENEFIT SUMMARY")
print("=" * 60)
for b in benefit_items:
    print(f"  {b['id']}: {b['item']:<45} ${b['total']:>10,.0f}")
print(f"  {'TOTAL BENEFITS':<49} ${total_benefits:>10,.0f}")

# Simple ROI
net_benefit = total_benefits - total_costs
roi = (net_benefit / total_costs * 100) if total_costs > 0 else 0
bcr = total_benefits / total_costs if total_costs > 0 else 0

print()
print("=" * 60)
print("FINANCIAL SUMMARY (undiscounted)")
print("=" * 60)
print(f"  Total Costs:        ${total_costs:>12,.0f}")
print(f"  Total Benefits:     ${total_benefits:>12,.0f}")
print(f"  Net Benefit:        ${net_benefit:>12,.0f}")
print(f"  ROI:                {roi:>11.1f}%")
print(f"  Benefit-Cost Ratio: {bcr:>11.2f}:1")

# Write summary as JSON for downstream use
summary = {
    "total_costs": total_costs,
    "total_benefits": total_benefits,
    "net_benefit": net_benefit,
    "roi_percent": round(roi, 1),
    "benefit_cost_ratio": round(bcr, 2)
}
with open("/tmp/cba-summary.json", "w") as f:
    json.dump(summary, f, indent=2)

print()
print("Summary written to /tmp/cba-summary.json")
PYEOF
```

### 5. Compute Net Present Value (NPV)

```bash
python3 <<'PYEOF'
import csv
import json

DISCOUNT_RATE = 0.08  # 8% annual discount rate
HORIZON_YEARS = 3

def load_items(path):
    with open(path) as f:
        return list(csv.DictReader(f))

costs = load_items("/tmp/costs.csv")
benefits = load_items("/tmp/benefits.csv")

def yearly_cashflows(items, horizon):
    """Build array of cashflows per year from item definitions."""
    flows = [0.0] * (horizon + 1)  # year 0 through year N
    for item in items:
        one_time = float(item["one_time"])
        recurring = float(item["recurring_yearly"])
        years = min(int(item["years"]), horizon)
        flows[0] += one_time
        for y in range(1, years + 1):
            flows[y] += recurring
    return flows

cost_flows = yearly_cashflows(costs, HORIZON_YEARS)
benefit_flows = yearly_cashflows(benefits, HORIZON_YEARS)

print(f"Discount rate: {DISCOUNT_RATE*100:.0f}%")
print(f"Horizon: {HORIZON_YEARS} years")
print()
print(f"{'Year':<6} {'Costs':>12} {'Benefits':>12} {'Net':>12} {'PV Factor':>10} {'PV Net':>12}")
print("-" * 66)

npv = 0.0
cumulative = 0.0
payback_year = None

for y in range(HORIZON_YEARS + 1):
    c = cost_flows[y]
    b = benefit_flows[y]
    net = b - c
    pv_factor = 1 / ((1 + DISCOUNT_RATE) ** y)
    pv_net = net * pv_factor
    npv += pv_net
    cumulative += net

    if payback_year is None and cumulative >= 0 and y > 0:
        payback_year = y

    print(f"  {y:<4} ${c:>10,.0f} ${b:>10,.0f} ${net:>10,.0f} {pv_factor:>9.4f} ${pv_net:>10,.0f}")

print("-" * 66)
print(f"  NPV: ${npv:>10,.0f}")

if payback_year is not None:
    # Interpolate for partial year
    prev_cumulative = cumulative - (benefit_flows[payback_year] - cost_flows[payback_year])
    net_in_year = benefit_flows[payback_year] - cost_flows[payback_year]
    if net_in_year > 0:
        fraction = abs(prev_cumulative) / net_in_year
        payback_months = ((payback_year - 1) + fraction) * 12
    else:
        payback_months = payback_year * 12
    print(f"  Payback period: ~{payback_months:.0f} months")
else:
    payback_months = None
    print("  Payback period: not reached within horizon")

# Save NPV results
with open("/tmp/cba-npv.json", "w") as f:
    json.dump({
        "discount_rate": DISCOUNT_RATE,
        "horizon_years": HORIZON_YEARS,
        "npv": round(npv, 2),
        "payback_months": round(payback_months, 0) if payback_months else None,
        "cost_flows": cost_flows,
        "benefit_flows": benefit_flows
    }, f, indent=2)

print()
print("NPV details written to /tmp/cba-npv.json")
PYEOF
```

### 6. Risk-Adjust the Analysis

```bash
python3 <<'PYEOF'
import json

# Load base analysis
with open("/tmp/cba-summary.json") as f:
    base = json.load(f)

# Define risk factors and their probability of reducing benefits or increasing costs
risks = [
    {
        "risk": "Adoption slower than expected",
        "probability": 0.3,
        "benefit_reduction": 0.20,
        "cost_increase": 0.05,
        "notes": "Teams may resist change; benefits delayed 6+ months"
    },
    {
        "risk": "Integration complexity underestimated",
        "probability": 0.25,
        "benefit_reduction": 0.0,
        "cost_increase": 0.30,
        "notes": "Legacy system interfaces often have hidden complexity"
    },
    {
        "risk": "Vendor pricing increases",
        "probability": 0.15,
        "benefit_reduction": 0.0,
        "cost_increase": 0.15,
        "notes": "SaaS pricing may increase at renewal"
    }
]

print("=" * 70)
print("RISK-ADJUSTED ANALYSIS")
print("=" * 70)
print()
print(f"{'Risk':<35} {'Prob':>5} {'Benefit-':>9} {'Cost+':>7} {'Weighted Impact':>15}")
print("-" * 70)

total_benefit_reduction = 0
total_cost_increase = 0

for r in risks:
    weighted_br = r["probability"] * r["benefit_reduction"]
    weighted_ci = r["probability"] * r["cost_increase"]
    total_benefit_reduction += weighted_br
    total_cost_increase += weighted_ci
    impact = (weighted_br * base["total_benefits"]) + (weighted_ci * base["total_costs"])
    print(f"  {r['risk']:<33} {r['probability']:>4.0%} {r['benefit_reduction']:>8.0%} {r['cost_increase']:>6.0%} ${impact:>13,.0f}")

adj_benefits = base["total_benefits"] * (1 - total_benefit_reduction)
adj_costs = base["total_costs"] * (1 + total_cost_increase)
adj_net = adj_benefits - adj_costs
adj_roi = (adj_net / adj_costs * 100) if adj_costs > 0 else 0

print()
print(f"  Base Benefits:          ${base['total_benefits']:>12,.0f}")
print(f"  Risk-Adjusted Benefits: ${adj_benefits:>12,.0f}  ({total_benefit_reduction:>5.1%} reduction)")
print(f"  Base Costs:             ${base['total_costs']:>12,.0f}")
print(f"  Risk-Adjusted Costs:    ${adj_costs:>12,.0f}  ({total_cost_increase:>5.1%} increase)")
print(f"  Risk-Adjusted Net:      ${adj_net:>12,.0f}")
print(f"  Risk-Adjusted ROI:      {adj_roi:>11.1f}%")

with open("/tmp/cba-risk-adjusted.json", "w") as f:
    json.dump({
        "risks": risks,
        "adjusted_benefits": adj_benefits,
        "adjusted_costs": adj_costs,
        "adjusted_net": adj_net,
        "adjusted_roi_percent": round(adj_roi, 1)
    }, f, indent=2)

print()
print("Risk-adjusted results written to /tmp/cba-risk-adjusted.json")
PYEOF
```

### 7. Sensitivity Analysis

```bash
python3 <<'PYEOF'
import json

with open("/tmp/cba-summary.json") as f:
    base = json.load(f)

print("=" * 60)
print("SENSITIVITY ANALYSIS")
print("=" * 60)
print()
print("How does ROI change when key assumptions vary?")
print()
print(f"{'Scenario':<40} {'Net Benefit':>12} {'ROI':>8}")
print("-" * 62)

scenarios = [
    ("Base case",                         1.0,  1.0),
    ("Costs +20%",                        1.0,  1.2),
    ("Costs -20%",                        1.0,  0.8),
    ("Benefits +20%",                     1.2,  1.0),
    ("Benefits -20%",                     0.8,  1.0),
    ("Worst: Costs +20%, Benefits -20%",  0.8,  1.2),
    ("Best: Costs -20%, Benefits +20%",   1.2,  0.8),
    ("Benefits -50% (pessimistic)",       0.5,  1.0),
]

for label, b_mult, c_mult in scenarios:
    adj_b = base["total_benefits"] * b_mult
    adj_c = base["total_costs"] * c_mult
    net = adj_b - adj_c
    roi = (net / adj_c * 100) if adj_c > 0 else 0
    flag = " <<<" if net < 0 else ""
    print(f"  {label:<38} ${net:>10,.0f} {roi:>7.1f}%{flag}")

print()
print("  '<<<' marks scenarios where the investment loses money")
PYEOF
```

### 8. Write the Final Report

```bash
SUBJECT="$(head -1 "$PROPOSAL" 2>/dev/null | sed 's/^#\+\s*//' || echo 'Proposed Initiative')"
REPORT_FILE="/home/shared/cost-benefit-analysis-$(date +%Y%m%d).md"

# Determine recommendation based on risk-adjusted ROI
RECOMMENDATION=$(python3 -c "
import json
with open('/tmp/cba-risk-adjusted.json') as f:
    d = json.load(f)
roi = d['adjusted_roi_percent']
if roi >= 50:
    print('Proceed — strong risk-adjusted ROI supports investment')
elif roi >= 10:
    print('Proceed with Conditions — positive but moderate ROI; monitor assumptions closely')
elif roi >= 0:
    print('Conditional — marginal ROI; consider phased approach to limit downside')
else:
    print('Do Not Proceed — negative risk-adjusted ROI indicates costs outweigh benefits')
")

cat > "$REPORT_FILE" <<REOF
# Cost-Benefit Analysis: ${SUBJECT}

**Date:** $(date +%Y-%m-%d)
**Analyst:** $(whoami)
**Decision:** Whether to proceed with: ${SUBJECT}
**Recommendation:** ${RECOMMENDATION}

## Executive Summary

This analysis evaluates the costs and benefits of the proposed initiative over a multi-year horizon. See the Financial Summary section for quantified results and the Risk Factors section for adjusted estimates.

$(python3 -c "
import json
with open('/tmp/cba-summary.json') as f: s = json.load(f)
with open('/tmp/cba-risk-adjusted.json') as f: r = json.load(f)
with open('/tmp/cba-npv.json') as f: n = json.load(f)
print(f'The base-case analysis shows a net benefit of \${s[\"net_benefit\"]:,.0f} with an ROI of {s[\"roi_percent\"]}%.')
print(f'After risk adjustment, the net benefit is \${r[\"adjusted_net\"]:,.0f} with an ROI of {r[\"adjusted_roi_percent\"]}%.')
print(f'NPV at {n[\"discount_rate\"]*100:.0f}% discount rate is \${n[\"npv\"]:,.0f}', end='')
if n.get('payback_months'):
    print(f' with an estimated payback period of {n[\"payback_months\"]:.0f} months.')
else:
    print('.')
")

## Cost Analysis

$(python3 -c "
import csv
costs = list(csv.DictReader(open('/tmp/costs.csv')))
print('| # | Cost Item | Category | One-Time | Recurring (/yr) | Years | Total |')
print('|---|-----------|----------|----------|------------------|-------|-------|')
for c in costs:
    ot = float(c['one_time']); rec = float(c['recurring_yearly']); yrs = int(c['years'])
    total = ot + rec * yrs
    print(f'| {c[\"id\"]} | {c[\"item\"]} | {c[\"category\"]} | \${ot:,.0f} | \${rec:,.0f} | {yrs} | \${total:,.0f} |')
grand = sum(float(c['one_time']) + float(c['recurring_yearly']) * int(c['years']) for c in costs)
print(f'| | **TOTAL** | | | | | **\${grand:,.0f}** |')
")

## Benefit Analysis

$(python3 -c "
import csv
benefits = list(csv.DictReader(open('/tmp/benefits.csv')))
print('| # | Benefit Item | Category | One-Time | Recurring (/yr) | Years | Total |')
print('|---|-------------|----------|----------|------------------|-------|-------|')
for b in benefits:
    ot = float(b['one_time']); rec = float(b['recurring_yearly']); yrs = int(b['years'])
    total = ot + rec * yrs
    print(f'| {b[\"id\"]} | {b[\"item\"]} | {b[\"category\"]} | \${ot:,.0f} | \${rec:,.0f} | {yrs} | \${total:,.0f} |')
grand = sum(float(b['one_time']) + float(b['recurring_yearly']) * int(b['years']) for b in benefits)
print(f'| | **TOTAL** | | | | | **\${grand:,.0f}** |')
")

## Financial Summary

$(python3 -c "
import json
with open('/tmp/cba-summary.json') as f: s = json.load(f)
with open('/tmp/cba-npv.json') as f: n = json.load(f)
print(f'| Metric | Value |')
print(f'|--------|-------|')
print(f'| Total Costs | \${s[\"total_costs\"]:,.0f} |')
print(f'| Total Benefits | \${s[\"total_benefits\"]:,.0f} |')
print(f'| Net Benefit | \${s[\"net_benefit\"]:,.0f} |')
print(f'| ROI | {s[\"roi_percent\"]}% |')
print(f'| Benefit-Cost Ratio | {s[\"benefit_cost_ratio\"]}:1 |')
print(f'| NPV ({n[\"discount_rate\"]*100:.0f}% discount) | \${n[\"npv\"]:,.0f} |')
pm = n.get('payback_months')
print(f'| Payback Period | {f\"{pm:.0f} months\" if pm else \"Not reached\"} |')
")

## Risk Factors

$(python3 -c "
import json
with open('/tmp/cba-risk-adjusted.json') as f: r = json.load(f)
print('| Risk | Probability | Impact on Analysis | Notes |')
print('|------|------------|-------------------|-------|')
for risk in r['risks']:
    impact_parts = []
    if risk['benefit_reduction'] > 0:
        impact_parts.append(f'Benefits -{risk[\"benefit_reduction\"]*100:.0f}%')
    if risk['cost_increase'] > 0:
        impact_parts.append(f'Costs +{risk[\"cost_increase\"]*100:.0f}%')
    impact = ', '.join(impact_parts)
    print(f'| {risk[\"risk\"]} | {risk[\"probability\"]*100:.0f}% | {impact} | {risk[\"notes\"]} |')
print()
print(f'**Risk-Adjusted ROI:** {r[\"adjusted_roi_percent\"]}%')
print(f'**Risk-Adjusted Net Benefit:** \${r[\"adjusted_net\"]:,.0f}')
")

## Sensitivity Analysis

$(python3 -c "
import json
with open('/tmp/cba-summary.json') as f: base = json.load(f)
scenarios = [
    ('Base case', 1.0, 1.0),
    ('Costs +20%', 1.0, 1.2),
    ('Costs -20%', 1.0, 0.8),
    ('Benefits +20%', 1.2, 1.0),
    ('Benefits -20%', 0.8, 1.0),
    ('Worst case (Costs +20%, Benefits -20%)', 0.8, 1.2),
    ('Best case (Costs -20%, Benefits +20%)', 1.2, 0.8),
]
print('| Scenario | Net Benefit | ROI |')
print('|----------|-------------|-----|')
for label, bm, cm in scenarios:
    b = base['total_benefits'] * bm
    c = base['total_costs'] * cm
    net = b - c
    roi = (net / c * 100) if c > 0 else 0
    print(f'| {label} | \${net:,.0f} | {roi:.1f}% |')
")

## Recommendation

${RECOMMENDATION}

## Methodology

- Costs and benefits enumerated from proposal documentation and stakeholder input
- Financial calculations: undiscounted totals, NPV at stated discount rate, simple ROI
- Risk adjustment: probability-weighted impact on costs and benefits
- Sensitivity analysis: +/-20% variation on key assumptions
- All calculations performed with Python; source data in CSV format
REOF

echo "Report written to: $REPORT_FILE"

# Register as artifact
bash /home/shared/scripts/artifact.sh register \
  "$REPORT_FILE" \
  --description "Cost-benefit analysis for: ${SUBJECT}"
```

## Quality Checklist

- [ ] All three cost categories addressed (direct, indirect, opportunity)
- [ ] All two benefit categories addressed (tangible, intangible)
- [ ] Dollar values assigned to every item with documented assumptions
- [ ] ROI, NPV, and payback period computed
- [ ] Risk factors identified with probability estimates
- [ ] Risk-adjusted ROI computed (not just base case)
- [ ] Sensitivity analysis shows break-even points
- [ ] Recommendation ties directly to the financial results
- [ ] Report written to shared workspace and registered as artifact
