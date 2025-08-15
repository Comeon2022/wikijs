#!/bin/bash

# =============================================================================
# Wiki.js Complete Deployment Script
# Version: 2.1.0
# Last Updated: 2025-08-15
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Starting complete Wiki.js deployment to GCP Cloud Run${NC}"
echo "=============================================================="

# Check terraform main.tf version
if [ -f "terraform/main.tf" ]; then
    TERRAFORM_VERSION=$(grep "# Version:" terraform/main.tf | head -1 | awk '{print $3}' || echo "Unknown")
    SCRIPT_VERSION="2.1.0"
    echo -e "${BLUE}📋 Versions:${NC}"
    echo "   Deploy Script: $SCRIPT_VERSION"
    echo "   Terraform Config: $TERRAFORM_VERSION"
    echo ""
    
    if [ "$TERRAFORM_VERSION" != "$SCRIPT_VERSION" ]; then
        echo -e "${YELLOW}⚠️  Warning: Version mismatch detected!${NC}"
        echo "   Please ensure you have the latest files from GitHub"
        echo "   Run: git pull origin main"
        echo ""
    fi
else
    echo -e "${RED}❌ terraform/main.tf not found!${NC}"
    exit 1
fi

# Check if terraform.tfvars exists, create from example if not
if [ ! -f "terraform/terraform.tfvars" ]; then
    echo -e "${YELLOW}terraform/terraform.tfvars not found. Creating from example...${NC}"
    if [ -f "terraform/terraform.tfvars.example" ]; then
        cp terraform/terraform.tfvars.example terraform/terraform.tfvars
        echo -e "${GREEN}Created terraform/terraform.tfvars from example file.${NC}"
    else
        echo -e "${RED}Error: terraform/terraform.tfvars.example not found!${NC}"
        echo "Please ensure the terraform.tfvars.example file exists in the terraform/ directory"
        exit 1
    fi
fi

