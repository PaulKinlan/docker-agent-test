---
name: incident-classification
description: Classify, prioritize, and route incoming incidents based on severity, category, and affected components
---

# Incident Classification

## When to Use

Use this skill when an incident, issue, or anomaly report arrives and needs to be classified before anyone can act on it. The goal is to produce a structured classification card that tells responders what they are dealing with, how urgent it is, and who should handle it. This is typically the first step in any incident response workflow.

## Severity Definitions

| Level | Name | Criteria | Response Target | Examples |
|-------|------|----------|-----------------|---------|
| **P0** | Critical | Complete outage or data loss affecting all users; security breach with active exploitation; safety risk | Immediate (within minutes) | System entirely down, credentials leaked publicly, data corruption spreading |
| **P1** | High | Major functionality broken for a significant portion of users; performance degraded beyond usable thresholds; security vulnerability with known exploit | Within 1 hour | Primary workflow broken, response times >10x normal, known CVE with public exploit |
| **P2** | Medium | Non-critical functionality impaired; workaround exists; issue affects a subset of users | Within 1 business day | Secondary feature broken, intermittent errors with retry success, single-tenant issue |
| **P3** | Low | Cosmetic issue, minor inconvenience, improvement request, or documentation gap | Next planning cycle | Typo in output, minor UI inconsistency, feature request, stale documentation |

## Category Definitions

| Category | Scope | Keywords |
|----------|-------|----------|
| **System** | Infrastructure, availability, deployment, configuration | down, crash, restart, deploy, container, disk, memory, CPU, OOM, timeout |
| **Data** | Data integrity, loss, corruption, migration, backup | data, corrupt, missing, duplicate, migration, backup, restore, sync, inconsistent |
| **Security** | Authentication, authorization, vulnerability, exposure | auth, permission, denied, leak, vulnerability, CVE, injection, token, certificate |
| **Performance** | Latency, throughput, resource exhaustion, scaling | slow, latency, throughput, queue, backlog, memory, CPU, scaling, bottleneck |
| **Integration** | Third-party services, APIs, external dependencies | API, upstream, downstream, webhook, callback, partner, external, federation |
| **Process** | Workflow, procedure, communication, coordination failures | workflow, missed, notification, handoff, SLA, escalation, procedure |

## Output: Classification Card

```markdown
# Incident Classification

**Incident ID:** INC-[YYYYMMDD]-[NNN]
**Classified by:** [agent name]
**Classified at:** [ISO timestamp]

## Summary
[One-sentence description of the incident]

## Classification
| Field | Value |
|-------|-------|
| **Severity** | P[0-3]: [Name] |
| **Category** | [System / Data / Security / Performance / Integration / Process] |
| **Urgency** | [Immediate / High / Standard / Low] |
| **Affected Components** | [list of components] |
| **Blast Radius** | [All users / Subset / Single user / Internal only] |
| **Workaround Available** | [Yes: describe / No] |

## Initial Assessment
[2-3 sentences: what appears to be happening, what evidence supports this, what is unknown]

## Routing
| Role | Reason |
|------|--------|
| **Primary:** [persona] | [why this role should lead] |
| **Secondary:** [persona] | [why this role should assist] |
| **Notify:** [persona(s)] | [why they need to know] |

## Evidence
- [Observation 1 with source]
- [Observation 2 with source]

## Recommended First Actions
1. [Immediate action for the responder]
2. [Second action]
3. [Third action]
```

## Procedure

### 1. Read the Incident Report

```bash
# Read from incoming mail (Maildir format)
mail -f ~/Maildir -H 2>/dev/null | tail -20

# Or read from a file
INCIDENT_FILE="${1:-/home/shared/inbox/incident.txt}"
if [ -f "$INCIDENT_FILE" ]; then
  cat "$INCIDENT_FILE"
else
  echo "No incident file at $INCIDENT_FILE"
fi

# Or read from the task board (pending, unclassified tasks)
bash /home/shared/scripts/task.sh list --status pending 2>/dev/null | jq '
  .[] | select(.tags == null or (.tags | index("classified") | not)) |
  {id: .id, subject: .subject, description: .description}
' 2>/dev/null
```

Capture the raw text for analysis:

