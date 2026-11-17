# Tableflow AWS Infrastructure - Terraform Configuration

This Terraform configuration creates the AWS infrastructure required for Confluent Cloud Tableflow's **Bring Your Own Bucket (BYOB)** feature. Tableflow allows Kafka topics to be materialized as Apache Iceberg or Delta Lake tables in customer-managed S3 storage.

## Overview

This module provisions:
- **S3 Bucket** for Tableflow table storage with SSE-S3 encryption
- **IAM Role** with S3 permissions for Tableflow access
- **IAM Trust Policy** to allow Confluent to assume the role
- **Confluent Provider Integration** linking the IAM role to Confluent Cloud
- **Outputs** for Confluent MCP tools integration

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│ Confluent Cloud (Tableflow)                                     │
│  - Kafka Topics                                                 │
│  - Tableflow Service                                            │
└──────────────────┬──────────────────────────────────────────────┘
                   │ STS AssumeRole
                   │ (with External ID)
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│ AWS Account (Customer)                                          │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ Provider Integration                                     │   │
│  │  - Confluent Role ARN                                    │   │
│  │  - External ID                                           │   │
│  └─────────────────────────────────────────────────────────┘   │
│                   │                                              │
│                   ▼                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ IAM Role: customer-360-tableflow-role-<suffix>                    │   │
│  │  - Trust Policy: Allow Confluent role with External ID   │   │
│  │  - Permission Policy: S3 access to bucket                │   │
│  └─────────────────────────────────────────────────────────┘   │
│                   │                                              │
│                   ▼                                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │ S3 Bucket: customer-360-tableflow-storage-XXXX           │   │
│  │  - SSE-S3 Encryption                                     │   │
│  │  - Blocked Public Access                                 │   │
│  │  - Lifecycle: Intelligent-Tiering after 90 days          │   │
│  │  - Contents: Iceberg/Delta table files                   │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

## Prerequisites

### 1. AWS Credentials

You need AWS credentials with permissions to create:
- S3 buckets
- IAM roles and policies
- Tags

Set your credentials using one of these methods:
```bash
# Method 1: Environment variables
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="eu-west-1"

# Method 2: AWS CLI profile
aws configure
```

### 2. Confluent Cloud Environment

You need:
- Confluent Cloud API Key and Secret (with OrganizationAdmin or EnvironmentAdmin role)
- Environment ID (from `terraform-confluent-aws` outputs)
- Kafka Cluster ID (from `terraform-confluent-aws` outputs)

Get these values:
```bash
cd ../terraform-confluent-aws
terraform output environment_id
terraform output kafka_cluster_id
```

### 3. Terraform

Install Terraform >= 1.0:
```bash
terraform version
```

## Quick Start

### Step 1: Configure Variables

Create a `terraform.tfvars` file from the example:
```bash
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:
```hcl
# AWS Configuration
aws_region     = "eu-west-1"
aws_access_key = "YOUR_AWS_ACCESS_KEY"
aws_secret_key = "YOUR_AWS_SECRET_KEY"

# Confluent Cloud Configuration
confluent_cloud_api_key    = "YOUR_CONFLUENT_API_KEY"
confluent_cloud_api_secret = "YOUR_CONFLUENT_API_SECRET"
confluent_environment_id   = "env-xxxxx"  # From terraform-confluent-aws
confluent_cluster_id       = "lkc-xxxxx"  # From terraform-confluent-aws

# Optional: Customize names
bucket_name_prefix                 = "customer-360-tableflow-storage"
iam_role_name                      = "customer-360-tableflow-role"   # the deployed role is <iam_role_name>-<suffix>
provider_integration_display_name  = "customer-360-tableflow-integration"

# Provider Integration
create_provider_integration = true
```

### Step 2: Deploy (Two-Phase Approach)

#### Phase 1: Initial Deployment

Deploy AWS infrastructure and create provider integration:
```bash
make deploy
```

Or manually:
```bash
terraform init
terraform plan
terraform apply
```

After deployment, note the outputs:
```bash
terraform output iam_role_arn
terraform output provider_integration_id
terraform output confluent_role_arn
terraform output -raw confluent_external_id
```

#### Phase 2: Update Trust Policy

The provider integration is created, but the IAM role trust policy still has a deny-all placeholder. Update it:

1. Get the Confluent role ARN and external ID:
```bash
CONFLUENT_ROLE_ARN=$(terraform output -raw confluent_role_arn)
EXTERNAL_ID=$(terraform output -raw confluent_external_id)
```

2. Add these to your `terraform.tfvars`:
```hcl
confluent_provider_integration_role_arn = "arn:aws:iam::851725421142:role/cspi-xxxxx"
confluent_external_id                   = "your-external-id-here"
```

3. Re-apply to update the trust policy:
```bash
terraform apply
```

4. Verify the trust policy was updated:
```bash
aws iam get-role --role-name customer-360-tableflow-role-<suffix> \
  --query 'Role.AssumeRolePolicyDocument' --output json
