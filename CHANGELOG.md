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
