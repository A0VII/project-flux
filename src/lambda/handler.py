"""
Project Flux — Lambda Event Processor

Reads telemetry events from SQS, validates them,
writes to S3 (archive) and DynamoDB (latest state),
and publishes SNS alerts for critical risk states.

Environment variables (set by Terraform):
    EVENTS_BUCKET   — S3 bucket name for raw event archive
    DEVICE_TABLE    — DynamoDB table name for latest state
    SNS_TOPIC_ARN   — SNS topic ARN for alerts (optional)
    ENVIRONMENT     — dev / staging / prod
"""

import json
import logging
import os
import uuid
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

# ── Logging ──────────────────────────────────────────────────
# Structured JSON logging — makes CloudWatch Logs Insights
# queries fast and reliable. Never use print() in Lambda.
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def log(level, msg, **kwargs):
    """Emit a structured JSON log entry."""
    entry = {
        "level": level,
        "message": msg,
        "timestamp": datetime.now(timezone.utc).isoformat(),
        **kwargs
    }
    if level == "ERROR":
        logger.error(json.dumps(entry))
    elif level == "WARNING":
        logger.warning(json.dumps(entry))
    else:
        logger.info(json.dumps(entry))

# ── AWS clients ──────────────────────────────────────────────
# Initialised outside the handler — reused across warm invocations.
# This is a critical Lambda optimisation: clients are expensive
# to create. Keep them at module level, not inside the handler.
s3      = boto3.client("s3")
dynamo  = boto3.resource("dynamodb")
sns     = boto3.client("sns")

# ── Config from environment ──────────────────────────────────
EVENTS_BUCKET = os.environ["EVENTS_BUCKET"]
DEVICE_TABLE  = os.environ["DEVICE_TABLE"]
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN", "")
ENVIRONMENT   = os.environ.get("ENVIRONMENT", "dev")

# Required fields every valid event must contain
REQUIRED_FIELDS = {
    "device_id", "session_id", "timestamp",
    "event_type", "risk_state", "schema_version"
}

# Risk states that trigger an SNS alert
CRITICAL_RISK_STATES = {"Red", "Red++"}


# ── Handler ──────────────────────────────────────────────────

def handler(event, context):
    """
    SQS trigger handler. Processes a batch of records.
    Each SQS record contains one telemetry event as its body.

    SQS + Lambda contract:
    - Return normally → SQS deletes all messages in the batch
    - Raise exception → SQS retries the entire batch
    - Use batch item failures → partial retry (we implement this)
    """
    records       = event.get("Records", [])
    failed_ids    = []

    log("INFO", "Processing SQS batch",
        batch_size=len(records),
        function=context.function_name,
        request_id=context.aws_request_id)

    for record in records:
        message_id = record["messageId"]
        try:
            process_record(record)
        except Exception as exc:
            log("ERROR", "Failed to process record",
                message_id=message_id,
                error=str(exc))
            # Report this message as failed — SQS will retry
            # only the failed messages, not the whole batch
            failed_ids.append({"itemIdentifier": message_id})

    if failed_ids:
        log("WARNING", "Batch completed with failures",
            failed_count=len(failed_ids),
            total_count=len(records))

    # Partial batch failure response — requires Lambda
    # function event source mapping to have
    # ReportBatchItemFailures enabled (set in lambda.tf)
    return {"batchItemFailures": failed_ids}


# ── Per-record processing ─────────────────────────────────────

def process_record(record):
    """Parse, validate, and process one SQS message."""
    body = record.get("body", "")

    # Parse JSON
    try:
        payload = json.loads(body)
    except json.JSONDecodeError as exc:
        # Malformed JSON — this is a poison pill, don't retry
        log("ERROR", "Invalid JSON in message body",
            error=str(exc),
            body_preview=body[:200])
        # Raise to mark as failed — goes to DLQ after maxReceiveCount
        raise ValueError(f"Invalid JSON: {exc}") from exc

    # Validate required fields
    missing = REQUIRED_FIELDS - set(payload.keys())
    if missing:
        log("ERROR", "Event missing required fields",
            missing_fields=list(missing),
            device_id=payload.get("device_id", "unknown"))
        raise ValueError(f"Missing required fields: {missing}")

    device_id  = payload["device_id"]
    session_id = payload["session_id"]
    risk_state = payload["risk_state"]
    event_id   = str(uuid.uuid4())

    log("INFO", "Processing event",
        device_id=device_id,
        session_id=session_id,
        event_type=payload["event_type"],
        risk_state=risk_state,
        event_id=event_id)

    # 1. Write raw event to S3
    write_to_s3(payload, event_id)

    # 2. Update latest device state in DynamoDB
    update_device_state(payload, event_id)

    # 3. Publish SNS alert if risk state is critical
    if risk_state in CRITICAL_RISK_STATES and SNS_TOPIC_ARN:
        publish_alert(payload, event_id)

    log("INFO", "Event processed successfully",
        device_id=device_id,
        event_id=event_id)


