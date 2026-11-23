#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# RAG-GCP Interactive Setup Wizard
#
# Walks step by step through:
#   1. Google Cloud authentication
#   2. Project creation (or reuse)
#   3. Billing account linking
#   4. Service (API) activation
#   5. Service account creation
#   6. IAM policy bindings
#   7. Workload Identity Federation (GitHub Actions)
#   8. Artifact Registry repositories
#   9. Cloud SQL (PostgreSQL + pgvector)
#  10. Final summary with values for GitHub secrets/variables
#
# Each step asks for the data it needs, shows the commands it will run,
# and lets you run or skip it.
# =============================================================================

# ----------------------------- UI helpers -----------------------------------

BOLD=$(tput bold 2>/dev/null || true)
DIM=$(tput dim 2>/dev/null || true)
RED=$(tput setaf 1 2>/dev/null || true)
GREEN=$(tput setaf 2 2>/dev/null || true)
YELLOW=$(tput setaf 3 2>/dev/null || true)
CYAN=$(tput setaf 6 2>/dev/null || true)
RESET=$(tput sgr0 2>/dev/null || true)

banner() {
  echo ""
  echo "${BOLD}${CYAN}==============================================================${RESET}"
  echo "${BOLD}${CYAN}  $1${RESET}"
  echo "${BOLD}${CYAN}==============================================================${RESET}"
}

info()  { echo "${CYAN}[INFO]${RESET} $*"; }
ok()    { echo "${GREEN}[ OK ]${RESET} $*"; }
warn()  { echo "${YELLOW}[WARN]${RESET} $*"; }
fail()  { echo "${RED}[FAIL]${RESET} $*"; }

# ask VAR "Prompt" "default"
ask() {
  local __var=$1 __prompt=$2 __default=${3:-} __answer
  if [[ -n "$__default" ]]; then
    read -r -p "${BOLD}${__prompt}${RESET} [${DIM}${__default}${RESET}]: " __answer
    __answer=${__answer:-$__default}
  else
    while true; do
      read -r -p "${BOLD}${__prompt}${RESET}: " __answer
      [[ -n "$__answer" ]] && break
      warn "A value is required."
    done
  fi
  printf -v "$__var" '%s' "$__answer"
}

# ask_secret VAR "Prompt"
ask_secret() {
  local __var=$1 __prompt=$2 __answer __confirm
  while true; do
    read -r -s -p "${BOLD}${__prompt}${RESET}: " __answer; echo ""
    [[ -z "$__answer" ]] && { warn "A value is required."; continue; }
    read -r -s -p "${BOLD}Confirm ${__prompt}${RESET}: " __confirm; echo ""
    [[ "$__answer" == "$__confirm" ]] && break
    warn "Values do not match, try again."
  done
  printf -v "$__var" '%s' "$__answer"
}

# confirm "Question" [default: Y|N] -> returns 0 for yes
confirm() {
  local prompt=$1 default=${2:-Y} answer hint
  if [[ "$default" == "Y" ]]; then hint="Y/n"; else hint="y/N"; fi
  read -r -p "${BOLD}${prompt}${RESET} [${hint}]: " answer
  answer=${answer:-$default}
  [[ "$answer" =~ ^[Yy] ]]
}

# run_cmd "description" cmd args... -> shows the command, asks, then runs it.
# Returns 0 if executed OK, 1 if skipped, aborts never (lets you retry/skip).
run_cmd() {
  local desc=$1; shift
  echo ""
  info "$desc"
  echo "${DIM}\$ $*${RESET}"
  if ! confirm "Run this command?"; then
    warn "Skipped."
    return 1
  fi
  while true; do
    if "$@"; then
      ok "Done."
      return 0
    fi
    fail "Command failed."
    if confirm "Retry?" N; then continue; fi
    if confirm "Continue wizard anyway?" Y; then return 1; fi
    exit 1
  done
}

# step_header N "Title" -> asks whether to run the step at all
step_enabled() {
  local num=$1 title=$2
  banner "STEP $num: $title"
  if confirm "Run this step?"; then return 0; fi
  warn "Step $num skipped."
  return 1
}

