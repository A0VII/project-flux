# ============================================================
# SNS — Email subscription for alerts
#
# The SNS topic itself was created in observability.tf.
# This file adds the email subscription and Lambda SNS policy.
#
# Why separate file?
# Subscriptions are runtime configuration (your email address)
# while the topic is infrastructure. Keeping them separate
# means you can update subscriptions without touching alarms.
# ============================================================

# ── Email subscription ──
# After apply, AWS sends a confirmation email.
# You MUST click "Confirm subscription" or no emails arrive.
resource "aws_sns_topic_subscription" "email_alerts" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ── Allow Lambda to publish to the SNS topic ──
resource "aws_iam_role_policy" "lambda_sns" {
  name = "lambda-sns-publish"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSNSPublish"
        Effect = "Allow"
        Action = ["sns:Publish"]
        Resource = aws_sns_topic.alerts.arn
      }
    ]
  })
}
