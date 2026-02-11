#!/bin/bash
# =============================================================================
# Mangala Local Development Stack - Stop Script
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Stopping Mangala Local Stack${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Parse arguments
ACTION="${1:-stop}"

case "$ACTION" in
  "stop")
    echo -e "${YELLOW}Stopping all services (keeping data)...${NC}"
    docker compose -f docker-compose.all.yml down 2>/dev/null || true
    docker compose -f docker-compose.yml down 2>/dev/null || true
    docker compose -f mongo-docker-compose.yml down 2>/dev/null || true
    ;;
  "clean")
    echo -e "${RED}Stopping all services and removing volumes...${NC}"
    read -p "This will DELETE all data. Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      docker compose -f docker-compose.all.yml down -v 2>/dev/null || true
      docker compose -f docker-compose.yml down -v 2>/dev/null || true
      docker compose -f mongo-docker-compose.yml down -v 2>/dev/null || true
      echo -e "${GREEN}All data cleaned.${NC}"
    else
      echo -e "${YELLOW}Aborted.${NC}"
      exit 0
    fi
    ;;
  "reset")
    echo -e "${RED}Full reset - removing containers, volumes, and images...${NC}"
    read -p "This will DELETE everything. Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      docker compose -f docker-compose.all.yml down -v --rmi local 2>/dev/null || true
      echo -e "${GREEN}Full reset complete.${NC}"
    else
      echo -e "${YELLOW}Aborted.${NC}"
      exit 0
    fi
    ;;
  *)
    echo -e "${RED}Unknown action: $ACTION${NC}"
    echo "Usage: $0 [stop|clean|reset]"
    echo "  stop  - Stop containers, keep data (default)"
    echo "  clean - Stop and remove all volumes"
    echo "  reset - Full reset including images"
    exit 1
    ;;
esac

echo ""
echo -e "${GREEN}Done!${NC}"
