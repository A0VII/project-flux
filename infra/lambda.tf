# ============================================================
# Lambda — Event processor function
#
# Triggered by SQS. Reads events, writes to S3 + DynamoDB,
# publishes SNS alerts for critical risk states.
# ============================================================

# ── Package the Lambda code into a zip file ──
# Terraform reads the Python file and creates the zip
# automatically — no manual zipping needed.
data "archive_file" "lambda_handler" {
  type        = "zip"
  source_file = "${path.module}/../src/lambda/handler.py"
  output_path = "${path.module}/../src/lambda/handler.zip"
}

# ── CloudWatch Log Group for Lambda ──
# Created explicitly so we can control retention and encryption.
# If we don't create it, Lambda creates it automatically
# with no retention limit and no encryption.
resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${var.project_name}-processor-${var.environment}"
  retention_in_days = 14
  kms_key_id        = aws_kms_key.flux.arn
}

# ── Lambda Function ──
resource "aws_lambda_function" "processor" {
  function_name = "${var.project_name}-processor-${var.environment}"
  description   = "Processes telemetry events from SQS — writes to S3 and DynamoDB"

  # The zip file Terraform created from our Python code
  filename         = data.archive_file.lambda_handler.output_path
  source_code_hash = data.archive_file.lambda_handler.output_base64sha256

  # Python runtime — use latest stable
  runtime = "python3.12"
  handler = "handler.handler"

  # IAM role the function assumes when it runs
  role = aws_iam_role.lambda_exec.arn

  # 30s timeout — matches SQS visibility timeout
  # If Lambda runs longer than this, SQS thinks it failed
  timeout = 30

  # Memory — 256MB is sufficient for JSON processing
  # More memory = more CPU (Lambda ties them together)
  memory_size = 256

  # Environment variables — no secrets here, just config
  # Secrets would go in AWS Secrets Manager
  environment {
    variables = {
      EVENTS_BUCKET = aws_s3_bucket.events.bucket
      DEVICE_TABLE  = aws_dynamodb_table.device_state.name
      SNS_TOPIC_ARN = aws_sns_topic.alerts.arn
      ENVIRONMENT   = var.environment
    }
  }

  # Ensure log group exists before function is created
  depends_on = [aws_cloudwatch_log_group.lambda]
}

# ── SQS Event Source Mapping ──
# This tells Lambda: "poll this SQS queue and invoke me with batches"
# AWS manages the polling loop — we don't write any polling code.
resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = aws_sqs_queue.events.arn
  function_name    = aws_lambda_function.processor.arn

  # Process up to 10 messages per Lambda invocation
  # Smaller batches = faster individual processing + easier debugging
  batch_size = 10

  # Enable partial batch failure reporting
  # Without this, one failure retries the entire batch
  function_response_types = ["ReportBatchItemFailures"]

  # Only invoke Lambda when there are messages waiting
  enabled = true
}
