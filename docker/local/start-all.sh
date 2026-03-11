#!/bin/bash
# =============================================================================
# Mangala Full Stack - Start All Services
# =============================================================================
# Usage:
#   ./start-all.sh              # Start infrastructure + services
#   ./start-all.sh infra        # Start infrastructure only
#   ./start-all.sh services     # Start services only (assumes infra running)
#   ./start-all.sh web          # Start web frontend only
#   ./start-all.sh build        # Build all services without starting
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
cd "$SCRIPT_DIR"

# Detect docker-compose command (docker-compose or docker compose)
if command -v docker-compose &> /dev/null; then
    COMPOSE="docker-compose"
else
    COMPOSE="docker compose"
fi

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Parse arguments
MODE="${1:-all}"

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_step() {
    echo -e "${CYAN}>>> $1${NC}"
}

print_success() {
    echo -e "${GREEN}[OK] $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}[WARN] $1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}"
}

# Check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

# Start infrastructure (databases, kafka, monitoring)
start_infra() {
    print_header "Starting Infrastructure"

    print_step "Starting PostgreSQL, MongoDB, Redis, Kafka..."
    $COMPOSE -f docker-compose.yml up -d

    print_step "Waiting for services to be healthy..."
    sleep 10

    # Wait for PostgreSQL
    until docker exec mangala-postgres pg_isready -U dev -d mangala_dev > /dev/null 2>&1; do
        echo "Waiting for PostgreSQL..."
        sleep 2
    done
    print_success "PostgreSQL is ready"

    # Wait for Redis
    until docker exec mangala-redis redis-cli ping > /dev/null 2>&1; do
        echo "Waiting for Redis..."
        sleep 2
    done
    print_success "Redis is ready"

    # Wait for Kafka
    echo "Waiting for Kafka (may take 30s)..."
    sleep 15
    print_success "Infrastructure is ready"
}

# Build all Java services
build_services() {
    print_header "Building Services"

    # Build common-security first (dependency for other services)
    if [ -d "$PROJECT_ROOT/mangala-common-security" ]; then
        print_step "Building mangala-common-security..."
        cd "$PROJECT_ROOT/mangala-common-security"
        mvn clean install -DskipTests -q
        print_success "mangala-common-security built"
    fi

    # Build services in parallel groups
    print_step "Building auth and gateway services..."
    (cd "$PROJECT_ROOT/mangala-authentication" && mvn clean package -DskipTests -q) &
    (cd "$PROJECT_ROOT/mangala-gateway" && mvn clean package -DskipTests -q) &
    wait
    print_success "Auth and Gateway built"

    print_step "Building other services..."
    (cd "$PROJECT_ROOT/mangala-wallet-service" && mvn clean package -DskipTests -q 2>/dev/null) &
    (cd "$PROJECT_ROOT/mangala-portfolio-service" && mvn clean package -DskipTests -q 2>/dev/null) &
    (cd "$PROJECT_ROOT/mangala-price-service" && mvn clean package -DskipTests -q 2>/dev/null) &
    (cd "$PROJECT_ROOT/mangala-notification-service" && mvn clean package -DskipTests -q 2>/dev/null) &
    wait
    print_success "All services built"
}

# Start services with Docker Compose
start_services_docker() {
    print_header "Starting Services (Docker)"

    print_step "Building and starting services..."
    $COMPOSE -f docker-compose.yml -f docker-compose.services.yml up -d --build

    print_step "Waiting for services to start..."
    sleep 30

    print_success "Services are starting up"
}

# Start services locally (for development)
start_services_local() {
    print_header "Starting Services (Local)"

    print_step "Starting Auth Service on port 8080..."
    cd "$PROJECT_ROOT/mangala-authentication"
    mvn spring-boot:run -Dspring-boot.run.profiles=local &
    AUTH_PID=$!

    sleep 20  # Wait for auth to start

    print_step "Starting Gateway on port 8000..."
    cd "$PROJECT_ROOT/mangala-gateway"
    mvn spring-boot:run -Dspring-boot.run.profiles=local &
    GATEWAY_PID=$!

    echo ""
    echo -e "${GREEN}Services started with PIDs:${NC}"
    echo "  Auth Service: $AUTH_PID"
    echo "  Gateway: $GATEWAY_PID"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop all services${NC}"

    # Wait for interrupt
    trap "kill $AUTH_PID $GATEWAY_PID 2>/dev/null; exit" INT TERM
    wait
}

# Start web frontend
start_web() {
    print_header "Starting Web Frontend"

    cd "$PROJECT_ROOT/mangala-web"

    if [ ! -d "node_modules" ]; then
        print_step "Installing dependencies..."
        npm install
    fi

    print_step "Starting Vite dev server on port 5173..."
    npm run dev &
    WEB_PID=$!

    echo ""
    print_success "Web frontend started at http://localhost:5173"
    echo "PID: $WEB_PID"
}

# Print access points
print_access_points() {
    echo ""
    print_header "Access Points"

    echo -e "${CYAN}Application:${NC}"
    echo "  Web Frontend:   http://localhost:3000 (Docker) or http://localhost:5173 (npm)"
    echo "  Gateway API:    http://localhost:8000"
    echo "  Auth Service:   http://localhost:8080"
    echo ""
    echo -e "${CYAN}Infrastructure:${NC}"
    echo "  PostgreSQL:     localhost:5432 (dev/dev123)"
    echo "  MongoDB:        localhost:27017 (admin/password123)"
    echo "  Redis:          localhost:6379"
    echo "  Kafka:          localhost:9094"
    echo ""
    echo -e "${CYAN}Monitoring:${NC}"
    echo "  Grafana:        http://localhost:3001 (admin/admin)"
    echo "  Prometheus:     http://localhost:9090"
    echo "  Alertmanager:   http://localhost:9093"
    echo ""
    echo -e "${CYAN}Admin UIs:${NC}"
    echo "  Kafka UI:       http://localhost:8082"
    echo "  Mongo Express:  http://localhost:8083 (admin/admin)"
    echo "  Redis Commander:http://localhost:8084"
    echo "  pgAdmin:        http://localhost:8085 (admin@google.com/admin)"
    echo ""
}

# Main
check_docker

case "$MODE" in
    "all")
        start_infra
        start_services_docker
        print_access_points
        ;;
    "infra")
        start_infra
        echo ""
        echo -e "${YELLOW}Infrastructure started. Run services manually:${NC}"
        echo "  cd mangala-authentication && mvn spring-boot:run"
        echo "  cd mangala-gateway && mvn spring-boot:run"
        ;;
    "services")
        start_services_docker
        print_access_points
        ;;
    "local")
        start_infra
        start_services_local
        ;;
    "web")
        start_web
        ;;
    "build")
        build_services
        ;;
    *)
        echo "Usage: $0 [all|infra|services|local|web|build]"
        echo ""
        echo "  all       - Start infrastructure + services (Docker)"
        echo "  infra     - Start infrastructure only"
        echo "  services  - Start services only (Docker, assumes infra running)"
        echo "  local     - Start infra + services locally (mvn spring-boot:run)"
        echo "  web       - Start web frontend (npm run dev)"
        echo "  build     - Build all services without starting"
        exit 1
        ;;
esac

echo ""
print_success "Done!"
