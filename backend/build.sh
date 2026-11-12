export SERVICE_NAME="rag-service"
export GEMINI_API_KEY="AIzaSy..."  # Or read from Secret Manager

# 1. Build using Google Cloud Build
gcloud builds submit --tag gcr.io/$PROJECT_ID/$SERVICE_NAME

# 2. Deploy to Cloud Run
# Note: Allocate at least 2Gi of memory for MarkItDown and FlashRank processing
gcloud run deploy $SERVICE_NAME \
    --image gcr.io/$PROJECT_ID/$SERVICE_NAME \
    --platform managed \
    --region $REGION \
    --memory 2Gi \
    --cpu 2 \
    --timeout 300 \
    --add-cloudsql-instances $INSTANCE_CONNECTION_NAME \
    --set-env-vars INSTANCE_CONNECTION_NAME=$INSTANCE_CONNECTION_NAME \
    --set-env-vars DB_NAME=$DB_NAME \
    --set-env-vars DB_USER=$DB_USER \
    --set-env-vars DB_PASS=$DB_PASS \
    --set-env-vars GEMINI_API_KEY=$GEMINI_API_KEY \
    --allow-unauthenticated