require_gcloud() {
  if ! command -v gcloud >/dev/null 2>&1; then
    fail "gcloud CLI not found. Install it from https://cloud.google.com/sdk/docs/install"
    exit 1
  fi
}

# ----------------------------- Start ----------------------------------------

banner "RAG-GCP Setup Wizard"
echo "This wizard provisions everything needed to deploy the RAG app on GCP."
echo "You can skip any step (useful for re-runs on an existing project)."
require_gcloud

# =============================================================================
# STEP 1: Authentication
# =============================================================================
if step_enabled 1 "Google Cloud Authentication"; then
  CURRENT_ACCOUNT=$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null || true)
  if [[ -n "$CURRENT_ACCOUNT" ]]; then
    info "Currently authenticated as: ${BOLD}${CURRENT_ACCOUNT}${RESET}"
    if confirm "Use this account?"; then
      ok "Using $CURRENT_ACCOUNT"
    else
      run_cmd "Log in to Google Cloud" gcloud auth login || true
    fi
  else
    run_cmd "Log in to Google Cloud" gcloud auth login || true
  fi
  gcloud auth list
fi

# =============================================================================
# STEP 2: Project
# =============================================================================
banner "STEP 2: Project"
ask PROJECT_ID "GCP Project ID" "rag-gcp-upds-22"
export PROJECT_ID

if gcloud projects describe "$PROJECT_ID" >/dev/null 2>&1; then
  ok "Project '$PROJECT_ID' already exists; it will be reused."
else
  info "Project '$PROJECT_ID' does not exist (or you lack access)."
  run_cmd "Create project '$PROJECT_ID'" gcloud projects create "$PROJECT_ID" || true
fi

run_cmd "Set '$PROJECT_ID' as the active project" \
  gcloud config set project "$PROJECT_ID" || true

PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null || true)
if [[ -n "$PROJECT_NUMBER" ]]; then
  export PROJECT_NUMBER
  ok "Project ID: $PROJECT_ID | Project Number: $PROJECT_NUMBER"
else
  warn "Could not resolve the project number. Steps that need it may fail."
fi

# =============================================================================
# STEP 3: Billing
# =============================================================================
if step_enabled 3 "Link Billing Account"; then
  info "Available billing accounts:"
  gcloud billing accounts list || true
  echo ""
  DEFAULT_BILLING=$(gcloud billing accounts list --format='value(ACCOUNT_ID)' 2>/dev/null | head -n 1 || true)
  ask BILLING_ACCOUNT_ID "Billing Account ID to link" "${DEFAULT_BILLING}"
  export BILLING_ACCOUNT_ID
  run_cmd "Link billing account '$BILLING_ACCOUNT_ID' to '$PROJECT_ID'" \
    gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID" || true
fi

# =============================================================================
# STEP 4: Enable GCP Services (APIs)
# =============================================================================
if step_enabled 4 "Enable GCP Services (APIs)"; then
  SERVICES=(
    iam.googleapis.com
    iamcredentials.googleapis.com
    sts.googleapis.com
    run.googleapis.com
    cloudbuild.googleapis.com
    artifactregistry.googleapis.com
    sqladmin.googleapis.com
    generativelanguage.googleapis.com
    sql-component.googleapis.com
  )
  info "The following services will be enabled:"
  printf '  - %s\n' "${SERVICES[@]}"
  run_cmd "Enable services on '$PROJECT_ID'" \
    gcloud services enable "${SERVICES[@]}" --project "$PROJECT_ID" || true
  if confirm "List all enabled services?" N; then
    gcloud services list --enabled --project "$PROJECT_ID"
  fi
fi

# =============================================================================
# STEP 5: Service Accounts
# =============================================================================
banner "STEP 5: Service Accounts"
ask BACKEND_SA_NAME "Backend service account name" "github-cloud-run-backend"
ask FRONTEND_SA_NAME "Frontend service account name" "github-cloud-run-frontend"
export BACKEND_RUNTIME_SERVICE_ACCOUNT="${BACKEND_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
export FRONTEND_RUNTIME_SERVICE_ACCOUNT="${FRONTEND_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"

