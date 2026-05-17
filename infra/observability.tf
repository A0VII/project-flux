# ============================================================
# CloudWatch Observability — Metric filters, alarms, dashboard
#
# Architecture:
#   Structured logs → Metric filters → Custom metrics
#   Custom metrics + AWS metrics → Alarms → SNS (Step 7)
#   All metrics → Dashboard (single-pane view)
# ============================================================

# ── SNS topic placeholder for alarm actions ──
# We create the topic here so alarms can reference it.
# Subscriptions (email/SMS) are added in Step 7.
resource "aws_sns_topic" "alerts" {
  name              = "${var.project_name}-alerts-${var.environment}"
  kms_master_key_id = aws_kms_key.flux.id
}

# ============================================================
# METRIC FILTERS
# Extract structured data from Lambda JSON logs.
# Each filter creates a custom CloudWatch metric from a
# pattern match against the log stream.
# ============================================================

# ── Filter 1: Count successfully processed events ──
resource "aws_cloudwatch_log_metric_filter" "events_processed" {
  name           = "${var.project_name}-events-processed-${var.environment}"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  pattern        = "{ $.message = \"Event processed successfully\" }"

  metric_transformation {
    name          = "EventsProcessed"
    namespace     = "ProjectFlux/${var.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ── Filter 2: Count processing errors ──
resource "aws_cloudwatch_log_metric_filter" "processing_errors" {
  name           = "${var.project_name}-processing-errors-${var.environment}"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  pattern        = "{ $.level = \"ERROR\" }"

  metric_transformation {
    name          = "ProcessingErrors"
    namespace     = "ProjectFlux/${var.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ── Filter 3: Count critical risk state events ──
# This is the business logic alert — fires when a Red event
# flows through the pipeline
resource "aws_cloudwatch_log_metric_filter" "critical_risk_events" {
  name           = "${var.project_name}-critical-risk-${var.environment}"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  pattern        = "{ $.message = \"SNS alert published\" }"

  metric_transformation {
    name          = "CriticalRiskEvents"
    namespace     = "ProjectFlux/${var.environment}"
    value         = "1"
    default_value = "0"
    unit          = "Count"
  }
}

# ============================================================
# ALARMS
# Each alarm watches one metric and fires when a threshold
# is crossed. Actions go to SNS → email (wired in Step 7).
# ============================================================

# ── Alarm 1: Lambda error rate too high ──
# Fires if more than 1 error occurs in any 5-minute window.
# This is your primary health signal — if Lambda is broken,
# events are not being processed.
resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${var.project_name}-lambda-errors-${var.environment}"
  alarm_description   = "Lambda processor error rate is elevated"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
  ok_actions    = [aws_sns_topic.alerts.arn]
}

# ── Alarm 2: No events processed (pipeline stall) ──
# Fires if zero events are processed in 10 minutes.
# This catches the case where events are queued but Lambda
# is not consuming them — silent failure mode.
resource "aws_cloudwatch_metric_alarm" "pipeline_stall" {
  alarm_name          = "${var.project_name}-pipeline-stall-${var.environment}"
  alarm_description   = "No events processed in the last 10 minutes"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "EventsProcessed"
  namespace           = "ProjectFlux/${var.environment}"
  period              = 600
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "breaching"

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── Alarm 3: SQS DLQ has messages ──
# Any message in the DLQ means an event failed after 3 retries.
# This is always worth investigating.
resource "aws_cloudwatch_metric_alarm" "dlq_messages" {
  alarm_name          = "${var.project_name}-dlq-not-empty-${var.environment}"
  alarm_description   = "Messages have arrived in the Dead Letter Queue"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.events_dlq.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── Alarm 4: Lambda duration approaching timeout ──
# Fires if p95 execution time exceeds 20 seconds.
# Our timeout is 30s — this gives a 10s warning buffer.
# If Lambda regularly approaches its timeout, something is wrong.
resource "aws_cloudwatch_metric_alarm" "lambda_duration" {
  alarm_name          = "${var.project_name}-lambda-slow-${var.environment}"
  alarm_description   = "Lambda p95 duration exceeding 20 seconds — approaching timeout"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p95"
  threshold           = 20000
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.processor.function_name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── Alarm 5: SQS queue growing (Lambda not keeping up) ──
# If more than 100 messages queue up, Lambda is falling behind.
resource "aws_cloudwatch_metric_alarm" "sqs_queue_depth" {
  alarm_name          = "${var.project_name}-queue-depth-${var.environment}"
  alarm_description   = "SQS queue depth exceeds 100 — Lambda may be falling behind"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 300
  statistic           = "Average"
  threshold           = 100
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.events.name
  }

  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ============================================================
# DASHBOARD
# Single-pane view of system health.
# A recruiter or interviewer can look at this and immediately
# understand the system's operational state.
# ============================================================





resource "aws_cloudwatch_dashboard" "flux" {
  dashboard_name = "${var.project_name}-${var.environment}"

  dashboard_body = jsonencode({
    widgets = [
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Events Processed"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["ProjectFlux/${var.environment}", "EventsProcessed",
              { stat = "Sum", period = 60, label = "Events/min" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 0
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Errors"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Errors", "FunctionName",
              aws_lambda_function.processor.function_name,
              { stat = "Sum", period = 60, label = "Errors" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "Lambda Duration (ms)"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName",
              aws_lambda_function.processor.function_name,
              { stat = "Average", period = 60, label = "Average" }],
            ["AWS/Lambda", "Duration", "FunctionName",
              aws_lambda_function.processor.function_name,
              { stat = "p95", period = 60, label = "p95" }]
          ]
          annotations = {
            horizontal = [
              { value = 20000, label = "Warn 20s", color = "#ff7f0e" },
              { value = 30000, label = "Timeout 30s", color = "#d13212" }
            ]
          }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "SQS Queue Depth"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible",
              "QueueName", aws_sqs_queue.events.name,
              { stat = "Average", period = 60, label = "Main Queue" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible",
              "QueueName", aws_sqs_queue.events_dlq.name,
              { stat = "Average", period = 60, color = "#d13212", label = "DLQ" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "Critical Risk Events"
          view   = "timeSeries"
          region = var.aws_region
          metrics = [
            ["ProjectFlux/${var.environment}", "CriticalRiskEvents",
              { stat = "Sum", period = 60, color = "#d13212", label = "Red Events" }]
          ]
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "alarm"
        x      = 0
        y      = 18
        width  = 24
        height = 4
        properties = {
          title = "Alarm Status"
          alarms = [
            aws_cloudwatch_metric_alarm.lambda_errors.arn,
            aws_cloudwatch_metric_alarm.pipeline_stall.arn,
            aws_cloudwatch_metric_alarm.dlq_messages.arn,
            aws_cloudwatch_metric_alarm.lambda_duration.arn,
            aws_cloudwatch_metric_alarm.sqs_queue_depth.arn
          ]
        }
      }
    ]
  })
}
