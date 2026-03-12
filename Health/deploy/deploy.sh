#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

echo "=== Building Next.js ==="
PATH="/opt/homebrew/opt/node@22/bin:$PATH" npm run build

echo "=== Building Docker image ==="
docker build -t vital-command:latest .

echo "=== Exporting image ==="
docker save vital-command:latest | gzip > deploy/vital-command.tar.gz

echo ""
echo "✅ Image saved to deploy/vital-command.tar.gz"
echo ""
echo "Transfer to target machine and run:"
echo "  scp deploy/vital-command.tar.gz user@target:/opt/"
echo ""
echo "On target machine:"
echo "  cd /opt"
echo "  docker load < vital-command.tar.gz"
echo "  # Create .env file with your settings first, then:"
echo "  docker run -d --restart=always -p 3000:3000 \\"
echo "    -v /opt/vital-command/data:/app/data \\"
echo "    --env-file /opt/vital-command/.env \\"
echo "    --name vital-command vital-command:latest"
