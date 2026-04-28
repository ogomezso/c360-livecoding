# Confluent Cloud Infrastructure - Customer 360 Demo

This Terraform configuration automatically provisions a complete Confluent Cloud infrastructure for the Customer 360 live coding workshop on AWS in Europe.

## 📦 What Gets Provisioned

### Confluent Cloud Resources

| Resource | Type | Description |
|----------|------|-------------|
| **Environment** | Organization | Isolated workspace for the Customer 360 demo |
| **Kafka Cluster** | Standard | Auto-scaling Kafka cluster (0-10 eCKU) with public endpoints in AWS eu-west-1 |
| **Flink Compute Pool** | Serverless | Flink SQL processing pool (0-10 CFUs) |
| **Service Account** | Identity | Application identity with proper RBAC roles |
| **API Keys** | Authentication | Kafka and Flink API keys for the service account |
| **Role Bindings** | Authorization | ClusterAdmin, FlinkDeveloper, EnvironmentAdmin roles |

### Default Configuration

- **Region**: AWS eu-west-1 (Ireland) - closest European region
- **Kafka Cluster**: Standard, Multi-Zone, Auto-scaling (0-10 eCKU), Public endpoints
- **Flink Pool**: Serverless, max 10 CFUs (auto-scales from 0)
- **Availability**: Multi-zone for 99.99% SLA
- **Networking**: Public endpoints (accessible from local MCP server)
- **Scaling**: Elastic auto-scaling (pay only for what you use)

## 🚀 Quick Start

### Prerequisites

1. **Confluent Cloud Account**
   - Sign up at: https://confluent.cloud/
   - Free trial available (no credit card required for limited usage)

2. **Confluent Cloud API Keys**
   - Navigate to: https://confluent.cloud/settings/api-keys
   - Create a Cloud API Key with **Organization** scope
   - Save both the key and secret securely

3. **Terraform**
   ```bash
   # macOS
   brew install terraform
   
   # Or download from https://www.terraform.io/downloads
   terraform --version  # Verify >= 1.5.0
   ```

4. **Confluent CLI** (Optional, but recommended)
   ```bash
   # macOS
   brew install confluentinc/tap/cli
   
   # Verify
   confluent version
   ```

### Step-by-Step Deployment

#### 1. Configure Credentials

**🔐 Security Best Practice**: Use environment variables instead of files

**Option A: Interactive Setup (Recommended)**

```bash
# Prompts for credentials and saves to .env.local
make setup-credentials

# Load credentials into your shell
source .env.local

# Verify they're set
make check-credentials
```

**Option B: Manual Environment Variables**

```bash
# Set environment variables (replace with your actual values)
export TF_VAR_confluent_cloud_api_key='your-cloud-api-key'
export TF_VAR_confluent_cloud_api_secret='your-cloud-api-secret'

# Verify
echo $TF_VAR_confluent_cloud_api_key
```

**Option C: Use a .env.local file**

```bash
# Create .env.local (this file is git-ignored)
cat > .env.local << 'EOF'
export TF_VAR_confluent_cloud_api_key='your-cloud-api-key'
export TF_VAR_confluent_cloud_api_secret='your-cloud-api-secret'
EOF

# Load it
source .env.local
```

**Where to get credentials:**
- Navigate to: https://confluent.cloud/settings/api-keys
- Create a **Cloud API Key** with **Organization** or **Cloud resource management** scope
- Copy both the key and secret immediately (secret is only shown once)

#### 2. Initialize Terraform

```bash
# Initialize Terraform and download providers
terraform init
```

Expected output:
```
Terraform has been successfully initialized!
```

#### 3. Review the Plan

```bash
# See what will be created
terraform plan
```

This will show:
- 1 environment
- 1 Kafka cluster (Standard with auto-scaling and public endpoints)
- 1 Flink compute pool
- 1 service account
- 2 API keys (Kafka and Flink)
- 3 role bindings

#### 4. Deploy Infrastructure

```bash
# Apply the configuration
terraform apply
```

Type `yes` when prompted.

#### 5. Verify Deployment

