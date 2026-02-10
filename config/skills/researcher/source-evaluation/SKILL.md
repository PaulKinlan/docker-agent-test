---
name: source-evaluation
description: Evaluate reliability and relevance of information sources
---

# Source Evaluation

## When to Use

Use this skill when you need to assess the reliability of information before including it in research, recommendations, or decisions.

## Evaluation Criteria

Evaluate every source against these four dimensions:

| Criterion | Question | Indicators of High Quality | Indicators of Low Quality |
|-----------|----------|---------------------------|--------------------------|
| Authority | Who created this? | Official docs, maintainer, known expert | Unknown author, no attribution |
| Currency | How recent is it? | Updated within 12 months, matches current version | Outdated version, no date |
| Accuracy | Can claims be verified? | Consistent with other sources, testable | Contradicts known facts, untestable |
| Scope | Does it cover what we need? | Directly addresses our question | Tangentially related, partial coverage |

## Confidence Levels

Assign one of these confidence levels to each piece of information:

| Level | Definition | When to Use |
|-------|-----------|-------------|
| **High** | Multiple authoritative sources agree | Official docs + verified by code inspection + confirmed by testing |
| **Medium** | Single credible source, uncontradicted | One official doc or one reliable source, no conflicting info |
| **Low** | Unverifiable or outdated | No authoritative source, or source is >2 years old for fast-moving tech |
| **Conflicting** | Sources disagree | Two or more sources make contradictory claims |

## Procedure

### 1. Catalog All Sources

For each piece of information you have gathered, record its source:

```bash
cat > /tmp/source-eval.md <<'EOF'
| # | Source | Type | URL/Path | Date | Author/Org |
|---|--------|------|----------|------|------------|
| 1 | | | | | |
| 2 | | | | | |
EOF
```

Source types:
- `official-doc` — Maintained documentation from the project
- `source-code` — Reading the actual implementation
- `manpage` — System manual pages
- `config-file` — Existing configuration in the project
- `test-output` — Empirical result from running code
- `article` — Blog post, tutorial, or third-party writeup
- `comment` — Code comment or commit message
- `inference` — Logical deduction from other facts

### 2. Evaluate Each Source

For each source, check:

```bash
SOURCE_PATH="/path/to/source"

# Currency: when was it last modified?
stat -c '%y' "$SOURCE_PATH" 2>/dev/null || stat -f '%Sm' "$SOURCE_PATH" 2>/dev/null

# Authority: who wrote/owns it?
git log --format='%an <%ae>' -1 -- "$SOURCE_PATH" 2>/dev/null

# Accuracy: does the code match what the doc says?
# (manually compare doc claims against actual implementation)

# Scope: does it address our specific question?
# (manually assess relevance)
```

### 3. Cross-Reference Claims

For important claims, verify against multiple sources:

```bash
CLAIM="function accepts JSON input"

# Check source code
rg "JSON\.parse|json\.loads" ~/workspace/src/ --type-add 'code:*.{js,py,ts}' --type code

# Check tests
rg "JSON|json" ~/workspace/tests/ -l

# Check documentation
rg -i "json" ~/workspace/README.md ~/workspace/docs/ 2>/dev/null
```

### 4. Produce Evaluation Output

For each source, produce a structured assessment:

```markdown
### Source: [Name or path]
- **Type:** official-doc | source-code | article | ...
- **Confidence:** High | Medium | Low | Conflicting
- **Authority:** [Who created it, their relationship to the project]
- **Currency:** [Last updated date, version it covers]
- **Accuracy:** [Verified against N other sources / Unable to verify]
- **Scope:** [Directly relevant / Partially relevant / Tangential]
- **Notes:** [Any caveats, biases, or limitations]
```

### 5. Resolve Conflicts

When sources disagree:

1. Prefer source code over documentation (code is ground truth)
2. Prefer test output over theoretical claims (empirical over theoretical)
3. Prefer newer over older (for version-specific information)
4. Prefer official over third-party
5. Document the conflict explicitly:

```markdown
### Conflicting Information
- **Claim:** [The disputed fact]
- **Source A says:** [claim] (confidence: Medium, official-doc from 2024)
- **Source B says:** [contradictory claim] (confidence: High, source-code current)
- **Resolution:** Source B (source code) takes precedence over outdated documentation
```

## Quality Checklist

- [ ] Every source has been cataloged with type, date, and author
- [ ] Each source has a confidence level assigned
- [ ] Important claims are cross-referenced against at least 2 sources
- [ ] Conflicts are documented with explicit resolution reasoning
- [ ] Low-confidence information is flagged for the consumer
- [ ] Source evaluation is included in the research deliverable's Sources table
