# Security Notes — Project Flux

## Account Security Baseline

### Controls Implemented
- Root account MFA: enabled (authenticator app)
- IAM user `z.admin01` created with AdministratorAccess policy
- IAM user MFA: enabled (authenticator app)
- AWS CLI configured with IAM user access keys (never root keys)
- Billing alarm: $0 spend threshold (email alert)
- Default region: ap-south-1 (Mumbai)

### Design Decisions
- AdministratorAccess used on IAM user for development velocity.
  Production hardening: replace with scoped policy per service.
- Root account access keys: NOT created (AWS best practice).
- Access keys stored only in ~/.aws/credentials (never committed to git).

### What We Intentionally Deferred
- Service Control Policies (SCPs) — requires AWS Organizations, overkill for solo project
- AWS Config rules — post-MVP
- GuardDuty — post-MVP