```

### Step 3: Export MCP Environment Variables

Export the environment variables for Confluent MCP tools:
```bash
terraform output -raw mcp_export_command | sh
```

Or manually:
```bash
export TABLEFLOW_S3_BUCKET_NAME="customer-360-tableflow-storage-xxxxx"
export TABLEFLOW_S3_BUCKET_REGION="eu-west-1"
export TABLEFLOW_IAM_ROLE_ARN="arn:aws:iam::xxxxx:role/customer-360-tableflow-role-<suffix>"
export TABLEFLOW_PROVIDER_INTEGRATION_ID="cspi-xxxxx"
export CONFLUENT_ENVIRONMENT_ID="env-xxxxx"
export CONFLUENT_CLUSTER_ID="lkc-xxxxx"
```

### Step 4: Create Tableflow Topics

Use Confluent MCP to create Tableflow-enabled topics:

```bash
# Example: Create a Tableflow topic for customer transactions
mcp__confluent__create-tableflow-topic \
  --display_name "corebank.transactions" \
  --storage.bucket_name "customer-360-tableflow-storage-xxxxx" \
  --storage.provider_integration_id "cspi-xxxxx" \
  --table_formats '["ICEBERG"]'
```

### Step 5: Create Glue Catalog Integration (Optional)

Integrate with AWS Glue Data Catalog for easier querying:

```bash
mcp__confluent__create-tableflow-catalog-integration \
  --display_name "customer-360-glue-catalog" \
  --config.kind "AwsGlue" \
  --config.provider_integration_id "cspi-xxxxx"
```

## Makefile Targets

This configuration includes a Makefile for easier management:

```bash
make deploy     # Full deployment workflow (init + plan + apply)
make init       # Initialize Terraform
make plan       # Show execution plan
make apply      # Apply changes
make destroy    # Destroy all resources
make validate   # Validate configuration
make fmt        # Format Terraform files
make export-mcp # Export MCP environment variables
make info       # Display current infrastructure state
make help       # Show all available targets
```

## Verification

### Verify AWS Resources

Check S3 bucket:
```bash
aws s3 ls s3://customer-360-tableflow-storage-xxxxx
aws s3api get-bucket-encryption --bucket customer-360-tableflow-storage-xxxxx
aws s3api get-public-access-block --bucket customer-360-tableflow-storage-xxxxx
```

Check IAM role:
```bash
aws iam get-role --role-name customer-360-tableflow-role-<suffix>
aws iam list-role-policies --role-name customer-360-tableflow-role-<suffix>
aws iam get-role-policy --role-name customer-360-tableflow-role-<suffix> --policy-name tableflow-s3-access
```

### Verify Trust Policy

After Phase 2, verify the trust policy allows Confluent:
```bash
aws iam get-role --role-name customer-360-tableflow-role-<suffix> \
  --query 'Role.AssumeRolePolicyDocument.Statement[0]' --output json
