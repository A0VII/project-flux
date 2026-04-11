# ============================================================
# S3 — Raw events archive bucket
#
# This bucket stores every raw event payload as a JSON object.
# It's the permanent, immutable record — the "source of truth."
# DynamoDB (added later) stores only the latest processed state.
# ============================================================

resource "aws_s3_bucket" "events" {
  bucket = "${var.project_name}-events-${var.environment}-${var.aws_account_id}"

  # force_destroy allows terraform destroy to delete the bucket
  # even if it has objects — safe for dev, must be false in prod
  force_destroy = var.environment == "dev" ? true : false
}

# Block all public access — event data must never be public
resource "aws_s3_bucket_public_access_block" "events" {
  bucket = aws_s3_bucket.events.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Encrypt all objects at rest using our KMS CMK
resource "aws_s3_bucket_server_side_encryption_configuration" "events" {
  bucket = aws_s3_bucket.events.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.flux.arn
    }
    bucket_key_enabled = true  # Reduces KMS API call costs
  }
}

# Versioning — allows recovery of overwritten or deleted objects
resource "aws_s3_bucket_versioning" "events" {
  bucket = aws_s3_bucket.events.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Lifecycle rules — automatically manage storage costs
resource "aws_s3_bucket_lifecycle_configuration" "events" {
  bucket = aws_s3_bucket.events.id

  rule {
    id     = "dev-retention-policy"
    status = "Enabled"

    filter {}

    # Move objects to cheaper storage after 30 days (pilot)
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    # Delete objects after 90 days in dev (cost control)
    expiration {
      days = 90
    }
  }
}