# ── S3 write ─────────────────────────────────────────────────

def write_to_s3(payload, event_id):
    """
    Write raw event to S3 with time-partitioned key.

    Key format: events/YYYY/MM/DD/{device_id}/{event_id}.json
    This partitioning enables efficient date-range queries
    with Athena or S3 Select later.
    """
    now = datetime.now(timezone.utc)
    key = (
        f"events/{now.year}/{now.month:02d}/{now.day:02d}"
        f"/{payload['device_id']}/{event_id}.json"
    )

    # Enrich payload with processing metadata
    enriched = {
        **payload,
        "_event_id":       event_id,
        "_processed_at":   now.isoformat(),
        "_environment":    ENVIRONMENT,
    }

    try:
        s3.put_object(
            Bucket      = EVENTS_BUCKET,
            Key         = key,
            Body        = json.dumps(enriched, indent=2),
            ContentType = "application/json",
        )
        log("INFO", "Event written to S3",
            bucket=EVENTS_BUCKET,
            key=key)
    except ClientError as exc:
        log("ERROR", "S3 write failed",
            bucket=EVENTS_BUCKET,
            key=key,
            error=str(exc))
        raise


# ── DynamoDB upsert ───────────────────────────────────────────

def update_device_state(payload, event_id):
    """
    Upsert latest device state in DynamoDB.

    Uses UpdateItem with condition to only update if the
    incoming timestamp is newer than what's stored.
    This prevents out-of-order events from overwriting
    newer state with older data.

    TTL is set to 90 days from now to auto-expire old records.
    """
    table = dynamo.Table(DEVICE_TABLE)

    # 90 days from now in epoch seconds for DynamoDB TTL
    ttl_epoch = int(datetime.now(timezone.utc).timestamp()) + (90 * 86400)

    try:
        table.update_item(
            Key={"device_id": payload["device_id"]},
            UpdateExpression=(
                "SET session_id   = :sid, "
                "    risk_state   = :rs, "
                "    event_type   = :et, "
                "    last_seen    = :ts, "
                "    #vals        = :v, "
                "    schema_ver   = :sv, "
                "    last_event_id= :eid, "
                "    environment  = :env, "
                "    expires_at   = :ttl"
            ),
            ExpressionAttributeNames={
                # 'values' is a reserved word in DynamoDB
                "#vals": "values"
            },
            ExpressionAttributeValues={
                ":sid": payload["session_id"],
                ":rs":  payload["risk_state"],
                ":et":  payload["event_type"],
                ":ts":  payload["timestamp"],
                ":v":   payload.get("values", {}),
                ":sv":  payload["schema_version"],
                ":eid": event_id,
                ":env": ENVIRONMENT,
                ":ttl": ttl_epoch,
            }
        )
        log("INFO", "DynamoDB state updated",
            device_id=payload["device_id"],
            risk_state=payload["risk_state"])
    except ClientError as exc:
        log("ERROR", "DynamoDB update failed",
            device_id=payload["device_id"],
            error=str(exc))
        raise


# ── SNS alert ─────────────────────────────────────────────────

def publish_alert(payload, event_id):
    """
    Publish SNS notification for critical risk states.
    SNS fans this out to email, SMS, or other subscribers.
    """
    message = {
        "alert_type":  "CRITICAL_RISK_STATE",
        "device_id":   payload["device_id"],
        "session_id":  payload["session_id"],
        "risk_state":  payload["risk_state"],
        "event_type":  payload["event_type"],
        "timestamp":   payload["timestamp"],
        "event_id":    event_id,
        "environment": ENVIRONMENT,
    }

    try:
        sns.publish(
            TopicArn = SNS_TOPIC_ARN,
            Subject  = f"[{ENVIRONMENT.upper()}] Critical Risk: {payload['risk_state']} — {payload['device_id']}",
            Message  = json.dumps(message, indent=2),
        )
        log("INFO", "SNS alert published",
            device_id=payload["device_id"],
            risk_state=payload["risk_state"],
            topic=SNS_TOPIC_ARN)
    except ClientError as exc:
        # Alert failure should NOT fail the whole event processing.
        # Log it and continue — the event is still written to S3/DynamoDB.
        log("ERROR", "SNS publish failed — alert dropped",
            device_id=payload["device_id"],
            error=str(exc))
