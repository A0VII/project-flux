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

## [0.4.0] — 2026-05-11 — Lambda Processor and Storage Layer

### Added
- Lambda function project-flux-processor-dev (python3.12, 256MB, 30s timeout)
- SQS event source mapping: batch_size=10, ReportBatchItemFailures enabled
- DynamoDB table project-flux-device-state-dev: PAY_PER_REQUEST, KMS, PITR, TTL
- CloudWatch log group for Lambda: 14-day retention, KMS encrypted
- Lambda IAM policies: DynamoDB read/write on device-state table
- Archive Terraform provider for automated Lambda zip packaging
- src/lambda/handler.py: full event processor with structured logging
- docs/demo/: 7 portfolio screenshots covering all pipeline layers

### Architecture
- S3 pattern: time-partitioned keys events/YYYY/MM/DD/device_id/event_id.json
- DynamoDB pattern: single-table latest-state index per device_id with TTL
- Partial batch failure: failed SQS messages retry individually
- AWS clients at module level for warm invocation reuse
- SNS alert path implemented, wired to topic in Step 7

### Fixed
- .gitignore: committed .terraform.lock.hcl per HashiCorp recommendation
- .gitignore: excluded src/lambda/handler.zip build artifact

### Verified
- Full pipeline: curl -> API Gateway -> SQS -> Lambda -> S3 + DynamoDB
- Cold start: 520ms | Processing: 315ms | Memory: 98MB/256MB
- Correlation ID consistent across S3 key, DynamoDB record, CloudWatch logs
- Structured JSON logs confirmed in CloudWatch Log Management console

## [0.5.0] — 2026-05-17 — CloudWatch Observability

### Added
- SNS topic project-flux-alerts-dev: KMS encrypted, receives all alarm notifications
- CloudWatch metric filter: EventsProcessed (custom namespace ProjectFlux/dev)
- CloudWatch metric filter: ProcessingErrors (ERROR level log pattern)
- CloudWatch metric filter: CriticalRiskEvents (SNS alert published pattern)
- CloudWatch alarm: lambda-errors (threshold 1, 5min window)
- CloudWatch alarm: pipeline-stall (LessThan 1 event/10min, treat_missing=breaching)
- CloudWatch alarm: dlq-not-empty (threshold 0 — any DLQ message triggers)
- CloudWatch alarm: lambda-slow (p95 Duration > 20000ms)
- CloudWatch alarm: queue-depth (SQS backlog > 100)
- CloudWatch dashboard project-flux-dev: 6 widgets + alarm status panel

### Design Decisions
- treat_missing_data=breaching on pipeline-stall: absence of events IS the problem
- treat_missing_data=notBreaching on error/DLQ alarms: no data means nothing bad
- Custom metric namespace ProjectFlux/dev separates app metrics from AWS/Lambda
- Dashboard threshold annotations show warn/timeout boundaries on duration widget

### Verified
- Dashboard live and rendering all 6 widgets
- pipeline-stall alarm correctly entered ALARM state (working as designed)
- lambda-errors alarm correctly in OK state