```bash
# View all outputs
terraform output

# Get specific values
terraform output kafka_cluster_id
terraform output flink_compute_pool_id

# View connection URLs
terraform output confluent_cloud_console_urls
```

## 📊 Accessing Your Infrastructure

### Confluent Cloud Console

After deployment, access your resources via these URLs (also in `terraform output`):

```bash
# Environment overview
terraform output -raw confluent_cloud_console_urls | jq -r '.environment'

# Kafka cluster
terraform output -raw confluent_cloud_console_urls | jq -r '.kafka_cluster'

# Flink console
terraform output -raw confluent_cloud_console_urls | jq -r '.flink_console'

# Topics view
terraform output -raw confluent_cloud_console_urls | jq -r '.topics'
```

### Using Confluent CLI

```bash
# Log in to Confluent Cloud
confluent login --save

# List environments
confluent environment list

# Use your environment
confluent environment use $(terraform output -raw environment_id)

# List clusters
confluent kafka cluster list

# Describe your cluster
confluent kafka cluster describe $(terraform output -raw kafka_cluster_id)
```

## 🔗 Integration with MCP Server

Export configuration for the Confluent MCP server:

```bash
# Append to MCP server .env file
terraform output -raw mcp_server_env_config >> ~/.confluent-mcp/.env

# Or save to a separate file
terraform output -raw mcp_server_env_config > confluent-mcp.env
```

The exported configuration includes:
- Confluent Cloud API credentials
- Kafka cluster connection details
- Flink compute pool configuration
- All necessary API keys

## 📝 Important Outputs

### Connection Information

```bash
# Get all connection info as JSON
terraform output -json connection_info | jq

# Kafka bootstrap servers
terraform output -raw kafka_cluster_bootstrap_endpoint

# Kafka REST endpoint
terraform output -raw kafka_cluster_rest_endpoint

# Flink REST endpoint
terraform output -raw flink_rest_endpoint
```

### Sensitive Outputs (API Keys)

```bash
# Kafka API Key
terraform output -raw kafka_api_key

# Kafka API Secret (sensitive)
terraform output -raw kafka_api_secret

# Flink API Key
terraform output -raw flink_api_key

# Flink API Secret (sensitive)
terraform output -raw flink_api_secret
```

**⚠️ Security Note**: These values are sensitive. Never commit them to version control.

## 🎛️ Customization

### Change Region

Edit `terraform.tfvars`:

```hcl
cluster_region = "eu-central-1"  # Frankfurt
# Or
cluster_region = "eu-west-2"     # London
# Or
cluster_region = "eu-west-3"     # Paris
```

Available European AWS regions:
- `eu-west-1` - Ireland (default, most services)
- `eu-west-2` - London
- `eu-west-3` - Paris
- `eu-central-1` - Frankfurt
- `eu-central-2` - Zurich
- `eu-north-1` - Stockholm
- `eu-south-1` - Milan

### Adjust Flink Pool Size

```hcl
# Flink compute pool (CFUs)
flink_max_cfu = 20  # Max CFUs (auto-scales from 0)
```

**Note**: Standard Kafka clusters auto-scale from 0-10 eCKU automatically - no configuration needed!

### Single vs Multi-Zone

```hcl
# For development/testing (99.5% SLA)
cluster_availability = "SINGLE_ZONE"

# For production (99.99% SLA - requires 2+ eCKU minimum)
cluster_availability = "MULTI_ZONE"
```

## 🧹 Cleanup

### Destroy Infrastructure

```bash
# Review what will be destroyed
terraform plan -destroy

# Destroy all resources
terraform destroy
```

Type `yes` when prompted.

**⚠️ Warning**: This will permanently delete:
- All topics and data in the Kafka cluster
- All Flink statements and jobs
- All API keys
- The entire environment

**Before destroying**:
1. Export any important data
2. Download any Flink SQL statements you want to keep
3. Save topic configurations if needed

### Partial Cleanup

To remove specific resources, use targeted destruction:

