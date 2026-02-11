#!/bin/bash
# =============================================================================
# Mangala Local Development Stack - Logs Script
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

SERVICE="${1:-}"

if [ -z "$SERVICE" ]; then
  echo "Following all logs (Ctrl+C to exit)..."
  docker compose -f docker-compose.all.yml logs -f
else
  echo "Following logs for: $SERVICE"
  docker compose -f docker-compose.all.yml logs -f "$SERVICE"
fi
