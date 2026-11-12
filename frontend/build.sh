export PROJECT_ID="your-gcp-project-id"
export REGION="us-central1"
export FRONTEND_SERVICE_NAME="rag-frontend"

# Get backend URL
export BACKEND_URL=$(gcloud run services describe rag-service --region $REGION --format='value(status.url)')

# 1. Build Frontend Container Image using Cloud Build (passing the backend URL)
gcloud builds submit \
  --tag gcr.io/$PROJECT_ID/$FRONTEND_SERVICE_NAME \
  --substitutions=_VITE_API_URL=$BACKEND_URL

# 2. Deploy to Cloud Run
gcloud run deploy $FRONTEND_SERVICE_NAME \
  --image gcr.io/$PROJECT_ID/$FRONTEND_SERVICE_NAME \
  --platform managed \
  --region $REGION \
  --memory 512Mi \
  --allow-unauthenticated