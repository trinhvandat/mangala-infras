# =============================================================================
# Mangala Development Makefile
# =============================================================================
# Usage:
#   make help          # Show all commands
#   make dev           # Start everything for development
#   make up            # Start infrastructure only
#   make up-all        # Start infrastructure + services
#   make down          # Stop everything
#   make logs          # View all logs
# =============================================================================

.PHONY: help dev up up-all down clean logs build test web

# Default target
.DEFAULT_GOAL := help

# Variables - Use docker-compose or docker compose depending on system
COMPOSE_CMD := $(shell command -v docker-compose 2>/dev/null || echo "docker compose")
COMPOSE_INFRA := $(COMPOSE_CMD) -f docker-compose.yml
COMPOSE_ALL := $(COMPOSE_CMD) -f docker-compose.yml -f docker-compose.services.yml
PROJECT_ROOT := $(shell cd ../../.. && pwd)

# Colors
CYAN := \033[0;36m
GREEN := \033[0;32m
YELLOW := \033[1;33m
NC := \033[0m

# =============================================================================
# Help
# =============================================================================
help: ## Show this help
	@echo ""
	@echo "$(CYAN)Mangala Development Commands$(NC)"
	@echo "=============================="
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "$(GREEN)%-15s$(NC) %s\n", $$1, $$2}'
	@echo ""

# =============================================================================
# Development Workflows
# =============================================================================
dev: up web ## Start infrastructure + web frontend (recommended for dev)
	@echo "$(GREEN)Development environment ready!$(NC)"
	@echo "  Web: http://localhost:5173"
	@echo "  Gateway: http://localhost:8000 (start manually)"
	@echo "  Auth: http://localhost:8080 (start manually)"

dev-full: up-all ## Start everything in Docker (full stack)
	@echo "$(GREEN)Full stack running in Docker!$(NC)"

# =============================================================================
# Infrastructure
# =============================================================================
up: ## Start infrastructure (PostgreSQL, MongoDB, Redis, Kafka + UIs)
	@echo "$(CYAN)Starting infrastructure...$(NC)"
	$(COMPOSE_INFRA) up -d
	@echo "$(GREEN)Infrastructure started!$(NC)"
	@echo "  PostgreSQL: localhost:5432"
	@echo "  MongoDB:    localhost:27017"
	@echo "  Redis:      localhost:6379"
	@echo "  Kafka:      localhost:9094"

up-all: ## Start infrastructure + all microservices
	@echo "$(CYAN)Starting full stack...$(NC)"
	$(COMPOSE_ALL) up -d --build
	@echo "$(GREEN)Full stack started!$(NC)"

up-full: ## Start everything including StarRocks analytics
	@echo "$(CYAN)Starting full stack with analytics...$(NC)"
	$(COMPOSE_ALL) --profile analytics up -d --build
	@echo "$(GREEN)Full stack with analytics started!$(NC)"

down: ## Stop all services (keep data)
	@echo "$(CYAN)Stopping services...$(NC)"
	$(COMPOSE_ALL) down 2>/dev/null || $(COMPOSE_INFRA) down
	@echo "$(GREEN)Services stopped.$(NC)"

clean: ## Stop all services and remove data
	@echo "$(YELLOW)Stopping and removing all data...$(NC)"
	$(COMPOSE_ALL) down -v --remove-orphans 2>/dev/null || $(COMPOSE_INFRA) down -v --remove-orphans
	@echo "$(GREEN)Cleaned up.$(NC)"

restart: down up ## Restart infrastructure

restart-all: down up-all ## Restart everything

# =============================================================================
# Logs
# =============================================================================
logs: ## View logs from all services
	$(COMPOSE_ALL) logs -f 2>/dev/null || $(COMPOSE_INFRA) logs -f

logs-infra: ## View infrastructure logs only
	$(COMPOSE_INFRA) logs -f postgres mongodb redis kafka

logs-auth: ## View auth service logs
	docker logs -f mangala-auth

logs-gateway: ## View gateway logs
	docker logs -f mangala-gateway

logs-wallet: ## View wallet service logs
	docker logs -f mangala-wallet

logs-es: ## View Elasticsearch logs
	docker logs -f mangala-elasticsearch

logs-starrocks: ## View StarRocks FE logs
	docker logs -f mangala-starrocks-fe

logs-starrocks-be: ## View StarRocks BE logs
	docker logs -f mangala-starrocks-be

logs-txhistory: ## View transaction history service logs
	docker logs -f mangala-txhistory

logs-portfolio: ## View portfolio service logs
	docker logs -f mangala-portfolio

# =============================================================================
# Build
# =============================================================================
build: ## Build all Java services
	@echo "$(CYAN)Building all services...$(NC)"
	@cd $(PROJECT_ROOT)/mangala-common-security && mvn clean install -DskipTests -q
	@cd $(PROJECT_ROOT)/mangala-authentication && mvn clean package -DskipTests -q &
	@cd $(PROJECT_ROOT)/mangala-gateway && mvn clean package -DskipTests -q &
	@wait
	@echo "$(GREEN)Build complete!$(NC)"

build-docker: ## Build Docker images for all services
	@echo "$(CYAN)Building Docker images...$(NC)"
	$(COMPOSE_ALL) build
	@echo "$(GREEN)Docker images built!$(NC)"

# =============================================================================
# Web Frontend
# =============================================================================
web: ## Start web frontend (npm run dev)
	@echo "$(CYAN)Starting web frontend...$(NC)"
	@cd $(PROJECT_ROOT)/mangala-web && npm run dev &
	@echo "$(GREEN)Web frontend starting at http://localhost:5173$(NC)"

web-build: ## Build web frontend for production
	@cd $(PROJECT_ROOT)/mangala-web && npm run build

web-install: ## Install web dependencies
	@cd $(PROJECT_ROOT)/mangala-web && npm install

# =============================================================================
# Testing
# =============================================================================
test: ## Run all tests
	@echo "$(CYAN)Running tests...$(NC)"
	@cd $(PROJECT_ROOT)/mangala-gateway && mvn test -q
	@cd $(PROJECT_ROOT)/mangala-authentication && mvn test -q
	@cd $(PROJECT_ROOT)/mangala-e2e-tests && mvn test -q
	@echo "$(GREEN)Tests passed!$(NC)"

test-e2e: ## Run E2E tests only
	@cd $(PROJECT_ROOT)/mangala-e2e-tests && mvn test

test-auth: ## Run authorization tests
	@cd $(PROJECT_ROOT)/mangala-gateway && mvn test -Dtest=AuthorizationMatrixTest

# =============================================================================
# Elasticsearch & StarRocks Setup
# =============================================================================
setup-es: ## Initialize Elasticsearch with ILM policy
	@echo "$(CYAN)Setting up Elasticsearch...$(NC)"
	@./init-elasticsearch/setup-elasticsearch.sh
	@echo "$(GREEN)Elasticsearch setup complete!$(NC)"

setup-starrocks: ## Initialize StarRocks schema
	@echo "$(CYAN)Setting up StarRocks...$(NC)"
	@mysql -h localhost -P 9030 -u root < init-starrocks/01-create-tables.sql
	@echo "$(GREEN)StarRocks setup complete!$(NC)"

setup-all: setup-es setup-starrocks ## Initialize all analytics infrastructure

# =============================================================================
# Database
# =============================================================================
db-shell: ## Open PostgreSQL shell
	docker exec -it mangala-postgres psql -U dev -d mangala_dev

db-mongo: ## Open MongoDB shell
	docker exec -it mangala-mongodb mongosh

db-redis: ## Open Redis CLI
	docker exec -it mangala-redis redis-cli

# =============================================================================
# Health Checks
# =============================================================================
health: ## Check health of all services
	@echo "$(CYAN)Checking service health...$(NC)"
	@echo ""
	@echo "Infrastructure:"
	@docker exec mangala-postgres pg_isready -U dev -d mangala_dev > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) PostgreSQL" || echo "  $(YELLOW)[DOWN]$(NC) PostgreSQL"
	@docker exec mangala-redis redis-cli ping > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) Redis" || echo "  $(YELLOW)[DOWN]$(NC) Redis"
	@docker exec mangala-mongodb mongosh --eval "db.runCommand('ping')" > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) MongoDB" || echo "  $(YELLOW)[DOWN]$(NC) MongoDB"
	@curl -sf http://localhost:9200/_cluster/health > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) Elasticsearch (9200)" || echo "  $(YELLOW)[DOWN]$(NC) Elasticsearch (9200)"
	@curl -sf http://localhost:8030/api/health > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) StarRocks FE (8030)" || echo "  $(YELLOW)[DOWN]$(NC) StarRocks FE (8030)"
	@echo ""
	@echo "Services:"
	@curl -sf http://localhost:8080/actuator/health > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) Auth Service (8080)" || echo "  $(YELLOW)[DOWN]$(NC) Auth Service (8080)"
	@curl -sf http://localhost:8000/actuator/health > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) Gateway (8000)" || echo "  $(YELLOW)[DOWN]$(NC) Gateway (8000)"
	@curl -sf http://localhost:8182/actuator/health > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) Portfolio Service (8182)" || echo "  $(YELLOW)[DOWN]$(NC) Portfolio Service (8182)"
	@curl -sf http://localhost:8087/actuator/health > /dev/null 2>&1 && echo "  $(GREEN)[OK]$(NC) TX History Service (8087)" || echo "  $(YELLOW)[DOWN]$(NC) TX History Service (8087)"
	@echo ""

status: ## Show status of all containers
	@docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep mangala || echo "No mangala containers running"

# =============================================================================
# Utilities
# =============================================================================
ps: ## Show running containers
	$(COMPOSE_ALL) ps 2>/dev/null || $(COMPOSE_INFRA) ps

shell-auth: ## Open shell in auth service container
	docker exec -it mangala-auth sh

shell-gateway: ## Open shell in gateway container
	docker exec -it mangala-gateway sh

prune: ## Remove unused Docker resources
	docker system prune -f
	docker volume prune -f
