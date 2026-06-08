# Project Flux

> A production-grade serverless IoT telemetry pipeline — built on AWS with Terraform IaC, GitHub Actions CI/CD, CloudWatch observability, and end-to-end encrypted event processing.

---

## Architecture

```
Event Generator (Python)
        │  HTTPS POST /events
        ▼
  API Gateway ──────────────────────────────────┐
  (REGIONAL, ap-south-1)                        │ Access logs
        │  SQS SendMessage                       ▼
        │  (Lambda-less direct integration) CloudWatch Logs
        ▼
  SQS Queue ← DLQ (maxReceiveCount=3)
  (KMS encrypted, 30s visibility)
        │  Event source mapping (batch=10)
        │  ReportBatchItemFailures enabled
        ▼
  Lambda Processor (Python 3.12, 256MB, 30s)
        │  Structured JSON logging
        ├──────────────────┬──────────────────┐
        ▼                  ▼                  ▼
       S3               DynamoDB             SNS
  (raw archive)     (latest state)        (alerts)
  KMS encrypted     KMS + PITR + TTL    KMS encrypted
  time-partitioned  single-table index   email confirmed
  events/YYYY/MM/DD  per device_id        ↓
        │                  │           Gmail inbox
        └──────────────────┴──────────────────┐
                                              ▼
                                       CloudWatch
                              Logs + Metric Filters
                              Custom Metrics + Alarms
                              Dashboard (6 widgets)
```

---

## Stack

| Layer | Technology | Decision Rationale |
|---|---|---|
| IaC | Terraform + remote S3 state | Cloud-agnostic, industry standard, DynamoDB state locking |
| Ingestion | API Gateway → SQS (direct) | Lambda-less integration: lower latency, no cold start on ingest path |
| Compute | AWS Lambda Python 3.12 | Serverless, zero idle cost, scales to zero, Free Tier |
| Queue | SQS + DLQ | Buffered retry, poison-pill isolation, at-least-once delivery |
| Archive | S3 (time-partitioned) | Cheap durable storage, Athena-queryable, lifecycle rules |
| State index | DynamoDB (PAY_PER_REQUEST) | Single-millisecond reads for latest device state |
| Alerting | SNS → Email | Decoupled pub/sub, extensible to SMS/Slack/PagerDuty |
| Encryption | KMS CMK (all services) | Audit trail, cross-service reuse, annual rotation |
| Observability | CloudWatch | Native AWS, structured logs, metric filters, alarms, dashboard |
| CI/CD | GitHub Actions | Automated tfsec + validate + plan on every push |
| Security | IAM least privilege, MFA, CloudTrail | Zero wildcard Resource policies, scoped inline policies |

---

## Repository Structure

```
project-flux/
├── infra/                        # Terraform — all AWS infrastructure
│   ├── main.tf                   # Provider config + S3 remote state backend
│   ├── variables.tf              # Input variables with validation
│   ├── outputs.tf                # Exported ARNs and endpoints
│   ├── kms.tf                    # CMK with scoped principal policy
│   ├── s3.tf                     # Events archive bucket
│   ├── iam.tf                    # Lambda execution role
│   ├── sqs.tf                    # Ingestion queue + DLQ
│   ├── api_gateway.tf            # REST API + SQS direct integration
│   ├── lambda.tf                 # Function + SQS event source mapping
│   ├── dynamodb.tf               # Device state table
│   ├── observability.tf          # Metric filters + alarms + dashboard
│   ├── sns.tf                    # Alert topic + email subscription
│   └── .terraform.lock.hcl      # Provider version pins (committed)
├── src/
│   ├── lambda/handler.py         # Event processor — S3 + DynamoDB + SNS
│   └── generator/                # Synthetic event generator (Step 9)
├── .github/
│   └── workflows/                # GitHub Actions CI/CD pipeline (Step 8)
└── docs/
    ├── security-notes.md         # Account hardening decisions
    ├── cost-notes.md             # Free Tier coverage + cost drivers
    ├── runbook.md                # Operational runbook (Step 9)
    └── demo/                     # Portfolio screenshots + evidence
```

