# Confluent Provider Integration for Tableflow
# This resource creates the connection between Confluent Cloud and the AWS IAM role
# allowing Tableflow to assume the customer IAM role and access the S3 bucket

resource "confluent_provider_integration" "tableflow_aws" {
  count = var.create_provider_integration ? 1 : 0

  display_name = var.provider_integration_display_name

  environment {
    id = var.confluent_environment_id
  }

  aws {
    customer_role_arn = aws_iam_role.tableflow_role.arn
  }

  lifecycle {
    create_before_destroy = false
  }

  depends_on = [
    aws_iam_role.tableflow_role,
    aws_s3_bucket.tableflow_storage
  ]
}

# Note: After the provider integration is created, you must update the IAM role
# trust policy with the Confluent role ARN and external ID. This can be done by:
# 1. Running `terraform output` to get the confluent_role_arn and external_id
# 2. Setting the variables:
#    - confluent_provider_integration_role_arn
#    - confluent_external_id
# 3. Re-running `terraform apply` to update the IAM role trust policy
