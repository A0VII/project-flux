# Cost Notes — Project Flux

## Free Tier Coverage (ap-south-1, dev)

| Service | Free Tier | Expected Usage | Status |
|---|---|---|---|
| API Gateway | 1M calls/month | ~1,000 test calls | ✅ Free |
| SQS | 1M requests/month | ~1,000 messages | ✅ Free |
| Lambda | 1M requests/month | ~1,000 invocations | ✅ Free |
| S3 | 5GB + 2K PUTs | Tiny | ✅ Free |
| DynamoDB | 25GB + 25 WCU/RCU | Tiny | ✅ Free |
| CloudWatch | 10 metrics, 5GB logs | Within limit | ✅ Free |
| KMS CMK | $1/month per key | 1 key | ⚠️ ~$1/month |

## Primary Cost Drivers

- **KMS CMK:** $1/month flat — the only real cost in this project.
- **CloudWatch Logs:** charged per GB beyond 5GB free tier.
  Mitigation: 14-day retention cap on all log groups.
- **S3:** charged per PUT beyond free tier.
  Mitigation: 90-day expiry lifecycle rule on events bucket.

## Design Decisions for Cost Control

- API Gateway → SQS direct integration: eliminates one Lambda
  invocation per event on the ingestion path.
- S3 lifecycle: STANDARD_IA at 30 days, expire at 90 days.
- CloudWatch log retention: 14 days on all log groups.
- SQS message retention: 1 day (events process quickly in dev).
- DynamoDB: PAY_PER_REQUEST billing — zero cost at near-zero traffic.

## Budget Guardrail

Zero-spend billing alarm configured on AWS account.
Any charge triggers immediate email notification.
