#!/bin/bash
# AIOC Development Startup Script
# Usage: bash scripts/dev.sh

set -e

echo "🚀 Starting AIOC Development Environment..."

# Check dependencies
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || command -v docker compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed."; exit 1; }

# Navigate to project root
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Start services
echo "📦 Starting PostgreSQL, Redis, Gateway, Core..."
docker compose -f infra/docker-compose/saas.dev.yml up -d --build

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 10

echo ""
echo "✅ AIOC Development Environment is ready!"
echo ""
echo "📡 Endpoints:"
echo "   Gateway:  http://localhost:8080"
echo "   Core:     http://localhost:8081"
echo "   Postgres: localhost:5432"
echo "   Redis:    localhost:6379"
echo ""
echo "🔑 Test Accounts:"
echo "   admin@aioc.internal / 123456"
echo "   user@aioc.internal  / 123456"
echo ""
echo "📝 Quick Start:"
echo "   # Login"
echo '   curl -X POST http://localhost:8080/api/v1/auth/login \'
echo '     -H "Content-Type: application/json" \'
echo '     -d '\''{"email":"admin@aioc.internal","password":"123456"}'\'''
echo ""
echo "   # Chat (replace <TOKEN>)"
echo '   curl -N -X POST http://localhost:8080/api/v1/chat/stream \'
echo '     -H "Authorization: Bearer <TOKEN>" \'
echo '     -H "Content-Type: application/json" \'
echo '     -d '\''{"messages":[{"role":"user","content":"Hello!"}],"mode":"economy"}'\'''
