# ============================================================
# Variables — all configurable values in one place
# No secrets here. Secrets go in environment variables or
# AWS Secrets Manager. Never in .tf files.
# ============================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "ap-south-1"
}

variable "environment" {
  description = "Deployment environment (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Project identifier — used in resource names"
  type        = string
  default     = "project-flux"
}

variable "aws_account_id" {
  description = "AWS account ID — used for globally unique resource names"
  type        = string
}

variable "alert_email" {
  description = "Email address for CloudWatch alarm notifications"
  type        = string
  default     = ""
}
