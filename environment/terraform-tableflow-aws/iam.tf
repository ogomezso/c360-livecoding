# IAM Policy Document for S3 Access Permissions
# This defines what Tableflow can do with the S3 bucket
data "aws_iam_policy_document" "tableflow_s3_access" {
  # Bucket-level permissions
  statement {
    sid    = "BucketLevelPermissions"
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads"
    ]

    resources = [
      aws_s3_bucket.tableflow_storage.arn
    ]
  }

  # Object-level permissions
  statement {
    sid    = "ObjectLevelPermissions"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObjectTagging",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts"
    ]

    resources = [
      "${aws_s3_bucket.tableflow_storage.arn}/*"
    ]
  }
}

# IAM Trust Policy - Phase 1 (Initial Deployment)
# This is a placeholder that denies all access until provider integration is created
data "aws_iam_policy_document" "tableflow_assume_role_initial" {
  statement {
    effect = "Deny"
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    actions = ["sts:AssumeRole"]
  }
}

# IAM Trust Policy - Phase 2 (After Provider Integration)
# This allows Confluent to assume the role using the provider integration
data "aws_iam_policy_document" "tableflow_assume_role" {
  count = var.confluent_provider_integration_role_arn != "" ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = [var.confluent_provider_integration_role_arn]
    }
    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "sts:ExternalId"
      values   = [var.confluent_external_id]
    }
  }
}

# IAM Role for Tableflow
resource "aws_iam_role" "tableflow_role" {
  name        = local.role_name
  description = "IAM role for Confluent Cloud Tableflow to access S3 bucket"

  # Use the appropriate trust policy based on whether provider integration is created
  assume_role_policy = var.confluent_provider_integration_role_arn != "" ? data.aws_iam_policy_document.tableflow_assume_role[0].json : data.aws_iam_policy_document.tableflow_assume_role_initial.json

  tags = merge(
    var.tags,
    {
      Name = local.role_name
    }
  )

  lifecycle {
    prevent_destroy = false
  }
}

# Attach S3 permissions policy to the IAM role
resource "aws_iam_role_policy" "tableflow_s3_policy" {
  name   = "tableflow-s3-access"
  role   = aws_iam_role.tableflow_role.id
  policy = data.aws_iam_policy_document.tableflow_s3_access.json
}

# IAM role names are unique per AWS account: suffix them so two demos can share an account.
locals {
  role_name = "${var.iam_role_name}-${var.name_suffix != "" ? var.name_suffix : random_id.suffix.hex}"
}
