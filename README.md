# Wiki.js on Google Cloud Run

This repository contains Terraform configuration to deploy Wiki.js on Google Cloud Run with PostgreSQL Cloud SQL database.

## Architecture

- **Database**: PostgreSQL 15 on Cloud SQL
- **Container**: Wiki.js 2.x on Cloud Run
- **Registry**: Google Artifact Registry
- **Access**: Public (allUsers have Cloud Run Invoker role)

## Prerequisites

- Google Cloud SDK installed and configured
- Terraform installed (>= 1.0)
- Docker installed
- A GCP project with billing enabled

## Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/Comeon2022/wikijs.git
   cd wikijs