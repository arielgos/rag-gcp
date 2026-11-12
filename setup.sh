# Variables
export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export INSTANCE_NAME="rag-postgres-instance"
export DB_NAME="ragdb"
export DB_USER="raguser"
export DB_PASS="StrongPassword123!"

gcloud config set project $PROJECT_ID

# 1. Create Cloud SQL PostgreSQL instance (v15 or higher is required for pgvector)
gcloud sql instances create $INSTANCE_NAME \
    --database-version=POSTGRES_15 \
    --tier=db-custom-2-7680 \
    --region=$REGION \
    --database-flags=cloudsql.enable_pgvector=on

# 2. Create the Database and User
gcloud sql databases create $DB_NAME --instance=$INSTANCE_NAME
gcloud sql users create $DB_USER --instance=$INSTANCE_NAME --password=$DB_PASS

# Get the full instance connection name (PROJECT_ID:REGION:INSTANCE_NAME)
export INSTANCE_CONNECTION_NAME=$(gcloud sql instances describe $INSTANCE_NAME --format="value(connectionName)")
echo "Connection Name: $INSTANCE_CONNECTION_NAME"