if confirm "Create the service accounts now?"; then
  if gcloud iam service-accounts describe "$BACKEND_RUNTIME_SERVICE_ACCOUNT" --project "$PROJECT_ID" >/dev/null 2>&1; then
    ok "Backend service account already exists."
  else
    run_cmd "Create backend service account '$BACKEND_SA_NAME'" \
      gcloud iam service-accounts create "$BACKEND_SA_NAME" \
        --project "$PROJECT_ID" \
        --display-name "GitHub Cloud Run Backend Deployer" || true
  fi
  if gcloud iam service-accounts describe "$FRONTEND_RUNTIME_SERVICE_ACCOUNT" --project "$PROJECT_ID" >/dev/null 2>&1; then
    ok "Frontend service account already exists."
  else
    run_cmd "Create frontend service account '$FRONTEND_SA_NAME'" \
      gcloud iam service-accounts create "$FRONTEND_SA_NAME" \
        --project "$PROJECT_ID" \
        --display-name "GitHub Cloud Run Frontend Deployer" || true
  fi
else
  warn "Service account creation skipped."
fi

# =============================================================================
# STEP 6: IAM Policy Bindings
# =============================================================================
if step_enabled 6 "IAM Policy Bindings"; then
  BACKEND_ROLES=(
    roles/run.admin
    roles/cloudbuild.builds.editor
    roles/artifactregistry.writer
    roles/iam.serviceAccountUser
    roles/storage.admin
    roles/cloudsql.client
  )
  FRONTEND_ROLES=(
    roles/run.admin
    roles/cloudbuild.builds.editor
    roles/artifactregistry.writer
    roles/iam.serviceAccountUser
    roles/storage.admin
  )

  info "Backend SA ($BACKEND_RUNTIME_SERVICE_ACCOUNT) roles:"
  printf '  - %s\n' "${BACKEND_ROLES[@]}"
  if confirm "Grant backend roles?"; then
    for role in "${BACKEND_ROLES[@]}"; do
      run_cmd "Grant $role to backend SA" \
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
          --member "serviceAccount:$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
          --role "$role" \
          --condition=None || true
    done
  fi

  echo ""
  info "Frontend SA ($FRONTEND_RUNTIME_SERVICE_ACCOUNT) roles:"
  printf '  - %s\n' "${FRONTEND_ROLES[@]}"
  if confirm "Grant frontend roles?"; then
    for role in "${FRONTEND_ROLES[@]}"; do
      run_cmd "Grant $role to frontend SA" \
        gcloud projects add-iam-policy-binding "$PROJECT_ID" \
          --member "serviceAccount:$FRONTEND_RUNTIME_SERVICE_ACCOUNT" \
          --role "$role" \
          --condition=None || true
    done
  fi
fi

