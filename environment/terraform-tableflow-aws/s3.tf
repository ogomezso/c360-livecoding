# Generate a random suffix for S3 bucket name to ensure global uniqueness
resource "random_id" "suffix" {
  byte_length = 4
}

# S3 Bucket for Tableflow Storage
resource "aws_s3_bucket" "tableflow_storage" {
  bucket = "${var.bucket_name_prefix}-${random_id.suffix.hex}"

  tags = merge(
    var.tags,
    {
      Name = "${var.bucket_name_prefix}-${random_id.suffix.hex}"
    }
  )

  lifecycle {
    prevent_destroy = false
  }
}

# Block all public access to the S3 bucket
resource "aws_s3_bucket_public_access_block" "tableflow_storage" {
  bucket = aws_s3_bucket.tableflow_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable server-side encryption (SSE-S3) for the bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "tableflow_storage" {
  bucket = aws_s3_bucket.tableflow_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# Optional: Lifecycle rule for cost optimization
# Transition objects to Intelligent-Tiering after 90 days
resource "aws_s3_bucket_lifecycle_configuration" "tableflow_storage" {
  bucket = aws_s3_bucket.tableflow_storage.id

  rule {
    id     = "transition-to-intelligent-tiering"
    status = "Enabled"

    filter {
      prefix = ""
    }

    transition {
      days          = 90
      storage_class = "INTELLIGENT_TIERING"
    }
  }
}

# Versioning is not required for Tableflow, but can be enabled if needed
# Uncomment the following block to enable versioning
# resource "aws_s3_bucket_versioning" "tableflow_storage" {
#   bucket = aws_s3_bucket.tableflow_storage.id
#
#   versioning_configuration {
#     status = "Enabled"
#   }
# }
