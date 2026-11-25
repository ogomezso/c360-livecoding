# Optional: AWS identities for a self-hosted Apache Polaris that federates the Tableflow Iceberg REST catalog.
# Off by default; scripts/polaris.sh turns it on (polaris.auto.tfvars) and off again on teardown.
#
# Polaris runs outside AWS (a local kind cluster), so it needs two things:
#   * an IAM user whose access key lets it call sts:AssumeRole, and
#   * a READ-ONLY role it assumes to vend short-lived, table-scoped credentials to the query engine (Trino).
# The query engine itself never holds long-lived storage credentials.

variable "enable_polaris_reader" {
  description = "Create the IAM user + read-only role + access key that a self-hosted Polaris uses to vend credentials. Set by scripts/polaris.sh."
  type        = bool
  default     = false
}

locals {
  polaris_suffix = var.name_suffix != "" ? var.name_suffix : random_id.suffix.hex
  polaris_count  = var.enable_polaris_reader ? 1 : 0
}

resource "aws_iam_user" "polaris" {
  count = local.polaris_count
  name  = "customer-360-polaris-${local.polaris_suffix}"
}

resource "aws_iam_access_key" "polaris" {
  count = local.polaris_count
  user  = aws_iam_user.polaris[0].name
}

# Polaris' own identity may do exactly one thing: assume the reader role.
resource "aws_iam_user_policy" "polaris_assume" {
  count = local.polaris_count
  name  = "assume-polaris-reader"
  user  = aws_iam_user.polaris[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = aws_iam_role.polaris_reader[0].arn
    }]
  })
}

resource "aws_iam_role" "polaris_reader" {
  count       = local.polaris_count
  name        = "customer-360-polaris-reader-${local.polaris_suffix}"
  description = "Read-only access to the Tableflow bucket, assumed by Polaris to vend credentials"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { AWS = aws_iam_user.polaris[0].arn }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "polaris_reader" {
  count = local.polaris_count
  name  = "read-tableflow-bucket"
  role  = aws_iam_role.polaris_reader[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:GetObjectVersion"]
        Resource = "${aws_s3_bucket.tableflow_storage.arn}/*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetBucketLocation"]
        Resource = aws_s3_bucket.tableflow_storage.arn
      }
    ]
  })
}

output "polaris_reader_role_arn" {
  description = "Read-only role Polaris assumes (empty when the Polaris reader is not enabled)"
  value       = var.enable_polaris_reader ? aws_iam_role.polaris_reader[0].arn : ""
}

output "polaris_aws_access_key_id" {
  description = "Access key id of the IAM user Polaris runs as"
  value       = var.enable_polaris_reader ? aws_iam_access_key.polaris[0].id : ""
}

output "polaris_aws_secret_access_key" {
  description = "Secret access key of the IAM user Polaris runs as"
  value       = var.enable_polaris_reader ? aws_iam_access_key.polaris[0].secret : ""
  sensitive   = true
}