# =============================================================================
# STEP 7: Workload Identity Federation (GitHub Actions)
# =============================================================================
if step_enabled 7 "Workload Identity Federation (GitHub Actions)"; then
  ask WORKLOAD_POOL_NAME "Workload identity pool name" "github-pool"
  ask WORKLOAD_PROVIDER_NAME "Workload identity provider name" "github-provider"
  ask GITHUB_REPOSITORY "GitHub repository (owner/repo)" "arielgos/rag-gcp-22"
  export WORKLOAD_POOL_NAME WORKLOAD_PROVIDER_NAME GITHUB_REPOSITORY

  if gcloud iam workload-identity-pools describe "$WORKLOAD_POOL_NAME" \
       --project "$PROJECT_ID" --location global >/dev/null 2>&1; then
    ok "Workload identity pool '$WORKLOAD_POOL_NAME' already exists."
  else
    run_cmd "Create workload identity pool '$WORKLOAD_POOL_NAME'" \
      gcloud iam workload-identity-pools create "$WORKLOAD_POOL_NAME" \
        --project "$PROJECT_ID" \
        --location global \
        --display-name "GitHub Pool" || true
  fi

  if gcloud iam workload-identity-pools providers describe "$WORKLOAD_PROVIDER_NAME" \
       --project "$PROJECT_ID" --location global \
       --workload-identity-pool "$WORKLOAD_POOL_NAME" >/dev/null 2>&1; then
    ok "Workload identity provider '$WORKLOAD_PROVIDER_NAME' already exists."
  else
    run_cmd "Create OIDC provider '$WORKLOAD_PROVIDER_NAME' for repo '$GITHUB_REPOSITORY'" \
      gcloud iam workload-identity-pools providers create-oidc "$WORKLOAD_PROVIDER_NAME" \
        --project "$PROJECT_ID" \
        --location global \
        --workload-identity-pool "$WORKLOAD_POOL_NAME" \
        --display-name "GitHub Provider" \
        --issuer-uri "https://token.actions.githubusercontent.com" \
        --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository" \
        --attribute-condition="assertion.repository == '$GITHUB_REPOSITORY'" || true
  fi

  if [[ -n "${PROJECT_NUMBER:-}" ]]; then
    WIF_MEMBER="principalSet://iam.googleapis.com/projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$WORKLOAD_POOL_NAME/attribute.repository/$GITHUB_REPOSITORY"
    run_cmd "Allow repo '$GITHUB_REPOSITORY' to impersonate the backend SA" \
      gcloud iam service-accounts add-iam-policy-binding \
        "$BACKEND_RUNTIME_SERVICE_ACCOUNT" \
        --project "$PROJECT_ID" \
        --role roles/iam.workloadIdentityUser \
        --member "$WIF_MEMBER" || true
    run_cmd "Allow repo '$GITHUB_REPOSITORY' to impersonate the frontend SA" \
      gcloud iam service-accounts add-iam-policy-binding \
        "$FRONTEND_RUNTIME_SERVICE_ACCOUNT" \
        --project "$PROJECT_ID" \
        --role roles/iam.workloadIdentityUser \
        --member "$WIF_MEMBER" || true
  else
    warn "PROJECT_NUMBER unknown; cannot bind service accounts to the pool."
  fi
fi

# =============================================================================
# STEP 8: Artifact Registry
# =============================================================================
if step_enabled 8 "Artifact Registry Repositories"; then
  ask REGION "GCP region" "us-central1"
  ask ARTIFACT_REGISTRY_REPOSITORY "Artifact Registry repository name" "rag-gcp-artifacts"
  export REGION ARTIFACT_REGISTRY_REPOSITORY

  if gcloud artifacts repositories describe "$ARTIFACT_REGISTRY_REPOSITORY" \
       --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
    ok "Repository '$ARTIFACT_REGISTRY_REPOSITORY' already exists."
  else
    run_cmd "Create Docker repository '$ARTIFACT_REGISTRY_REPOSITORY' in $REGION" \
      gcloud artifacts repositories create "$ARTIFACT_REGISTRY_REPOSITORY" \
        --repository-format=docker \
        --location="$REGION" \
        --description="Docker repository for Cloud Run source deployments" \
        --project "$PROJECT_ID" || true
  fi

  if confirm "Also create the 'cloud-run-source-deploy' repository (used by 'gcloud run deploy --source')?"; then
    if gcloud artifacts repositories describe cloud-run-source-deploy \
         --location "$REGION" --project "$PROJECT_ID" >/dev/null 2>&1; then
      ok "Repository 'cloud-run-source-deploy' already exists."
    else
      run_cmd "Create Docker repository 'cloud-run-source-deploy' in $REGION" \
        gcloud artifacts repositories create cloud-run-source-deploy \
          --repository-format=docker \
          --location="$REGION" \
          --project="$PROJECT_ID" || true
    fi
  fi
fi