---

## Status

| Component | Status | Details |
|---|---|---|
| AWS account security | ✅ Complete | Root MFA, IAM user, zero-spend alarm, CloudTrail |
| Repository setup | ✅ Complete | Terraform v1.14.8, SSH auth, conventional commits |
| Core IaC — KMS, S3, IAM | ✅ Complete | CMK with rotation, encrypted S3, least-privilege roles |
| Ingestion pipeline | ✅ Complete | API Gateway → SQS direct, KMS encrypted, DLQ |
| Lambda processor | ✅ Complete | Python 3.12, partial batch failure, structured logs |
| Storage layer | ✅ Complete | S3 time-partitioned + DynamoDB latest-state index |
| Alerting — SNS | ✅ Complete | Email confirmed, Red events trigger real inbox alerts |
| Observability | ✅ Complete | 5 alarms, 3 metric filters, 6-widget dashboard live |
| CI/CD pipeline | ✅ Complete | GitHub Actions — tfsec + validate + plan, all green |
| Event generator | ✅ Complete | Python script: single / burst / scenario modes |
| End-to-end demo | ✅ Complete | Full scenario run, Red alert email, live dashboard |

---

## Verified Pipeline (end-to-end proof)

Every layer has been tested and verified live:

| Verification | Result |
|---|---|
| `POST /events` → HTTP 202 | ✅ API Gateway accepts events |
| SQS `receive-message` returns payload | ✅ KMS-encrypted queue confirmed |
| Lambda cold start | ✅ 520ms, warm 315–493ms, memory 98–99MB/256MB |
| S3 object at `events/YYYY/MM/DD/device_id/uuid.json` | ✅ KMS-encrypted, lifecycle rule active |
| DynamoDB item with all fields + TTL | ✅ Upserted correctly, expires in 90 days |
| CloudWatch structured JSON logs | ✅ Correlation IDs consistent across S3, DynamoDB, logs |
| SNS email for `risk_state=Red` | ✅ `[DEV] Critical Risk: Red — device-critical-001` received |
| CloudWatch dashboard live | ✅ EventsProcessed, CriticalRiskEvents, Duration, Queue Depth |
| pipeline-stall alarm fired | ✅ Correctly entered ALARM state when no events for 10min |

---

## Security Baseline

- Root account access keys: **never created**
- IAM policies: inline, scoped to exact resource ARNs — no wildcard `Resource: "*"`
- All data at rest: KMS CMK with annual rotation (`alias/project-flux-dev`)
- All data in transit: TLS (API Gateway, Lambda, S3, DynamoDB)
- S3 buckets: public access blocked at bucket level
- Terraform state: encrypted in S3, locked via DynamoDB, versioned
- CloudTrail: enabled (via KMS key audit trail)
- `.terraform.lock.hcl`: committed — pins exact provider versions per HashiCorp recommendation

---

## Cost

Runs entirely within the **AWS Free Tier** with one exception:

| Service | Status |
|---|---|
| Lambda, API Gateway, SQS, S3, DynamoDB, CloudWatch | ✅ Free Tier |
| KMS CMK | ⚠️ ~$1/month (1 key flat rate) |

Zero-spend budget alarm configured — any charge triggers immediate email notification.

---

## Key Design Decisions

**Why API Gateway → SQS directly (not via Lambda)?**
Fewer hops = lower latency, no cold start on the ingestion path. Lambda is only needed for processing, not receiving.

**Why S3 + DynamoDB instead of one storage system?**
S3 is cheap durable archival (source of truth). DynamoDB is fast indexed access (latest state for dashboards). Using both matches the tool to the job.

**Why `treat_missing_data = "breaching"` on the pipeline-stall alarm?**
Absence of events IS the failure condition being detected. No data means the pipeline is stalled.

**Why commit `.terraform.lock.hcl`?**
It pins exact provider versions so every developer and CI run uses identical providers — prevents silent breaking changes from provider updates.

---

