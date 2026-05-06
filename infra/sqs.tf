# ============================================================
# SQS — Ingestion buffer between API Gateway and Lambda
#
# Two queues:
#   1. Main queue  — receives all incoming events
#   2. Dead Letter Queue (DLQ) — receives events that fail
#      processing after maxReceiveCount attempts
# ============================================================

resource "aws_sqs_queue" "events_dlq" {
  name                      = "${var.project_name}-events-dlq-${var.environment}"
  message_retention_seconds = 1209600
  kms_master_key_id         = aws_kms_key.flux.id

  tags = {
    Purpose = "Dead letter queue for failed event processing"
  }
}

resource "aws_sqs_queue" "events" {
  name                       = "${var.project_name}-events-${var.environment}"
  message_retention_seconds  = 86400
  visibility_timeout_seconds = 30
  kms_master_key_id          = aws_kms_key.flux.id

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.events_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Purpose = "Primary ingestion queue for telemetry events"
  }
}

resource "aws_sqs_queue_policy" "events" {
  queue_url = aws_sqs_queue.events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowAPIGatewayToSendMessages"
      Effect = "Allow"
      Principal = {
        Service = "apigateway.amazonaws.com"
      }
      Action   = "sqs:SendMessage"
      Resource = aws_sqs_queue.events.arn
      Condition = {
        ArnLike = {
          "aws:SourceArn" = "arn:aws:execute-api:${var.aws_region}:${var.aws_account_id}:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_sqs" {
  name = "lambda-sqs-consume"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowSQSConsume"
      Effect = "Allow"
      Action = [
        "sqs:ReceiveMessage",
        "sqs:DeleteMessage",
        "sqs:GetQueueAttributes",
        "sqs:ChangeMessageVisibility"
      ]
      Resource = [
        aws_sqs_queue.events.arn,
        aws_sqs_queue.events_dlq.arn
      ]
    }]
  })
}
