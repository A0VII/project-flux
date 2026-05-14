# ============================================================
# DynamoDB — Latest device state index
#
# Stores only the most recent state per device.
# NOT a full event history — that lives in S3.
#
# Design: single-table, device_id as partition key.
# No sort key needed — we only ever read/write one item
# per device (the latest state).
# ============================================================

resource "aws_dynamodb_table" "device_state" {
  name         = "${var.project_name}-device-state-${var.environment}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "device_id"

  attribute {
    name = "device_id"
    type = "S"
  }

  # Encrypt at rest using our CMK
  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.flux.arn
  }

  # Point-in-time recovery — allows restoring to any second
  # in the last 35 days. Free for dev, essential for prod.
  point_in_time_recovery {
    enabled = true
  }

  # TTL — automatically expire old records after 90 days
  # Prevents unbounded table growth in dev
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = {
    Purpose = "Latest device state index for real-time queries"
  }
}

# ── Extend Lambda IAM role — add DynamoDB permissions ──
resource "aws_iam_role_policy" "lambda_dynamodb" {
  name = "lambda-dynamodb-write"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowDynamoDBReadWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:PutItem",
          "dynamodb:GetItem",
          "dynamodb:UpdateItem",
          "dynamodb:Query"
        ]
        Resource = aws_dynamodb_table.device_state.arn
      }
    ]
  })
}