```bash
INCIDENT_TEXT=$(cat "$INCIDENT_FILE" 2>/dev/null || echo "$1")
echo "$INCIDENT_TEXT" > /tmp/incident-raw.txt
echo "Incident text captured: $(wc -w < /tmp/incident-raw.txt) words"
```

### 2. Classify Severity

Apply the severity decision tree. Work through each level starting from P0:

```bash
INCIDENT_LOWER=$(echo "$INCIDENT_TEXT" | tr '[:upper:]' '[:lower:]')

classify_severity() {
  local text="$1"

  # P0: Complete outage, active data loss, active security breach
  if echo "$text" | grep -qE '(complete|total).*(outage|down|failure)'; then
    echo "P0"; return
  fi
  if echo "$text" | grep -qE 'data.*(loss|corrupt|destroy).*active|active.*(breach|exploit)'; then
    echo "P0"; return
  fi
  if echo "$text" | grep -qE 'all users.*(affected|cannot|unable)|everyone.*(down|broken)'; then
    echo "P0"; return
  fi

  # P1: Major functionality broken, severe degradation, known exploit
  if echo "$text" | grep -qE 'major.*(broken|failure|outage)|cannot.*(login|access|use)'; then
    echo "P1"; return
  fi
  if echo "$text" | grep -qE '(response|load).*(time|latency).*[0-9]+.*(second|minute)|extremely slow'; then
    echo "P1"; return
  fi
  if echo "$text" | grep -qE 'cve-[0-9]|known.*(exploit|vulnerability)|security.*(hole|flaw)'; then
    echo "P1"; return
  fi

  # P2: Partial impact, workaround exists, subset affected
  if echo "$text" | grep -qE '(some|few|subset|intermittent|partial).*(user|fail|error|broken)'; then
    echo "P2"; return
  fi
  if echo "$text" | grep -qE 'workaround|can still|alternative|retry.*(work|succeed)'; then
    echo "P2"; return
  fi

  # P3: Everything else
  echo "P3"
}

SEVERITY=$(classify_severity "$INCIDENT_LOWER")
echo "Severity: $SEVERITY"
```

### 3. Classify Category

```bash
classify_category() {
  local text="$1"

  # Security takes priority -- always check first
  if echo "$text" | grep -qE 'auth|permission|denied|leak|vulnerab|cve|inject|token|certif|credential|password|unauthorized'; then
    echo "Security"; return
  fi

  # Data integrity
  if echo "$text" | grep -qE 'data.*(corrupt|loss|missing|duplicate|inconsist)|backup|restore|migration|sync'; then
    echo "Data"; return
  fi

  # Performance
  if echo "$text" | grep -qE 'slow|latency|throughput|queue|backlog|bottleneck|scaling|response.time'; then
    echo "Performance"; return
  fi

  # Integration
  if echo "$text" | grep -qE 'api|upstream|downstream|webhook|external|third.party|partner|federation|integration'; then
    echo "Integration"; return
  fi

  # Process
  if echo "$text" | grep -qE 'workflow|missed|notification|handoff|sla|escalat|procedure|communication'; then
    echo "Process"; return
  fi

  # Default: System
  echo "System"
}

CATEGORY=$(classify_category "$INCIDENT_LOWER")
echo "Category: $CATEGORY"
```

### 4. Identify Affected Components

```bash
# Extract component names by looking for known system terms
identify_components() {
  local text="$1"
  local components=""

  # Check for known shared infrastructure
  echo "$text" | grep -oE '(task.board|artifact|mail|orchestrat|agent|script|shared|workspace|heartbeat|health.check)' \
    | sort -u | tr '\n' ', ' | sed 's/,$//'
}

COMPONENTS=$(identify_components "$INCIDENT_LOWER")
if [ -z "$COMPONENTS" ]; then
  COMPONENTS="Unknown -- requires investigation"
fi
echo "Affected components: $COMPONENTS"
```

### 5. Determine Blast Radius

