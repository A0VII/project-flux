# Project Flux — Operational Runbook

> How to deploy, demo, troubleshoot, and tear down the pipeline.

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Terraform | 1.14.8+ | HashiCorp RPM repo |
| AWS CLI | v2 | `aws configure` with `z.admin01` credentials |
| Python | 3.12+ | System default |
| Git | any | SSH auth to GitHub |

Verify everything is ready:

```bash
terraform -version
aws sts get-caller-identity
python3 --version
git remote -v
```

---

## Deploy from Scratch

```bash
# 1. Clone the repository
git clone git@github.com:A0VII/project-flux.git
cd project-flux

# 2. Deploy all infrastructure
cd infra
terraform init
terraform plan
terraform apply

# 3. Confirm outputs
terraform output
```

Expected outputs: API endpoint, Lambda ARN, DynamoDB table, S3 bucket, SNS topic, dashboard URL.

**After first deploy:** Check your email for the SNS subscription confirmation and click the link before running the demo.

---

## Run the Demo

### Setup

```bash
export API_ENDPOINT=$(cd infra && terraform output -raw api_endpoint)
```

### Single event (sanity check)

```bash
python3 src/generator/send_events.py --mode single
```

Expected: `✅ [  1] Green | HTTP 202`

### Full scenario (interview demo)

```bash
python3 src/generator/send_events.py --mode scenario
```

Expected sequence:
1. Green heartbeats (normal operation)
2. Yellow state changes (degradation detected)
3. Red alert fired → email arrives in inbox within 60 seconds
4. Recovery back to Green
5. Session end

**Watch simultaneously:**
- Terminal: coloured event stream
- Gmail: Red alert email arrives mid-run
- CloudWatch dashboard: `EventsProcessed` increments in real time

CloudWatch dashboard URL: https://ap-south-1.console.aws.amazon.com/cloudwatch/home?region=ap-south-1#dashboards:name=project-flux-dev

### Burst test (load simulation)

```bash
python3 src/generator/send_events.py --mode burst --count 20 --delay 0.3
```

---

## Verify the Pipeline

After running events, verify each layer individually:

```bash
# 1. Check Lambda processed events (last 10 log entries)
aws logs filter-log-events \
  --log-group-name "/aws/lambda/project-flux-processor-dev" \
  --filter-pattern "Event processed successfully" \
  --limit 10 \
  --query "events[*].message" \
  --output text

# 2. Check most recent S3 object
aws s3 ls s3://project-flux-events-dev-507221376720/events/ \
  --recursive \
  --human-readable \
  | sort | tail -5

# 3. Check DynamoDB for device state
aws dynamodb get-item \
  --table-name project-flux-device-state-dev \
  --key '{"device_id": {"S": "device-demo-001"}}' \
  --output json

# 4. Check all alarm states
aws cloudwatch describe-alarms \
  --alarm-name-prefix "project-flux" \
  --query "MetricAlarms[*].{Name:AlarmName,State:StateValue}" \
  --output table

# 5. Check SQS — confirm queue is empty (all processed)
aws sqs get-queue-attributes \
  --queue-url $(cd infra && terraform output -raw sqs_queue_url) \
  --attribute-names ApproximateNumberOfMessages \
  --query "Attributes.ApproximateNumberOfMessages"
```

---

## Troubleshoot Common Issues

### Events accepted (HTTP 202) but nothing in Lambda logs

**Cause:** SQS visibility timeout — Lambda may not have triggered yet.
**Fix:** Wait 30 seconds and recheck. If DLQ has messages, Lambda failed silently.

```bash
# Check DLQ
aws sqs get-queue-attributes \
  --queue-url https://sqs.ap-south-1.amazonaws.com/507221376720/project-flux-events-dlq-dev \
  --attribute-names ApproximateNumberOfMessages
```

### Red event sent but no email received

**Cause 1:** SNS subscription not confirmed — check AWS SNS console for `PendingConfirmation`.
**Cause 2:** Email in spam — search `from:no-reply@sns.amazonaws.com`.
**Cause 3:** KMS key policy missing SNS/CloudWatch principals — run `terraform apply` to fix.

### Lambda errors in CloudWatch

```bash
# Get recent error logs
aws logs filter-log-events \
  --log-group-name "/aws/lambda/project-flux-processor-dev" \
  --filter-pattern "ERROR" \
  --limit 5 \
  --query "events[*].message" \
  --output text
```

### `API_ENDPOINT` not set

```bash
export API_ENDPOINT=$(cd infra && terraform output -raw api_endpoint)
```

---

## Key Resource References

| Resource | Identifier |
|---|---|
| API endpoint | `https://zrjal44k1h.execute-api.ap-south-1.amazonaws.com/dev/events` |
| Lambda function | `project-flux-processor-dev` |
| SQS queue | `project-flux-events-dev` |
| SQS DLQ | `project-flux-events-dlq-dev` |
| S3 bucket | `project-flux-events-dev-507221376720` |
| DynamoDB table | `project-flux-device-state-dev` |
| SNS topic | `arn:aws:sns:ap-south-1:507221376720:project-flux-alerts-dev` |
| KMS key alias | `alias/project-flux-dev` |
| CloudWatch dashboard | `project-flux-dev` |
| Terraform state bucket | `project-flux-tfstate-507221376720` |

---

## Tear Down

```bash
cd infra

# Remove all AWS resources
terraform destroy

# Confirm by typing: yes
```

**Note:** KMS keys enter a 7-day deletion pending window — they cannot be destroyed immediately. The S3 buckets must be emptied before Terraform can delete them if they contain objects.

```bash
# Empty buckets before destroy if needed
aws s3 rm s3://project-flux-events-dev-507221376720 --recursive
aws s3 rm s3://project-flux-tfstate-507221376720 --recursive
```