# Ask user if they've entered their project ID
while true; do
    read -p "Did you enter your project ID in terraform/terraform.tfvars? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${GREEN}Great! Continuing with deployment...${NC}"
        break
    elif [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Opening terraform/terraform.tfvars for editing...${NC}"
        echo -e "${YELLOW}Please change 'your-gcp-project-id' to your actual GCP project ID${NC}"
        nano terraform/terraform.tfvars
        echo -e "${GREEN}File saved. Let's check again...${NC}"
    else
        echo "Please answer 'y' for yes or 'n' for no"
    fi
done

# Get project ID from terraform.tfvars
PROJECT_ID=$(grep -E '^project_id' terraform/terraform.tfvars | cut -d'"' -f2)
REGION=$(grep -E '^region' terraform/terraform.tfvars | cut -d'"' -f2 | head -1)

if [ -z "$PROJECT_ID" ]; then
    echo -e "${RED}Error: project_id not found in terraform/terraform.tfvars${NC}"
    exit 1
fi

if [ -z "$REGION" ]; then
    REGION="us-central1"
fi

echo -e "${BLUE}📋 Configuration:${NC}"
echo "   Project ID: $PROJECT_ID"
echo "   Region: $REGION"
echo ""

# ============================================================================
# STEP 1: SETUP AND AUTHENTICATE
# ============================================================================
echo -e "${YELLOW}🔐 Step 1: Setting up authentication...${NC}"
gcloud config set project $PROJECT_ID
echo -e "${GREEN}✓ Project set to $PROJECT_ID${NC}"

# ============================================================================
# STEP 2: ENABLE REQUIRED APIS
# ============================================================================
echo -e "${YELLOW}🔌 Step 2: Enabling required GCP APIs...${NC}"
echo "This may take a few minutes..."

REQUIRED_APIS=(
    "cloudresourcemanager.googleapis.com"
    "sqladmin.googleapis.com"
    "sql-component.googleapis.com"
    "run.googleapis.com"
    "artifactregistry.googleapis.com"
    "cloudbuild.googleapis.com"
    "iam.googleapis.com"
    "compute.googleapis.com"
)

API_ENABLE_FAILED=false

for api in "${REQUIRED_APIS[@]}"; do
    echo -e "${YELLOW}  Enabling $api...${NC}"
    if ! gcloud services enable $api --project=$PROJECT_ID 2>/dev/null; then
        echo -e "${RED}  Failed to enable $api - you may need to enable it manually${NC}"
        API_ENABLE_FAILED=true
    else
        echo -e "${GREEN}  ✓ $api enabled${NC}"
    fi
done

if [ "$API_ENABLE_FAILED" = true ]; then
    echo -e "${YELLOW}Some APIs failed to enable automatically.${NC}"
    echo -e "${YELLOW}You can enable them manually at: https://console.developers.google.com/apis/dashboard?project=$PROJECT_ID${NC}"
    echo -e "${YELLOW}Required APIs: cloudresourcemanager, sqladmin, sql-component, run, artifactregistry, cloudbuild, iam, compute${NC}"
    read -p "Do you want to continue anyway? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deployment cancelled. Please enable the APIs manually and try again."
        exit 1
    fi
else
    echo -e "${GREEN}✓ All APIs enabled successfully!${NC}"
fi

# ============================================================================
# STEP 3: DEPLOY INFRASTRUCTURE WITH TERRAFORM
# ============================================================================
echo ""
echo -e "${YELLOW}🏗️  Step 3: Deploying infrastructure with Terraform...${NC}"

# Change to terraform directory
cd terraform

# Initialize Terraform
echo -e "${YELLOW}  Initializing Terraform...${NC}"
terraform init

# Plan the deployment
echo -e "${YELLOW}  Planning Terraform deployment...${NC}"
terraform plan

# Apply the deployment
# Apply the deployment with error handling for Cloud SQL timeout
echo -e "${YELLOW}  Applying Terraform deployment...${NC}"
if terraform apply -auto-approve; then
    echo -e "${GREEN}✓ Infrastructure deployed successfully!${NC}"
else
    echo -e "${YELLOW}⚠️ Terraform deployment encountered an error (likely Cloud SQL timeout)${NC}"
    echo -e "${YELLOW}🔍 Checking if Cloud SQL instance was created despite timeout...${NC}"
    
    # Check if Cloud SQL instance exists and wait for it to be ready
    SQL_INSTANCE_NAME="wiki-postgres-instance"
    MAX_WAIT_MINUTES=20
    WAIT_COUNT=0
    
    while [ $WAIT_COUNT -lt $MAX_WAIT_MINUTES ]; do
        echo -e "${YELLOW}  Checking Cloud SQL instance status (attempt $((WAIT_COUNT + 1))/$MAX_WAIT_MINUTES)...${NC}"
        
        # Check if instance exists and get its status
        SQL_STATUS=$(gcloud sql instances describe $SQL_INSTANCE_NAME --project=$PROJECT_ID --format="value(state)" 2>/dev/null || echo "NOT_FOUND")
        
        if [ "$SQL_STATUS" = "RUNNABLE" ]; then
            echo -e "${GREEN}✅ Cloud SQL instance is ready! Importing to Terraform state...${NC}"
            
            # Import the instance to Terraform state
            terraform import google_sql_database_instance.wiki_postgres $PROJECT_ID:$SQL_INSTANCE_NAME 2>/dev/null || true
            
            # Complete the Terraform deployment
            echo -e "${YELLOW}  Completing Terraform deployment...${NC}"
            if terraform apply -auto-approve; then
                echo -e "${GREEN}✅ Infrastructure deployment completed successfully!${NC}"
                break
            else
                echo -e "${RED}❌ Failed to complete Terraform deployment after SQL import${NC}"
                exit 1
            fi
            
        elif [ "$SQL_STATUS" = "NOT_FOUND" ]; then
            echo -e "${RED}❌ Cloud SQL instance not found. Creation may have failed.${NC}"
            echo "Please check the GCP Console: https://console.cloud.google.com/sql/instances?project=$PROJECT_ID"
            exit 1
            
        else
            echo -e "${YELLOW}  Cloud SQL instance status: $SQL_STATUS (waiting for RUNNABLE)${NC}"
            echo -e "${YELLOW}  Waiting 60 seconds before next check...${NC}"
            sleep 60
            WAIT_COUNT=$((WAIT_COUNT + 1))
        fi
    done
    
    if [ $WAIT_COUNT -eq $MAX_WAIT_MINUTES ]; then
        echo -e "${RED}❌ Cloud SQL instance did not become ready within $MAX_WAIT_MINUTES minutes${NC}"
        echo "Current status: $SQL_STATUS"
        echo "Please check the GCP Console for any issues: https://console.cloud.google.com/sql/instances?project=$PROJECT_ID"
        exit 1
    fi
fi

# Get the Artifact Registry URL
ARTIFACT_URL=$(terraform output -raw artifact_registry_url)
echo -e "${BLUE}📦 Artifact Registry URL: $ARTIFACT_URL${NC}"

# Go back to root directory
cd ..

# ============================================================================
# STEP 4: PREPARE AND PUSH DOCKER IMAGE
# ============================================================================
echo ""
echo -e "${YELLOW}🐳 Step 4: Preparing and pushing Wiki.js Docker image...${NC}"

# Configure Docker authentication
echo -e "${YELLOW}  Configuring Docker authentication for Artifact Registry...${NC}"
gcloud auth configure-docker $REGION-docker.pkg.dev

# Pull the official Wiki.js image
echo -e "${YELLOW}  Pulling official Wiki.js image...${NC}"
docker pull ghcr.io/requarks/wiki:2

# Tag the image for Artifact Registry
echo -e "${YELLOW}  Tagging image for Artifact Registry...${NC}"
docker tag ghcr.io/requarks/wiki:2 $ARTIFACT_URL/wiki:2
docker tag ghcr.io/requarks/wiki:2 $ARTIFACT_URL/wiki:latest

# Push the image to Artifact Registry
echo -e "${YELLOW}  Pushing image to Artifact Registry...${NC}"
docker push $ARTIFACT_URL/wiki:2
docker push $ARTIFACT_URL/wiki:latest

echo -e "${GREEN}✓ Image successfully pushed to Artifact Registry!${NC}"

# ============================================================================
# STEP 5: UPDATE CLOUD RUN WITH WIKI.JS IMAGE
# ============================================================================
echo ""
echo -e "${YELLOW}☁️  Step 5: Updating Cloud Run service with Wiki.js image...${NC}"

# Update Cloud Run service with the new image
gcloud run services update wiki-js \
    --image=$ARTIFACT_URL/wiki:2 \
    --region=$REGION \
    --project=$PROJECT_ID

echo -e "${GREEN}✓ Cloud Run service updated successfully!${NC}"

# ============================================================================
# STEP 6: GET FINAL STATUS AND URL
# ============================================================================
echo ""
echo -e "${GREEN}🎉 DEPLOYMENT COMPLETED SUCCESSFULLY!${NC}"
echo "=============================================================="

# Get the service URL
SERVICE_URL=$(gcloud run services describe wiki-js --region=$REGION --project=$PROJECT_ID --format="value(status.url)")

echo -e "${BLUE}📋 Deployment Summary:${NC}"
echo "   Project ID: $PROJECT_ID"
echo "   Region: $REGION"
echo "   Service: wiki-js"
echo "   Database: wiki-postgres-instance"
echo "   Registry: $ARTIFACT_URL"
echo ""
echo -e "${GREEN}🌐 Your Wiki.js application is now available at:${NC}"
echo -e "${GREEN}   $SERVICE_URL${NC}"
echo ""
echo -e "${YELLOW}📝 Next Steps:${NC}"
echo "1. Visit the URL above to complete Wiki.js setup"
echo "2. The database connection is pre-configured"
echo "3. Create your admin account and start using Wiki.js!"
echo ""
echo -e "${BLUE}💡 Useful commands:${NC}"
echo "   View logs: gcloud run services logs read wiki-js --region=$REGION"
echo "   Destroy all: cd terraform && terraform destroy"
echo ""
echo -e "${GREEN}✨ Happy wiki-ing! ✨${NC}"