```bash
determine_blast_radius() {
  local text="$1"

  if echo "$text" | grep -qE 'all (user|agent|system)|every(one|thing)|complete|total|entire'; then
    echo "All users"
  elif echo "$text" | grep -qE 'some (user|agent)|subset|group|team|partial'; then
    echo "Subset"
  elif echo "$text" | grep -qE 'single|one (user|agent)|specific|individual|only I|only my'; then
    echo "Single user"
  elif echo "$text" | grep -qE 'internal|backend|infra|admin|operator'; then
    echo "Internal only"
  else
    echo "Unknown -- requires investigation"
  fi
}

BLAST_RADIUS=$(determine_blast_radius "$INCIDENT_LOWER")
echo "Blast radius: $BLAST_RADIUS"
```

### 6. Check for Similar Past Incidents

```bash
# Search for past classification cards
find /home/shared/ -name 'incident-classification-*' -type f 2>/dev/null | while read f; do
  MATCH=$(grep -l "$CATEGORY" "$f" 2>/dev/null)
  if [ -n "$MATCH" ]; then
    echo "=== Similar past incident: $f ==="
    head -20 "$f"
    echo ""
  fi
done

# Search the triage log
if [ -f ~/triage/log.jsonl ]; then
  jq -r "select(.type == \"$(echo "$CATEGORY" | tr '[:upper:]' '[:lower:]')\")" ~/triage/log.jsonl 2>/dev/null \
    | tail -5
fi
```

### 7. Route to Appropriate Specialist

```bash
route_incident() {
  local severity="$1"
  local category="$2"

  case "$category" in
    Security)
      PRIMARY="security"; SECONDARY="coder"; NOTIFY="manager" ;;
    Data)
      PRIMARY="coder"; SECONDARY="analyst"; NOTIFY="manager" ;;
    Performance)
      PRIMARY="coder"; SECONDARY="analyst"; NOTIFY="architect" ;;
    Integration)
      PRIMARY="coder"; SECONDARY="devops"; NOTIFY="architect" ;;
    Process)
      PRIMARY="manager"; SECONDARY="planner"; NOTIFY="" ;;
    System|*)
      PRIMARY="devops"; SECONDARY="coder"; NOTIFY="manager" ;;
  esac

  # P0 always notifies manager
  if [ "$severity" = "P0" ]; then
    NOTIFY="manager"
  fi

  echo "PRIMARY=$PRIMARY SECONDARY=$SECONDARY NOTIFY=$NOTIFY"
}

eval $(route_incident "$SEVERITY" "$CATEGORY")
echo "Route: primary=$PRIMARY, secondary=$SECONDARY, notify=$NOTIFY"
```

### 8. Write the Classification Card

```bash
INCIDENT_ID="INC-$(date +%Y%m%d)-$(printf '%03d' $((RANDOM % 999 + 1)))"
CLASSIFICATION_FILE="/home/shared/incident-classification-${INCIDENT_ID}.md"
TIMESTAMP=$(date -Iseconds)
AGENT_NAME=$(whoami)
SUMMARY_LINE=$(echo "$INCIDENT_TEXT" | head -1 | cut -c1-120)

# Map severity to urgency
case "$SEVERITY" in
  P0) URGENCY="Immediate" ;;
  P1) URGENCY="High" ;;
  P2) URGENCY="Standard" ;;
  P3) URGENCY="Low" ;;
esac

cat > "$CLASSIFICATION_FILE" <<EOF
# Incident Classification

**Incident ID:** ${INCIDENT_ID}
**Classified by:** ${AGENT_NAME}
**Classified at:** ${TIMESTAMP}

## Summary
${SUMMARY_LINE}

## Classification
| Field | Value |
|-------|-------|
| **Severity** | ${SEVERITY}: $(echo "$SEVERITY" | sed 's/P0/Critical/;s/P1/High/;s/P2/Medium/;s/P3/Low/') |
| **Category** | ${CATEGORY} |
| **Urgency** | ${URGENCY} |
| **Affected Components** | ${COMPONENTS} |
| **Blast Radius** | ${BLAST_RADIUS} |
| **Workaround Available** | [FILL IN: Yes -- describe / No] |

## Initial Assessment
[FILL IN: 2-3 sentences describing what appears to be happening based on the report, what evidence supports this assessment, and what remains unknown.]

## Routing
| Role | Reason |
|------|--------|
| **Primary:** ${PRIMARY} | Lead responder for ${CATEGORY} incidents |
| **Secondary:** ${SECONDARY} | Supporting expertise for ${CATEGORY} |
| **Notify:** ${NOTIFY:-none} | Awareness for ${SEVERITY} severity |

## Evidence
$(echo "$INCIDENT_TEXT" | head -10 | sed 's/^/- /')

## Recommended First Actions
1. Acknowledge the incident and update the task board
2. Reproduce or verify the reported symptoms
3. Assess actual blast radius and confirm severity
EOF

echo "Classification card written to: $CLASSIFICATION_FILE"
```

