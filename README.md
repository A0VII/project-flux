# Project Flux

> Serverless IoT telemetry ingestion and monitoring pipeline — built on AWS with Terraform, GitHub Actions CI/CD, and CloudWatch observability.

## Architecture
```
Event Generator (Python)
        │
        ▼
  API Gateway (HTTPS)
        │
        ▼
   SQS Queue (buffer + retry)
        │
        ▼
  Lambda (validate + transform)
   ┌─────┴──────┐──────────┐
   ▼            ▼          ▼
  S3          DynamoDB    SNS
(archive)  (latest state) (alerts)
                │
                ▼
          CloudWatch
    (Logs + Alarms + Dashboard)
```

## Stack

| Layer | Technology | Why |
|---|---|---|
| IaC | Terraform | Industry standard, cloud-agnostic |
| Compute | AWS Lambda | Serverless, free tier, no idle cost |
| Ingestion | API Gateway + SQS | Buffered, retry-safe ingestion |
| Storage | S3 + DynamoDB | Archive + indexed state, purpose-matched |
| Alerting | SNS | Decoupled, extensible alert routing |
| Observability | CloudWatch | Native AWS, structured logs, dashboards |
| CI/CD | GitHub Actions | Automated lint + security scan + deploy |

## Repository Structure
```
project-flux/
├── infra/          # Terraform — all AWS infrastructure as code
├── src/
│   ├── lambda/     # Lambda function (Python)
│   └── generator/  # Synthetic event generator (Python)
├── .github/
│   └── workflows/  # GitHub Actions CI/CD pipeline
└── docs/
    ├── security-notes.md
    ├── runbook.md       (added during build)
    ├── cost-notes.md    (added during build)
    └── demo/            # Screenshots + demo video
```

## Status

🔨 **In active development** — building step by step.

| Component | Status |
|---|---|
| AWS account security | ✅ Done |
| Repository setup | ✅ Done |
| Core IaC (S3, KMS, IAM) | 🔨 In progress |
| Ingestion pipeline | ⏳ Pending |
| Lambda processor | ⏳ Pending |
| Storage layer | ⏳ Pending |
| Alerting | ⏳ Pending |
| Observability | ⏳ Pending |
| CI/CD pipeline | ⏳ Pending |
| End-to-end demo | ⏳ Pending |

## Cost

Designed to run entirely within the **AWS Free Tier**. Budget alarm set at $0 — any charge triggers immediate notification.

---

*Built as a portfolio project demonstrating end-to-end AWS cloud engineering.*
