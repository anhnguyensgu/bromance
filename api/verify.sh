#!/bin/bash
echo "Registering user..."
curl -X POST http://127.0.0.1:3000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "password123"}'
echo -e "\n\nLogging in..."
TOKEN=$(curl -s -X POST http://127.0.0.1:3000/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "password": "password123"}' | jq -r .token)
echo "Token: $TOKEN"