### 9. Notify the Assigned Responder

```bash
# Send classification to primary responder
bash /home/shared/scripts/send-mail.sh "$PRIMARY" <<EOF
[${SEVERITY}] Incident ${INCIDENT_ID} assigned to you

Classification: ${SEVERITY} ${CATEGORY}
Urgency: ${URGENCY}
Affected: ${COMPONENTS}
Blast radius: ${BLAST_RADIUS}

Summary: ${SUMMARY_LINE}

Full classification card: ${CLASSIFICATION_FILE}

Recommended first actions:
1. Acknowledge by updating task status to in_progress
2. Reproduce or verify the reported symptoms
3. Assess actual blast radius and confirm severity

$(if [ "$SEVERITY" = "P0" ]; then
  echo "This is a P0 -- drop everything and respond immediately."
fi)
EOF

# Notify secondary
bash /home/shared/scripts/send-mail.sh "$SECONDARY" <<EOF
[FYI] Incident ${INCIDENT_ID} -- you are secondary responder

${SEVERITY} ${CATEGORY} incident assigned to ${PRIMARY}.
You may be pulled in for assistance.
Classification card: ${CLASSIFICATION_FILE}
EOF

# Notify manager for P0/P1
if [ -n "$NOTIFY" ]; then
  bash /home/shared/scripts/send-mail.sh "$NOTIFY" <<EOF
[${SEVERITY}] Incident ${INCIDENT_ID} classified and routed

Category: ${CATEGORY}
Assigned to: ${PRIMARY} (primary), ${SECONDARY} (secondary)
Blast radius: ${BLAST_RADIUS}
Summary: ${SUMMARY_LINE}

Classification card: ${CLASSIFICATION_FILE}
EOF
fi

echo "Notifications sent."
```

### 10. Create Task and Register Artifact

```bash
# Create a task for tracking
TASK_ID=$(bash /home/shared/scripts/task.sh add \
  --subject "[${SEVERITY}] ${INCIDENT_ID}: ${SUMMARY_LINE}" \
  --description "Classified incident. See ${CLASSIFICATION_FILE} for details." \
  --owner "$PRIMARY" 2>/dev/null | jq -r '.id' 2>/dev/null)

echo "Task created: $TASK_ID"

# Register the classification card as an artifact
bash /home/shared/scripts/artifact.sh register \
  --name "classification-${INCIDENT_ID}" \
  --type "incident-classification" \
  --path "$CLASSIFICATION_FILE" \
  --description "${SEVERITY} ${CATEGORY} incident: ${SUMMARY_LINE}"

echo "Artifact registered."

# Log the classification
mkdir -p ~/classifications
cat >> ~/classifications/log.jsonl <<EOF
{"timestamp":"${TIMESTAMP}","incident_id":"${INCIDENT_ID}","severity":"${SEVERITY}","category":"${CATEGORY}","urgency":"${URGENCY}","blast_radius":"${BLAST_RADIUS}","components":"${COMPONENTS}","primary":"${PRIMARY}","secondary":"${SECONDARY}","task_id":"${TASK_ID}","classified_by":"${AGENT_NAME}"}
EOF
```

## Quality Checklist

- [ ] Incident report has been read completely before classifying
- [ ] Severity is justified by matching specific criteria (not a gut feeling)
- [ ] Category is assigned based on the primary nature of the issue
- [ ] Affected components are identified (or explicitly marked as unknown)
- [ ] Blast radius is assessed (all users / subset / single / internal)
- [ ] Past similar incidents were checked for patterns
- [ ] Primary and secondary responders are assigned based on category
- [ ] Classification card is written with all fields populated
- [ ] Primary responder is notified with severity, summary, and first actions
- [ ] Manager is notified for P0 and P1 incidents
- [ ] Task is created on the task board with the correct owner
- [ ] Classification is logged for future pattern analysis
