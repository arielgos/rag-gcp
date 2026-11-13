#!/usr/bin/env bash
set -euo pipefail

# Set project ID for the current session
export PROJECT_ID="rag-gcp-514613"

export BACKEND_RUNTIME_SERVICE_ACCOUNT="github-cloud-run-backend@$PROJECT_ID.iam.gserviceaccount.com"
export FRONTEND_RUNTIME_SERVICE_ACCOUNT="github-cloud-run-frontend@$PROJECT_ID.iam.gserviceaccount.com"

export WORKLOAD_POOL_NAME="github-pool"
export WORKLOAD_PROVIDER_NAME="github-provider"
export GITHUB_REPOSITORY="arielgos/rag-gcp"
export GITHUB_BRANCH="main"

# Authenticate with Google Cloud
gcloud auth login
gcloud auth list

# Set project ID and project number for the current session
gcloud config set project "$PROJECT_ID"
gcloud config list

export PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

echo "Project ID: $PROJECT_ID"
echo "Project Number: $PROJECT_NUMBER"

echo "Enabling GCP services..."
gcloud services enable \
  iam.googleapis.com \
  iamcredentials.googleapis.com \
  sts.googleapis.com \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  sqladmin.googleapis.com \
  generativelanguage.googleapis.com \
  sql-component.googleapis.com \
  --project "$PROJECT_ID"

gcloud services list --enabled --project "$PROJECT_ID"

# Create service account
echo "Creating service account..."
gcloud iam service-accounts create "github-cloud-run-backend" \
  --project "$PROJECT_ID" \
  --display-name "GitHub Cloud Run Backend Deployer"
  
gcloud iam service-accounts create "github-cloud-run-frontend" \
  --project "$PROJECT_ID" \
  --display-name "GitHub Cloud Run Deployer"

# Add IAM policies to service account
echo "Setting up IAM policies..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/run.admin

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/cloudbuild.builds.editor

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/artifactregistry.writer

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/iam.serviceAccountUser

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/storage.admin"

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/cloudsql.client"

# Frontend service account IAM policies
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$FRONTEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/run.admin

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$FRONTEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/cloudbuild.builds.editor

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$FRONTEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/artifactregistry.writer

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$FRONTEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/iam.serviceAccountUser

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member="serviceAccount:$FRONTEND_RUNTIME_SERVICE_ACCOUNT" \
  --role="roles/storage.admin"

# Create workload identity pool
echo "Creating workload identity pool..."
gcloud iam workload-identity-pools create "$WORKLOAD_POOL_NAME" \
  --project "$PROJECT_ID" \
  --location global \
  --display-name "GitHub Pool"

# Create workload identity provider
echo "Creating workload identity provider..."
gcloud iam workload-identity-pools providers create-oidc "$WORKLOAD_PROVIDER_NAME" \
  --project "$PROJECT_ID" \
  --location global \
  --workload-identity-pool "$WORKLOAD_POOL_NAME" \
  --display-name "GitHub Provider" \
  --issuer-uri "https://token.actions.githubusercontent.com" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository == '$GITHUB_REPOSITORY'"

# Bind the service account to workload identity
echo "Binding service account to workload identity..."
gcloud iam service-accounts add-iam-policy-binding \
  "$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --project "$PROJECT_ID" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WORKLOAD_POOL_NAME/attribute.repository/$GITHUB_REPOSITORY"


gcloud iam service-accounts add-iam-policy-binding \
  "$FRONTEND_RUNTIME_SERVICE_ACCOUNT" \
  --project "$PROJECT_ID" \
  --role roles/iam.workloadIdentityUser \
  --member "principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WORKLOAD_POOL_NAME/attribute.repository/$GITHUB_REPOSITORY"


# Create Artifact Registry repository
echo "Creating Artifact Registry repository..."
gcloud artifacts repositories create "cloud-run-source-deploy" \
  --repository-format=docker \
  --location=us-central1 \
  --description="Docker repository for Cloud Run source deployments" \
  --project "$PROJECT_ID"


# Database setup

export REGION="us-central1"
export INSTANCE_NAME="rag-postgres-instance"
export DB_NAME="ragdb"
export DB_USER="raguser"
export DB_PASS="StrongPassword123!"

gcloud config set project $PROJECT_ID

# 1. Create Cloud SQL PostgreSQL instance (v15 or higher is required for pgvector)
gcloud sql instances create "$INSTANCE_NAME" \
    --database-version=POSTGRES_15 \
    --tier=db-custom-2-7680 \
    --region="$REGION" \
    --enable-google-ml-integration \
    --database-flags=cloudsql.enable_google_ml_integration=on

# 2. Create the Database and User
gcloud sql databases create $DB_NAME --instance=$INSTANCE_NAME
gcloud sql users create $DB_USER --instance=$INSTANCE_NAME --password=$DB_PASS

# Get the full instance connection name (PROJECT_ID:REGION:INSTANCE_NAME)
export INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe $INSTANCE_NAME --format="value(connectionName)")
echo "Connection Name: $INSTANCE_CONNECTION_NAME"

# PSQl Command to create the vector extension
CREATE EXTENSION IF NOT EXISTS vector;

gcloud iam workload-identity-pools providers list \
  --project="$PROJECT_ID" \
  --location="global" \
  --workload-identity-pool="$WORKLOAD_POOL_NAME" \
  --format="value(name)"