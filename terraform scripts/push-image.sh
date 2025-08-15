#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Pushing Wiki.js image to Artifact Registry${NC}"

# Change to terraform directory to get outputs
cd terraform

# Get values from Terraform output
PROJECT_ID=$(terraform output -raw project_id 2>/dev/null || grep -E '^project_id' terraform.tfvars | cut -d'"' -f2)
REGION=$(terraform output -raw region 2>/dev/null || grep -E '^region' terraform.tfvars | cut -d'"' -f2 | head -1)
ARTIFACT_URL=$(terraform output -raw artifact_registry_url)

if [ -z "$PROJECT_ID" ] || [ -z "$REGION" ] || [ -z "$ARTIFACT_URL" ]; then
    echo -e "${RED}Error: Could not get required values. Make sure Terraform has been applied.${NC}"
    exit 1
fi

echo -e "${YELLOW}Project ID: $PROJECT_ID${NC}"
echo -e "${YELLOW}Region: $REGION${NC}"
echo -e "${YELLOW}Artifact Registry URL: $ARTIFACT_URL${NC}"

# Configure Docker authentication
echo -e "${YELLOW}Configuring Docker authentication for Artifact Registry...${NC}"
gcloud auth configure-docker $REGION-docker.pkg.dev

# Pull the official Wiki.js image
echo -e "${YELLOW}Pulling official Wiki.js image...${NC}"
docker pull ghcr.io/requarks/wiki:2

# Tag the image for Artifact Registry
echo -e "${YELLOW}Tagging image for Artifact Registry...${NC}"
docker tag ghcr.io/requarks/wiki:2 $ARTIFACT_URL/wiki:2
docker tag ghcr.io/requarks/wiki:2 $ARTIFACT_URL/wiki:latest

# Push the image to Artifact Registry
echo -e "${YELLOW}Pushing image to Artifact Registry...${NC}"
docker push $ARTIFACT_URL/wiki:2
docker push $ARTIFACT_URL/wiki:latest

echo -e "${GREEN}Image successfully pushed to Artifact Registry!${NC}"
echo -e "${YELLOW}You can now update your Cloud Run service to use this image.${NC}"

# Optionally update Cloud Run service
read -p "Do you want to update the Cloud Run service now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Updating Cloud Run service...${NC}"
    terraform apply -auto-approve
    echo -e "${GREEN}Cloud Run service updated!${NC}"
    echo -e "${YELLOW}Your Wiki.js application is available at:${NC}"
    terraform output wiki_js_url
fi