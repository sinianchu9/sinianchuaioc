#!/bin/bash
# AIOC Engine Integration Test Script
# Tests the full flow: login → stream via engine → verify

set -e

API_BASE="${API_BASE:-http://localhost:8080}"
EMAIL="${EMAIL:-admin@aioc.internal}"
PASSWORD="${PASSWORD:-123456}"

echo "=== AIOC Engine Integration Test ==="
echo "Target: $API_BASE"
echo ""

# 1. Login
echo "1. 🔑 Logging in..."
LOGIN_RESP=$(curl -s -X POST "$API_BASE/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -H "X-Client-Id: 00000000-0000-0000-0000-000000000102" \
  -H "X-Client-Version: 1.0.0" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")

TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.access_token // empty')
if [ -z "$TOKEN" ]; then
  echo "❌ Login failed: $LOGIN_RESP"
  exit 1
fi
echo "✅ Got JWT token"

# 2. Chat stream
echo ""
echo "2. 💬 Sending chat stream request..."
echo "--- Stream output ---"
curl -N -s -X POST "$API_BASE/api/v1/chat/stream" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -H "X-Client-Id: 00000000-0000-0000-0000-000000000102" \
  -H "X-Client-Version: 1.0.0" \
  -d '{"mode":"economy","messages":[{"role":"user","content":"Reply 123"}]}'
echo ""
echo "--- End of stream ---"

# 3. Check billing logs
echo ""
echo "3. 📊 Checking billing logs..."
docker exec aioc-postgres psql -U aioc -c "SELECT request_id, model, tokens_in, tokens_out, cost FROM billing_logs ORDER BY ts DESC LIMIT 3;" 2>/dev/null || echo "(Cannot connect to postgres — run inside Docker network)"

# 4. Check audit logs
echo ""
echo "4. 📋 Checking audit logs..."
docker exec aioc-postgres psql -U aioc -c "SELECT trace_id, model_used, tokens_in, tokens_out, fallback_used FROM audit_logs ORDER BY ts DESC LIMIT 3;" 2>/dev/null || echo "(Cannot connect to postgres — run inside Docker network)"

echo ""
echo "=== Test Complete ==="
