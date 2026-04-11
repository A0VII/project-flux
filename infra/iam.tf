# ============================================================
# IAM — Lambda execution role
#
# This role is "assumed" by Lambda when it runs. It defines
# exactly what AWS services Lambda is allowed to call.
# Principle: grant only the minimum permissions needed.
# ============================================================

# The trust policy — defines WHO can assume this role
# Only the Lambda service is allowed to use it
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    sid     = "AllowLambdaServiceToAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# The role itself
resource "aws_iam_role" "lambda_exec" {
  name               = "${var.project_name}-lambda-exec-${var.environment}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  description        = "Execution role for Project Flux Lambda functions"
}

# ── Managed policy: CloudWatch Logs (basic Lambda logging) ──
# AWSLambdaBasicExecutionRole is an AWS-managed policy that
# grants CreateLogGroup, CreateLogStream, PutLogEvents.
# We use the managed policy here because it's well-maintained
# by AWS and covers exactly this standard use case.
resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── Inline policy: S3 write access (events bucket only) ──
# We use an inline policy (not managed) because it's tightly
# scoped to a single specific resource — this role's bucket.
resource "aws_iam_role_policy" "lambda_s3" {
  name = "lambda-s3-events-write"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventsBucketWrite"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject"
        ]
        Resource = "${aws_s3_bucket.events.arn}/*"
      }
    ]
  })
}

# ── Inline policy: DynamoDB access (added in Step 6) ──
# Placeholder — we will add DynamoDB permissions when we
# create the table, to keep permissions and resources paired.

# ── Inline policy: SNS publish (added in Step 7) ──
# Placeholder — we will add SNS permissions when we
# create the topic, to keep permissions and resources paired.

# ── Inline policy: KMS decrypt (for reading encrypted data) ──
resource "aws_iam_role_policy" "lambda_kms" {
  name = "lambda-kms-decrypt"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowKMSDecryptForLambda"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.flux.arn
      }
    ]
  })
}