```bash
# Remove only the Flink compute pool
terraform destroy -target=confluent_flink_compute_pool.customer_360

# Remove only API keys
terraform destroy -target=confluent_api_key.customer_360_kafka_api_key
```

## 🔧 Troubleshooting

### Issue: "Error creating Kafka cluster"

**Problem**: Cluster creation timeout or failure.

**Solution**:
```bash
# Check Confluent Cloud status
curl https://status.confluent.cloud/

# Verify your API key permissions
confluent api-key list

# Check cluster limits
confluent kafka cluster list
```

### Issue: "Insufficient permissions"

**Problem**: API key doesn't have required permissions.

**Solution**:
- Ensure your Cloud API Key has **Organization** or **Cloud resource management** scope
- Recreate API key at: https://confluent.cloud/settings/api-keys

### Issue: "Region not available"

**Problem**: Selected region doesn't support Dedicated clusters or Flink.

**Solution**:
```bash
# List available regions
confluent kafka region list --cloud aws

# Choose a different region in terraform.tfvars
cluster_region = "eu-central-1"
```

### Issue: Terraform state is locked

**Problem**: State file is locked from a previous operation.

**Solution**:
```bash
# Force unlock (use with caution)
terraform force-unlock <lock-id>

# Or remove the lock file if using local state
rm .terraform.tfstate.lock.info
```

### Issue: API rate limiting

**Problem**: Too many API calls to Confluent Cloud.

**Solution**:
```bash
# Wait and retry
sleep 60 && terraform apply

# Use -parallelism flag to reduce concurrent operations
terraform apply -parallelism=1
```

## 📚 Additional Resources

### Confluent Documentation
- [Terraform Provider Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs)
- [Cluster Types Comparison](https://docs.confluent.io/cloud/current/clusters/cluster-types.html)
- [Standard Clusters](https://docs.confluent.io/cloud/current/clusters/cluster-types.html#standard-cluster)
- [Elastic CKU (eCKU) Billing](https://docs.confluent.io/cloud/current/billing/overview.html#e-cku-definition)
- [Flink Compute Pools](https://docs.confluent.io/cloud/current/flink/get-started/compute-pools.html)
- [RBAC in Confluent Cloud](https://docs.confluent.io/cloud/current/security/access-control/cloud-rbac.html)

### Terraform Resources Created
- `confluent_environment` - [Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_environment)
- `confluent_kafka_cluster` - [Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_kafka_cluster)
- `confluent_flink_compute_pool` - [Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_flink_compute_pool)
- `confluent_service_account` - [Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_service_account)
- `confluent_api_key` - [Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_api_key)
- `confluent_role_binding` - [Docs](https://registry.terraform.io/providers/confluentinc/confluent/latest/docs/resources/confluent_role_binding)

## 🔐 Security Best Practices

1. **Never commit terraform.tfvars** - Contains sensitive credentials
2. **Use environment variables** for CI/CD:
   ```bash
   export TF_VAR_confluent_cloud_api_key="your-key"
   export TF_VAR_confluent_cloud_api_secret="your-secret"
   ```
3. **Rotate API keys regularly** - Generate new keys periodically
4. **Use separate environments** - dev, staging, prod with different API keys
5. **Enable audit logging** - Monitor access to your Confluent Cloud resources
6. **Store state securely** - Consider remote state (S3, GCS, Terraform Cloud)

## 🎯 Next Steps

After successfully deploying your infrastructure:

1. **Create Topics** - Define topics for Customer 360 data:
   - `corebank.customers`
   - `corebank.accounts`
   - `corebank.transactions`
   - `digital.interactions`

2. **Set Up Schemas** - Register Avro schemas in Schema Registry

3. **Configure MCP Server** - Use the exported configuration

4. **Start the Workshop** - Follow the main [README.md](../../README.md)

## 📞 Support

- **Issues**: Report Terraform issues or bugs
- **Confluent Support**: https://support.confluent.io/
- **Community**: https://forum.confluent.io/

---

**Created for**: Customer 360 Live Coding Workshop  
**Managed by**: Terraform  
**Cloud Provider**: AWS  
**Region**: Europe (eu-west-1)
