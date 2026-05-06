# Changelog

All notable changes to Project Flux are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [Unreleased]

### In Progress
- Core infrastructure IaC (S3, KMS, IAM roles)

---

## [0.1.0] — 2026-03-28 — Repository Bootstrap

### Added
- Repository structure: `/infra`, `/src/lambda`, `/src/generator`, `/docs`, `/.github/workflows`
- `.gitignore` covering Terraform state, AWS credentials, Python artifacts
- `README.md` with architecture overview and build status tracker
- `docs/security-notes.md` documenting account security baseline

### Security
- Root account MFA enabled
- IAM user `z.admin01` created (AdministratorAccess, MFA enabled)
- AWS CLI configured with IAM user credentials only — root access keys never created
- Zero-spend billing alarm configured

---

## [0.2.0] — 2026-04-11 — Core Infrastructure

### Added
- Terraform remote state: S3 backend + DynamoDB lock table (bootstrapped via CLI)
- KMS Customer Managed Key with annual rotation and scoped principal policy
- S3 events bucket: KMS encryption, versioning, public access blocked, lifecycle rules
- IAM Lambda execution role with least-privilege inline policies
- `infra/variables.tf` with input validation (environment enum guard)
- `infra/outputs.tf` exposing ARNs and names for downstream modules

### Security
- All S3 objects encrypted at rest with CMK (not AWS-managed key)
- IAM policies scoped to exact resource ARNs — no wildcard Resources
- S3 bucket public access blocked at bucket level
- Terraform state encrypted at rest in S3

### Infrastructure
- Terraform backend: `project-flux-tfstate-507221376720` (ap-south-1)
- State lock: DynamoDB table `project-flux-tfstate-lock`

## [0.3.0] — $(date +%Y-%m-%d) — Ingestion Pipeline

### Added
- SQS events queue: KMS encrypted, 1-day retention, 30s visibility timeout
- SQS Dead Letter Queue: 14-day retention, captures events after 3 failed attempts
- SQS queue policy: restricts SendMessage to API Gateway service principal only
- API Gateway REST API: POST /events endpoint (REGIONAL, ap-south-1)
- API Gateway → SQS direct service integration (no Lambda on ingestion path)
- API Gateway stage dev: JSON-structured access logging to CloudWatch (14d)
- API Gateway account-level CloudWatch logging role registered
- Lambda IAM policy extended: SQS consume permissions on main queue and DLQ
- docs/cost-notes.md: cost driver analysis and free tier coverage table

### Design Decisions
- Lambda-less API Gateway → SQS integration: lower latency on ingestion path
- HTTP 202 Accepted: correct semantics for asynchronous event processing
- DLQ pattern: prevents poison pill messages from blocking queue indefinitely
- KMS permissions on API Gateway IAM role: required for CMK-encrypted queues

### Verified
- curl POST /events returns HTTP 202
- SQS receive-message returns full event payload (end-to-end confirmed)
