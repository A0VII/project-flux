# Project Flux — Architecture Decisions

> Engineering rationale behind the key design choices in this project.
> Each decision documents the options considered, the choice made, and why.

---

## Decision 1: API Gateway → SQS Direct Integration (No Lambda on Ingest Path)

**Context:** Events arrive at the API Gateway and need to reach SQS.

**Options considered:**
- A) API Gateway → Lambda → SQS (Lambda validates and enqueues)
- B) API Gateway → SQS direct service integration (no Lambda)

**Decision:** Option B — direct integration.

**Rationale:**
- Fewer hops = lower latency on the hot path (ingest is latency-sensitive)
- No Lambda cold start on ingest — SQS accepts the message immediately
- Lambda errors on the ingest path would cause data loss; SQS absorbs the load even if Lambda is unavailable
- The HTTP 202 Accepted response correctly signals async processing

**Trade-off:** No request validation on ingest. Malformed events reach SQS and Lambda. Accepted for this project — a production system would add API Gateway request validation or a separate validation Lambda.

---

## Decision 2: S3 + DynamoDB (Two Storage Systems, Not One)

**Context:** Processed events need to be stored persistently.

**Options considered:**
- A) S3 only (raw archive, query with Athena)
- B) DynamoDB only (fast indexed access)
- C) S3 + DynamoDB (archive + indexed state)

**Decision:** Option C — both.

**Rationale:**
- S3 is the cheapest durable archive — cost per GB-month is ~20x cheaper than DynamoDB
- DynamoDB gives single-millisecond access to the latest device state — essential for dashboards and alerts
- The two systems serve different access patterns: S3 for historical analysis, DynamoDB for real-time state
- S3 objects are time-partitioned (`events/YYYY/MM/DD/device_id/`) for Athena compatibility

**Trade-off:** Write amplification — every event is written to two systems. Accepted because the patterns are genuinely different and the cost difference is significant at scale.

---

## Decision 3: KMS CMK Over AWS-Managed Keys

**Context:** Data at rest must be encrypted.

**Options considered:**
- A) AWS-managed keys (SSE-S3, SSE-SQS default)
- B) Customer Managed Key (CMK) via KMS

**Decision:** Option B — single CMK for all services.

**Rationale:**
- CMK provides a full audit trail in CloudTrail — every encrypt/decrypt call is logged
- Single key for all services reduces operational complexity vs. per-service keys
- Annual rotation enabled — satisfies compliance requirements without manual intervention
- Scoped principal policy — only specific roles and services can use the key

**Trade-off:** ~$1/month flat cost. Accepted — the audit trail and access control are worth it for a health data pipeline.

---

## Decision 4: SQS DLQ with `maxReceiveCount=3`

**Context:** Events that Lambda fails to process need handling.

**Options considered:**
- A) No DLQ (failed events disappear after visibility timeout expires)
- B) DLQ with low receive count (1-2 retries)
- C) DLQ with standard receive count (3 retries)

**Decision:** Option C — DLQ with `maxReceiveCount=3`.

**Rationale:**
- 3 retries filters transient failures (network blips, throttling) from persistent failures (bad event schema)
- Messages in the DLQ can be inspected and replayed once the root cause is fixed
- DLQ alarm fires immediately if any message arrives — zero tolerance for silent data loss in a health system

**Trade-off:** 3 retries means a persistent failure takes 3× the visibility timeout (90 seconds) to reach the DLQ. Accepted — correctness matters more than speed here.

---

## Decision 5: CloudWatch Over Third-Party Observability

**Context:** The pipeline needs metrics, alarms, and dashboards.

**Options considered:**
- A) CloudWatch (native AWS)
- B) Datadog
- C) Grafana + Prometheus

**Decision:** Option A — CloudWatch.

**Rationale:**
- Lambda, SQS, API Gateway, and DynamoDB all emit metrics to CloudWatch natively — zero instrumentation cost
- No additional infrastructure or agents to manage
- Free Tier covers 10 custom metrics and 10 alarms — sufficient for this project
- Metric filters on structured JSON logs are a native CloudWatch feature

**Trade-off:** CloudWatch dashboards are less flexible than Grafana. At scale (multi-region, multi-account), Datadog becomes the better choice. Accepted for a single-account, single-region project.

---

## Decision 6: `treat_missing_data = "breaching"` on Pipeline-Stall Alarm

**Context:** The pipeline-stall alarm fires when no events are processed for 10 minutes.

**Options considered:**
- A) `treat_missing_data = "notBreaching"` (no data = assume OK)
- B) `treat_missing_data = "breaching"` (no data = alarm fires)

**Decision:** Option B — breaching.

**Rationale:**
- The absence of data IS the failure condition being detected
- If the pipeline is silently stalled (Lambda throttled, SQS trigger disabled), no events flow and no metric is emitted
- With `notBreaching`, a completely dead pipeline would never alarm — the worst possible outcome for a health monitoring system

**Trade-off:** In dev environments that are intentionally idle, this alarm fires constantly. Accepted — the alarm correctly represents the system state. A production system would have environment-specific thresholds.

---

## Decision 7: Plan-Only CI/CD (No Auto-Apply)

**Context:** GitHub Actions runs on every push to main.

**Options considered:**
- A) Full CI/CD with auto-apply on push to main
- B) Plan-only CI (validate + plan, human applies)

**Decision:** Option B — plan-only.

**Rationale:**
- Infrastructure auto-apply without approval gates is high-risk
- A misconfigured Terraform change could destroy production resources
- Plan-only CI still proves the configuration is always valid and shows exactly what would change
- The correct production pattern is: plan in CI → human review → apply in CD with approval gate

**Known improvement:** Replace static IAM access keys in GitHub Secrets with OIDC federation — GitHub proves its identity to AWS without long-lived credentials, eliminating the credential rotation risk.

---

## Decision 8: Conventional Commits + Semantic Versioning

**Context:** Git history and changelog discipline.

**Decision:** Conventional Commits format with semantic versioning in CHANGELOG.

**Rationale:**
- Commit messages are machine-parseable — tooling can generate changelogs automatically
- `feat:`, `infra:`, `docs:`, `ci:`, `fix:` prefixes make the history scannable
- Semantic versioning in CHANGELOG maps each build step to a release
- `.terraform.lock.hcl` committed per HashiCorp recommendation — pins exact provider versions for reproducible builds

---

## What Would Be Different in Production

| Aspect | This Project | Production |
|---|---|---|
| Auth on API | None (open endpoint) | API keys or Cognito JWT |
| CI/CD credentials | Static IAM keys in GitHub Secrets | OIDC federation (no static keys) |
| CI/CD apply | Manual (`terraform apply`) | Automated with approval gate |
| Environments | `dev` only | `dev` → `staging` → `prod` |
| KMS keys | 1 key, all services | Per-service keys with separate rotation |
| DLQ handling | Manual inspection | Automated replay Lambda |
| Alerting | Email via SNS | PagerDuty/OpsGenie integration |
| Multi-region | Single region (ap-south-1) | Active-active or active-passive failover |
| Observability | CloudWatch only | CloudWatch + Datadog or Grafana |
