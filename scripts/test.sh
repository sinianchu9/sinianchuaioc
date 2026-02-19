#!/bin/bash
# AIOC Test Script - Minimal verification
# Usage: bash scripts/test.sh

set -e

BASE_URL="${1:-http://localhost:8080}"

echo "🧪 AIOC API Test Suite"
echo "   Base URL: $BASE_URL"
echo ""

# 1. Health check
echo "1️⃣ Health Check..."
HEALTH=$(curl -s "$BASE_URL/api/v1/health")
echo "   $HEALTH"
echo ""

# 2. Login
echo "2️⃣ Login as admin..."
LOGIN_RESP=$(curl -s -X POST "$BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@aioc.internal","password":"123456"}')
echo "   Response: $(echo $LOGIN_RESP | head -c 200)..."

# Extract token (requires jq)
if command -v jq >/dev/null 2>&1; then
  TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.access_token')
  echo "   Token: ${TOKEN:0:30}..."
else
  echo "   ⚠️ Install jq to auto-extract token"
  echo "   Please manually extract access_token from the response above"
  exit 0
fi
echo ""

# 3. Client Capabilities
echo "3️⃣ Client Capabilities..."
CAPS=$(curl -s "$BASE_URL/api/v1/client/capabilities" \
  -H "Authorization: Bearer $TOKEN")
echo "   $CAPS"
echo ""

# 4. Billing Summary
echo "4️⃣ Billing Summary..."
BILLING=$(curl -s "$BASE_URL/api/v1/billing/summary" \
  -H "Authorization: Bearer $TOKEN")
echo "   $BILLING"
echo ""

# 5. Sessions
echo "5️⃣ Create Session..."
SESSION=$(curl -s -X POST "$BASE_URL/api/v1/sessions" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title":"Test Chat","model_mode":"economy"}')
echo "   $SESSION"
echo ""

# 6. List Sessions
echo "6️⃣ List Sessions..."
SESSIONS=$(curl -s "$BASE_URL/api/v1/sessions" \
  -H "Authorization: Bearer $TOKEN")
echo "   $SESSIONS"
echo ""

# 7. Chat Stream
echo "7️⃣ Chat Stream (Economy mode)..."
echo "   Sending: 'Say hello in 10 words'"
timeout 30 curl -N -s -X POST "$BASE_URL/api/v1/chat/stream" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"messages":[{"role":"user","content":"Say hello in 10 words"}],"mode":"economy"}' || true
echo ""
echo ""

echo "✅ All tests complete!"