```

Expected output:
```json
{
  "Effect": "Allow",
  "Principal": {
    "AWS": "arn:aws:iam::851725421142:role/cspi-xxxxx"
  },
  "Action": "sts:AssumeRole",
  "Condition": {
    "StringEquals": {
      "sts:ExternalId": "your-external-id"
    }
  }
}
```

### Test Tableflow End-to-End

1. Produce messages to a Tableflow-enabled topic
2. Check S3 for Iceberg table files:
```bash
aws s3 ls s3://customer-360-tableflow-storage-xxxxx/ --recursive
```
3. Query tables via AWS Athena or Glue Data Catalog

## Troubleshooting

### Issue: Trust Policy Not Updating

**Symptom:** IAM role trust policy still shows "Deny" after Phase 2

**Solution:**
1. Verify you set both variables in `terraform.tfvars`:
   - `confluent_provider_integration_role_arn`
   - `confluent_external_id`
2. Run `terraform plan` to see if the trust policy will change
3. Run `terraform apply` to apply the change

### Issue: Provider Integration Creation Fails

**Symptom:** Error creating `confluent_provider_integration` resource

**Solution:**
1. Verify Confluent Cloud API credentials have sufficient permissions
2. Ensure the environment ID is correct
3. Check that the IAM role exists and is in the same AWS account

### Issue: S3 Access Denied in Tableflow

**Symptom:** Tableflow cannot write to S3 bucket

**Solution:**
1. Verify the IAM role trust policy is updated (Phase 2 completed)
2. Check S3 bucket permissions in IAM policy
3. Ensure bucket region matches Kafka cluster region
4. Verify provider integration is active:
```bash
mcp__confluent__read-tableflow-topic --display_name "your-topic"
```

### Issue: Bucket Name Conflict

**Symptom:** Error: bucket name already exists

**Solution:**
The random suffix should prevent this, but if it happens:
1. Destroy and re-apply to get a new random suffix
2. Or manually set a unique `bucket_name_prefix` in `terraform.tfvars`

## Security Best Practices

1. **Never commit credentials** to git
   - Use `.gitignore` for `terraform.tfvars` and `.env.local`
   - Use environment variables or AWS CLI profiles

2. **Restrict IAM role permissions**
   - The role only has S3 permissions to the specific bucket
   - Trust policy requires external ID for additional security

3. **Enable S3 encryption**
   - SSE-S3 encryption is enabled by default
   - Can be upgraded to KMS encryption if needed

4. **Block public access**
   - All public access is blocked on the S3 bucket
   - Only Confluent can access via IAM role assumption

5. **Monitor costs**
   - Enable AWS Cost Explorer for S3 storage costs
   - Lifecycle policy transitions to Intelligent-Tiering after 90 days

## Cost Optimization

- **S3 Storage:** Pay for data stored by Tableflow
- **Lifecycle Policy:** Automatically transitions to Intelligent-Tiering after 90 days
- **Iceberg Compaction:** Tableflow automatically compacts files and deletes old versions
- **Monitoring:** Use AWS Cost Explorer to track S3 costs

## Resources Created

| Resource Type | Name | Purpose |
|---------------|------|---------|
| S3 Bucket | `customer-360-tableflow-storage-XXXX` | Stores Iceberg/Delta table files |
| IAM Role | `customer-360-tableflow-role-<suffix>` | Allows Confluent to access S3 |
| IAM Policy | `tableflow-s3-access` | Grants S3 permissions to IAM role |
| Provider Integration | `customer-360-tableflow-integration` | Links Confluent to AWS IAM role |
| Random ID | 4-byte hex suffix | Ensures bucket name uniqueness |

## Integration with terraform-confluent-aws

This module is designed to work alongside the existing `terraform-confluent-aws` infrastructure:

```bash
environment/
├── terraform-confluent-aws/      # Confluent Cloud resources
│   ├── confluent.tf              # Environment, cluster, Flink
│   ├── topics.tf                 # Kafka topics
│   └── outputs.tf                # Provides environment_id, cluster_id
│
└── terraform-tableflow-aws/      # AWS resources for Tableflow (this module)
    ├── s3.tf                     # S3 bucket
    ├── iam.tf                    # IAM role
    ├── provider-integration.tf   # Confluent provider integration
    └── outputs.tf                # MCP environment variables
```

## Next Steps

After deploying this infrastructure:

1. **Create Tableflow Topics** via Confluent MCP
2. **Create Glue Catalog Integration** for easier querying
3. **Produce data** to Tableflow-enabled topics
4. **Query tables** via AWS Athena, Glue, or Spark
5. **Monitor costs** in AWS Cost Explorer

## Additional Resources

- [Tableflow Documentation](https://docs.confluent.io/cloud/current/topics/tableflow/)
- [Configure Storage for Tableflow](https://docs.confluent.io/cloud/current/topics/tableflow/how-to-guides/configure-storage.html)
- [Tableflow Quick Start](https://docs.confluent.io/cloud/current/topics/tableflow/get-started/quick-start-custom-storage-glue.html)
- [AWS IAM Roles](https://docs.aws.amazon.com/IAM/latest/UserGuide/id_roles.html)
- [S3 Server-Side Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/serv-side-encryption.html)

## Support

For issues or questions:
- Check the troubleshooting section above
- Review Confluent Cloud documentation
- Contact your Confluent account team
