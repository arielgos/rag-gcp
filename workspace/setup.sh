#!/usr/bin/env bash
set -euo pipefail

# Set project ID for the current session
export PROJECT_ID="rag-gcp-514613"
export SERVICE_ACCOUNT_NAME="github-cloud-run-deployer"
export BACKEND_RUNTIME_SERVICE_ACCOUNT="$BACKEND_RUNTIME_SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"

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
  --project "$PROJECT_ID"

gcloud services list --enabled --project "$PROJECT_ID"

# Create service account
echo "Creating service account..."
gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
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

# Create backend runtime service account
echo "Creating backend runtime service account..."
gcloud iam service-accounts create "$BACKEND_RUNTIME_SERVICE_ACCOUNT_NAME" \
  --project "$PROJECT_ID" \
  --display-name "Backend Runtime Service Account"

# Add IAM policies to backend runtime service account
echo "Setting up IAM policies for backend runtime service account..."
gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/run.invoker

gcloud projects add-iam-policy-binding "$PROJECT_ID" \
  --member "serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
  --role roles/iam.serviceAccountUser

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

# Create Artifact Registry repository
echo "Creating Artifact Registry repository..."
gcloud artifacts repositories create "$GITHUB_REPOSITORY" \
  --repository-format=docker \
  --location=us-central1 \
  --description="Docker repository for Cloud Run source deployments" \
  --project "$PROJECT_ID"
