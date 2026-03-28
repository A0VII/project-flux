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
