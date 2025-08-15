#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Wiki.js deployment to GCP Cloud Run${NC}"

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

echo -e "${YELLOW}Using Project ID: $PROJECT_ID${NC}"
echo -e "${YELLOW}Using Region: $REGION${NC}"

# Authenticate with gcloud (if needed)
echo -e "${YELLOW}Checking gcloud authentication...${NC}"
gcloud config set project $PROJECT_ID

# Change to terraform directory
cd terraform

# Initialize Terraform
echo -e "${YELLOW}Initializing Terraform...${NC}"
terraform init

# Plan the deployment
echo -e "${YELLOW}Planning Terraform deployment...${NC}"
terraform plan

# Apply the deployment
echo -e "${YELLOW}Applying Terraform deployment...${NC}"
terraform apply -auto-approve

# Get the Artifact Registry URL
ARTIFACT_URL=$(terraform output -raw artifact_registry_url)

echo -e "${GREEN}Terraform deployment completed!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Push the Wiki.js image to Artifact Registry:"
echo "   docker pull ghcr.io/requarks/wiki:2"
echo "   docker tag ghcr.io/requarks/wiki:2 $ARTIFACT_URL/wiki:2"
echo "   gcloud auth configure-docker $REGION-docker.pkg.dev"
echo "   docker push $ARTIFACT_URL/wiki:2"
echo ""
echo "2. Update the Cloud Run service to use the pushed image:"
echo "   terraform apply"
echo ""
echo "3. Your Wiki.js application will be available at:"
terraform output wiki_js_url

echo -e "${GREEN}Deployment script completed!${NC}"