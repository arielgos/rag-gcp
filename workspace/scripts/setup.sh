#!/usr/bin/env bash
set -euo pipefail

# Set project ID for the current session
export PROJECT_ID="rag-gcp-514613"

export SERVICE_ACCOUNT_NAME="github-cloud-run-deployer"
export API_SERVICE_ACCOUNT="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
export BACKEND_RUNTIME_SERVICE_ACCOUNT_NAME="rag-gcp-backend-runtime"
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
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"

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