# =============================================================================
# STEP 9: Cloud SQL (PostgreSQL + pgvector)
# =============================================================================
if step_enabled 9 "Cloud SQL Database (PostgreSQL + pgvector)"; then
  REGION=${REGION:-us-central1}
  ask REGION "GCP region for Cloud SQL" "$REGION"
  ask INSTANCE_NAME "Cloud SQL instance name" "rag-postgres-instance"
  ask DB_TIER "Instance tier" "db-custom-2-7680"
  ask DB_NAME "Database name" "ragdb"
  ask DB_USER "Database user" "raguser"
  ask_secret DB_PASS "Database password"
  export REGION INSTANCE_NAME DB_NAME DB_USER DB_PASS

  if gcloud sql instances describe "$INSTANCE_NAME" --project "$PROJECT_ID" >/dev/null 2>&1; then
    ok "Cloud SQL instance '$INSTANCE_NAME' already exists."
  else
    warn "Creating a Cloud SQL instance can take 10+ minutes."
    run_cmd "Create PostgreSQL 15 instance '$INSTANCE_NAME' (ML integration enabled)" \
      gcloud sql instances create "$INSTANCE_NAME" \
        --project "$PROJECT_ID" \
        --database-version=POSTGRES_15 \
        --tier="$DB_TIER" \
        --region="$REGION" \
        --enable-google-ml-integration \
        --database-flags=cloudsql.enable_google_ml_integration=on || true
  fi

  run_cmd "Create database '$DB_NAME'" \
    gcloud sql databases create "$DB_NAME" --instance="$INSTANCE_NAME" --project "$PROJECT_ID" || true

  run_cmd "Create database user '$DB_USER'" \
    gcloud sql users create "$DB_USER" --instance="$INSTANCE_NAME" --password="$DB_PASS" --project "$PROJECT_ID" || true

  INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe "$INSTANCE_NAME" \
    --project "$PROJECT_ID" --format="value(connectionName)" 2>/dev/null || true)
  export INSTANCE_CONNECTION_NAME
  [[ -n "$INSTANCE_CONNECTION_NAME" ]] && ok "Instance connection name: $INSTANCE_CONNECTION_NAME"

  echo ""
  info "The 'vector' extension (pgvector) must be created inside the database."
  if confirm "Connect now with 'gcloud sql connect' to create the extension?"; then
    info "You'll be prompted for the password of '$DB_USER'."
    info "Once connected, run:  ${BOLD}CREATE EXTENSION IF NOT EXISTS vector;${RESET}  then  ${BOLD}\\q${RESET}  to exit."
    gcloud sql connect "$INSTANCE_NAME" --user="$DB_USER" --database="$DB_NAME" --project "$PROJECT_ID" || \
      warn "Connection failed. You can run the extension creation later."
  else
    warn "Remember to run 'CREATE EXTENSION IF NOT EXISTS vector;' in '$DB_NAME' before using the app."
  fi
fi

# =============================================================================
# STEP 10: Summary
# =============================================================================
banner "STEP 10: Summary"

WIF_PROVIDER_FULL=""
if [[ -n "${WORKLOAD_POOL_NAME:-}" && -n "${WORKLOAD_PROVIDER_NAME:-}" ]]; then
  WIF_PROVIDER_FULL=$(gcloud iam workload-identity-pools providers describe "$WORKLOAD_PROVIDER_NAME" \
    --project="$PROJECT_ID" --location=global \
    --workload-identity-pool="$WORKLOAD_POOL_NAME" \
    --format="value(name)" 2>/dev/null || true)
fi

echo ""
echo "${BOLD}Provisioned configuration:${RESET}"
echo "  PROJECT_ID:                  ${PROJECT_ID}"
echo "  PROJECT_NUMBER:              ${PROJECT_NUMBER:-<unknown>}"
echo "  BACKEND_SERVICE_ACCOUNT:     ${BACKEND_RUNTIME_SERVICE_ACCOUNT:-<not configured>}"
echo "  FRONTEND_SERVICE_ACCOUNT:    ${FRONTEND_RUNTIME_SERVICE_ACCOUNT:-<not configured>}"
echo "  WIF_PROVIDER:                ${WIF_PROVIDER_FULL:-<not configured>}"
echo "  ARTIFACT_REGISTRY:           ${ARTIFACT_REGISTRY_REPOSITORY:-<not configured>} (${REGION:-<region>})"
echo "  SQL_INSTANCE:                ${INSTANCE_NAME:-<not configured>}"
echo "  SQL_CONNECTION_NAME:         ${INSTANCE_CONNECTION_NAME:-<not configured>}"
echo "  DB_NAME / DB_USER:           ${DB_NAME:-<not configured>} / ${DB_USER:-<not configured>}"
echo ""
info "Use WIF_PROVIDER and the service account emails in your GitHub Actions"
info "workflow (google-github-actions/auth) secrets/variables."
ok "Wizard finished."
