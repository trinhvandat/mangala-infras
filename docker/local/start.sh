#!/bin/bash
# =============================================================================
# Mangala Local Development Stack - Start Script
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
echo -e "${BLUE}  Mangala Local Development Stack${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Parse arguments
PROFILE="${1:-all}"

case "$PROFILE" in
  "all")
    echo -e "${YELLOW}Starting ALL services...${NC}"
    docker compose -f docker-compose.all.yml up -d
    ;;
  "infra")
    echo -e "${YELLOW}Starting infrastructure only (no UI tools)...${NC}"
    docker compose -f docker-compose.all.yml up -d postgres mongodb mongo-init-replica redis kafka
    ;;
  "db")
    echo -e "${YELLOW}Starting databases only...${NC}"
    docker compose -f docker-compose.all.yml up -d postgres mongodb mongo-init-replica redis
    ;;
  "postgres")
    echo -e "${YELLOW}Starting PostgreSQL only...${NC}"
    docker compose -f docker-compose.yml up -d
    ;;
  "mongo")
    echo -e "${YELLOW}Starting MongoDB only...${NC}"
    docker compose -f mongo-docker-compose.yml up -d
    ;;
  *)
    echo -e "${RED}Unknown profile: $PROFILE${NC}"
    echo "Usage: $0 [all|infra|db|postgres|mongo]"
    exit 1
    ;;
esac

echo ""
echo -e "${GREEN}Waiting for services to be healthy...${NC}"
sleep 5

# Check service status
echo ""
echo -e "${BLUE}Service Status:${NC}"
docker compose -f docker-compose.all.yml ps 2>/dev/null || docker compose -f docker-compose.yml ps

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Services are starting up!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo -e "${BLUE}Access Points:${NC}"
echo "  PostgreSQL:     localhost:5432 (dev/dev123)"
echo "  MongoDB:        localhost:27017 (admin/password123)"
echo "  Redis:          localhost:6379"
echo "  Kafka:          localhost:9094 (external)"
echo ""
echo -e "${BLUE}Web UIs:${NC}"
echo "  Kafka UI:       http://localhost:8082"
echo "  Mongo Express:  http://localhost:8083 (admin/admin)"
echo "  Redis Commander:http://localhost:8084"
echo "  pgAdmin:        http://localhost:8085 (admin@mangala.local/admin)"
echo ""
echo -e "${YELLOW}Note: Backend services (auth, gateway) should be started separately.${NC}"
echo ""
