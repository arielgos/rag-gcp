#!/bin/bash
source .env
export GEMINI_API_KEY="$GEMINI_API_KEY"
docker compose up --build -d