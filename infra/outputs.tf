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

output "api_endpoint" {
  description = "API Gateway endpoint URL for event ingestion"
  value       = "${aws_api_gateway_stage.dev.invoke_url}/events"
}

output "api_id" {
  description = "API Gateway REST API ID"
  value       = aws_api_gateway_rest_api.flux.id
}

output "sqs_queue_url" {
  description = "SQS main events queue URL"
  value       = aws_sqs_queue.events.url
}

output "sqs_queue_arn" {
  description = "SQS main events queue ARN"
  value       = aws_sqs_queue.events.arn
}

output "sqs_dlq_arn" {
  description = "SQS Dead Letter Queue ARN"
  value       = aws_sqs_queue.events_dlq.arn
}

output "lambda_function_name" {
  description = "Lambda processor function name"
  value       = aws_lambda_function.processor.function_name
}

output "lambda_function_arn" {
  description = "Lambda processor function ARN"
  value       = aws_lambda_function.processor.arn
}

output "dynamodb_table_name" {
  description = "DynamoDB device state table name"
  value       = aws_dynamodb_table.device_state.name
}

output "dynamodb_table_arn" {
  description = "DynamoDB device state table ARN"
  value       = aws_dynamodb_table.device_state.arn
}
