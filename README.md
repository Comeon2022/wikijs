# Wiki.js on Google Cloud Run

This repository contains Terraform configuration to deploy Wiki.js on Google Cloud Run with PostgreSQL Cloud SQL database.

## 🏗️ Architecture

- **Database**: PostgreSQL 15 on Cloud SQL
- **Container**: Wiki.js 2.x on Cloud Run  
- **Registry**: Google Artifact Registry
- **Access**: Public (allUsers have Cloud Run Invoker role)
- **Infrastructure**: 100% Terraform managed

## 📋 Prerequisites

- [Google Cloud SDK](https://cloud.google.com/sdk/docs/install) installed and configured
- [Terraform](https://www.terraform.io/downloads) installed (>= 1.0)
- [Docker](https://docs.docker.com/get-docker/) installed
- A GCP project with billing enabled

## 🚀 Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Comeon2022/wikijs.git
   cd wikijs
   ```

2. **One-click deployment**:
   ```bash
   chmod +x scripts/deploy-all.sh
   ./scripts/deploy-all.sh
   ```

That's it! The script will:
- ✅ Enable all required GCP APIs
- ✅ Create and configure PostgreSQL database
- ✅ Set up Artifact Registry
- ✅ Pull and push Wiki.js Docker image
- ✅ Deploy to Cloud Run with public access
- ✅ Provide you with the final URL

The script will guide you through entering your GCP project ID and handle everything else automatically.

## 📁 Repository Structure

```
wikijs/
├── README.md
├── .gitignore
├── terraform/
│   ├── main.tf                    # Main Terraform configuration
│   └── terraform.tfvars.example   # Example variables file
└── scripts/
    ├── deploy.sh                  # One-click deployment script
    └── push-image.sh              # Docker image push script
```

## ⚙️ Configuration

### Required Variables

Edit `terraform/terraform.tfvars`:

```hcl
project_id = "your-gcp-project-id"
region     = "us-central1"           # Optional, defaults to us-central1
zone       = "us-central1-a"         # Optional, defaults to us-central1-a
```

### Optional Customization

You can modify these in `terraform/main.tf`:
- Database tier (currently `db-f1-micro` for cost optimization)
- Cloud Run resource limits (CPU/Memory)
- PostgreSQL version (currently 15)
- Region/zone preferences

## 📦 Resources Created

This Terraform configuration creates:

- ☁️ **Cloud SQL PostgreSQL 15** instance with database and user
- 📦 **Artifact Registry** repository for Docker images
- 🔐 **Service Account** (`wiki-js-sa`) with minimal required permissions
- 🏃 **Cloud Run service** with public access
- 🎯 **IAM bindings** for security and access control

## 📊 Outputs

After successful deployment:
- 🌐 **Wiki.js URL**: Public endpoint for accessing your wiki
- 🗄️ **Database connection string**: For manual connections if needed
- 📦 **Artifact Registry URL**: Where your images are stored
- 📧 **Service Account email**: For reference and additional IAM if needed

## 🔧 Manual Deployment (Alternative)

If you prefer step-by-step deployment:

```bash
cd terraform

# Initialize Terraform
terraform init

# Review planned changes
terraform plan

# Apply infrastructure
terraform apply

# Configure Docker authentication
gcloud auth configure-docker us-central1-docker.pkg.dev

# Pull, tag, and push Wiki.js image
docker pull ghcr.io/requarks/wiki:2
docker tag ghcr.io/requarks/wiki:2 $(terraform output -raw artifact_registry_url)/wiki:2
docker push $(terraform output -raw artifact_registry_url)/wiki:2

# Update Cloud Run with the pushed image
terraform apply
```

## 🔒 Security Features

- ✅ Service Account with **least privilege** permissions
- ✅ **Database backups** enabled automatically
- ✅ **Resource limits** on Cloud Run for cost control
- ✅ **Auto-scaling** from 0 to 10 instances
- ✅ **Public access** as requested (allUsers can invoke)

## ⚠️ Production Considerations

For production deployments, consider:

- 🔐 Use **Google Secret Manager** instead of plain text passwords
- 🌐 Restrict **database network access** (currently allows all IPs)
- 📊 Enable **Cloud SQL Insights** for performance monitoring
- 🔄 Set up **automated backups** with longer retention
- 🏷️ Add **resource labels** for cost tracking
- 🔍 Enable **Cloud Logging** and **Monitoring**

## 💰 Cost Optimization

Current configuration uses:
- `db-f1-micro` for Cloud SQL (cheapest option)
- Cloud Run scales to zero when not in use
- Minimal resource allocations

Estimated monthly cost: ~$7-15 for light usage.

## 🧹 Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

**Warning**: This will permanently delete your database and all data!

## 📚 Wiki.js Setup

After deployment:

1. Navigate to the Cloud Run URL
2. Follow Wiki.js initial setup wizard
3. Database connection is pre-configured
4. Choose your authentication method
5. Create your first admin account

## 🐛 Troubleshooting

### Common Issues:

1. **"APIs not enabled"**: Wait 2-3 minutes after first apply for APIs to fully activate
2. **"Image not found"**: Make sure you ran the `push-image.sh` script
3. **"Permission denied"**: Check that your gcloud auth is configured for the correct project
4. **"Database connection failed"**: Verify Cloud SQL instance is running and accessible

### Getting Help:

- Check Cloud Run logs: `gcloud run services logs read wiki-js --region=us-central1`
- Check Cloud SQL status in GCP Console
- Verify Terraform state: `terraform show`

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Wiki.js](https://wiki.js.org/) for the amazing wiki software
- [Google Cloud Platform](https://cloud.google.com/) for the infrastructure
- [Terraform](https://www.terraform.io/) for infrastructure as code