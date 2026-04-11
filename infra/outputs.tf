# ============================================================
# Outputs — values exposed after terraform apply
# These are referenced by other modules and the CI/CD pipeline
# ============================================================

output "events_bucket_name" {
  description = "S3 bucket name for raw event storage"
  value       = aws_s3_bucket.events.bucket
}

output "events_bucket_arn" {
  description = "S3 bucket ARN for raw event storage"
  value       = aws_s3_bucket.events.arn
}

output "kms_key_arn" {
  description = "KMS key ARN used for encryption"
  value       = aws_kms_key.flux.arn
}

output "kms_key_id" {
  description = "KMS key ID"
  value       = aws_kms_key.flux.key_id
}

output "lambda_role_arn" {
  description = "IAM role ARN for Lambda execution"
  value       = aws_iam_role.lambda_exec.arn
}

output "lambda_role_name" {
  description = "IAM role name for Lambda execution"
  value       = aws_iam_role.lambda_exec.name
}
