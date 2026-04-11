# ============================================================
# KMS — Customer Managed Key for encryption at rest
#
# Why a CMK instead of AWS-managed keys?
# AWS-managed keys (aws/s3, aws/lambda) are free and automatic,
# but you can't control their rotation, audit their usage in
# detail, or use them across services. A CMK gives us:
#   - Explicit rotation policy (annual)
#   - Detailed CloudTrail logs of every encrypt/decrypt call
#   - One key that all Project Flux resources share
# ============================================================

resource "aws_kms_key" "flux" {
  description             = "Project Flux — encryption key for all data at rest"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Root account has full key administration rights
        Sid    = "EnableRootAccountAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.aws_account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        # Lambda role can use the key to encrypt/decrypt data
        Sid    = "AllowLambdaEncryption"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_role.lambda_exec.arn
        }
        Action = [
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      },
      {
        # CloudWatch Logs needs to use the key to encrypt log groups
        Sid    = "AllowCloudWatchLogs"
        Effect = "Allow"
        Principal = {
          Service = "logs.${var.aws_region}.amazonaws.com"
        }
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:GenerateDataKey",
          "kms:DescribeKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "flux" {
  name          = "alias/project-flux-${var.environment}"
  target_key_id = aws_kms_key.flux.key_id
}
