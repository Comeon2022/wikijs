# =============================================================================
# Wiki.js on Google Cloud Run - Terraform Configuration
# Version: 2.1.0
# Last Updated: 2025-08-15
# 
# Changes in v2.1.0:
# - Extended Cloud SQL timeout to 30 minutes
# - Added comprehensive IAM permissions for service account
# - Added time_sleep resource for SQL readiness
# - Commented out Cloud Build trigger
# - Fixed container port to 3000 (Wiki.js standard)
# - Added db-e2-micro tier for faster provisioning
# =============================================================================

# Variables
variable "project_id" {
  description = "GCP Project ID"
  type        = string
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-a"
}

# Provider configuration
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# NOTE: Required APIs are enabled by the deploy script
# If running Terraform manually, ensure these APIs are enabled:
# - cloudresourcemanager.googleapis.com
# - sqladmin.googleapis.com (Cloud SQL Admin API)
# - sql-component.googleapis.com (Cloud SQL API)
# - run.googleapis.com
# - artifactregistry.googleapis.com
# - cloudbuild.googleapis.com
# - iam.googleapis.com
# - compute.googleapis.com

# Service Account for Wiki.js
resource "google_service_account" "wiki_js_sa" {
  account_id   = "wiki-js-sa"
  display_name = "Wiki.js Service Account"
  project      = var.project_id
}

# Artifact Registry Repository
resource "google_artifact_registry_repository" "wiki_js_repo" {
  location      = var.region
  repository_id = "wiki-js"
  description   = "Repository for Wiki.js container images"
  format        = "DOCKER"
}

# IAM binding for service account to push to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "wiki_js_sa_writer" {
  project    = var.project_id
  location   = google_artifact_registry_repository.wiki_js_repo.location
  repository = google_artifact_registry_repository.wiki_js_repo.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# IAM binding for service account - Cloud Run Developer
resource "google_project_iam_member" "wiki_js_sa_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# IAM binding for service account - Logs Writer
resource "google_project_iam_member" "wiki_js_sa_logs_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# IAM binding for service account - Logs Reader
resource "google_project_iam_member" "wiki_js_sa_logs_reader" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# IAM binding for service account - Cloud SQL Client (for database access)
resource "google_project_iam_member" "wiki_js_sa_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.wiki_js_sa.email}"
}

# Cloud SQL PostgreSQL Instance
resource "google_sql_database_instance" "wiki_postgres" {
  name             = "wiki-postgres-instance"
  database_version = "POSTGRES_15"
  region          = var.region
  
  settings {
    tier = "db-e2-micro"  # Faster to provision than db-f1-micro
    
    backup_configuration {
      enabled = true
      start_time = "03:00"
    }
    
    ip_configuration {
      ipv4_enabled = true
      authorized_networks {
        name  = "allow-all"
        value = "0.0.0.0/0"
      }
    }
    
    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }
  }
  
  deletion_protection = false
  
  timeouts {
    create = "30m"
    update = "30m"  
    delete = "30m"
  }
}

# Wait for Cloud SQL to be fully ready before creating database
resource "time_sleep" "wait_for_sql_instance" {
  depends_on = [google_sql_database_instance.wiki_postgres]
  create_duration = "60s"
}

# Cloud SQL Database
resource "google_sql_database" "wiki_database" {
  name     = "wiki"
  instance = google_sql_database_instance.wiki_postgres.name
  
  depends_on = [time_sleep.wait_for_sql_instance]
}

# Cloud SQL User
resource "google_sql_user" "wiki_user" {
  name     = "wikijs"
  instance = google_sql_database_instance.wiki_postgres.name
  password = "wikijsrocks"
  
  depends_on = [time_sleep.wait_for_sql_instance]
}

# Cloud Run Service
resource "google_cloud_run_v2_service" "wiki_js" {
  name     = "wiki-js"
  location = var.region
  
  template {
    service_account = google_service_account.wiki_js_sa.email
    
    containers {
      # Use a placeholder image initially - will be updated after image push
      image = "gcr.io/cloudrun/hello"
      
      ports {
        container_port = 3000
      }
      
      env {
        name  = "DB_TYPE"
        value = "postgres"
      }
      
      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.wiki_postgres.public_ip_address
      }
      
      env {
        name  = "DB_PORT"
        value = "5432"
      }
      
      env {
        name  = "DB_USER"
        value = google_sql_user.wiki_user.name
      }
      
      env {
        name  = "DB_PASS"
        value = google_sql_user.wiki_user.password
      }
      
      env {
        name  = "DB_NAME"
        value = google_sql_database.wiki_database.name
      }
      
      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle = true
      }
    }
    
    scaling {
      min_instance_count = 0
      max_instance_count = 10
    }
  }
  
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }
  
  depends_on = [
    google_sql_database_instance.wiki_postgres,
    google_artifact_registry_repository.wiki_js_repo
  ]
}

# IAM policy to allow unauthenticated access (allUsers)
resource "google_cloud_run_service_iam_member" "public_access" {
  service  = google_cloud_run_v2_service.wiki_js.name
  location = google_cloud_run_v2_service.wiki_js.location
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Build trigger for pushing image to Artifact Registry (optional)
# Uncomment and configure if you want to set up automated builds from GitHub
# Requires connecting your GitHub repository to Cloud Build first
# Visit: https://console.cloud.google.com/cloud-build/triggers to connect

# resource "google_cloudbuild_trigger" "wiki_js_build" {
#   name        = "wiki-js-build"
#   description = "Build and push Wiki.js image to Artifact Registry"
#   
#   github {
#     owner = "requarks"  # Wiki.js repository owner
#     name  = "wiki"      # Repository name
#     push {
#       branch = "^main$"
#     }
#   }
#   
#   build {
#     step {
#       name = "gcr.io/cloud-builders/docker"
#       args = [
#         "build",
#         "-t", "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:2",
#         "-t", "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki:latest",
#         "."
#       ]
#     }
#     
#     step {
#       name = "gcr.io/cloud-builders/docker"
#       args = [
#         "push", 
#         "--all-tags",
#         "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}/wiki"
#       ]
#     }
#     
#     options {
#       logging = "CLOUD_LOGGING_ONLY"
#     }
#   }
#   
#   service_account = google_service_account.wiki_js_sa.id
#   
#   depends_on = [
#     google_artifact_registry_repository_iam_member.wiki_js_sa_writer
#   ]
# }

# Outputs
output "wiki_js_url" {
  description = "URL of the Wiki.js Cloud Run service"
  value       = google_cloud_run_v2_service.wiki_js.uri
}

output "postgres_connection_string" {
  description = "PostgreSQL connection string"
  value       = "postgresql://${google_sql_user.wiki_user.name}:${google_sql_user.wiki_user.password}@${google_sql_database_instance.wiki_postgres.public_ip_address}:5432/${google_sql_database.wiki_database.name}"
  sensitive   = true
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.wiki_js_repo.repository_id}"
}

output "service_account_email" {
  description = "Wiki.js Service Account email"
  value       = google_service_account.wiki_js_sa.email
}