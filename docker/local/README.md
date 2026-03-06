# Mangala Local Development Infrastructure

This directory contains Docker Compose configurations for running the complete Mangala backend infrastructure locally.

## Quick Start

```bash
# Start all infrastructure services
./start.sh all

# Or start only databases (no UI tools)
./start.sh db

# Stop all services (keep data)
./stop.sh

# View logs
./logs.sh              # All services
./logs.sh kafka        # Specific service
```

## Available Profiles

| Profile | Services |
|---------|----------|
| `all` | PostgreSQL, MongoDB, Redis, Kafka + all UI tools |
| `infra` | PostgreSQL, MongoDB, Redis, Kafka (no UI) |
| `db` | PostgreSQL, MongoDB, Redis only |
| `postgres` | PostgreSQL only |
| `mongo` | MongoDB only |

## Service Ports

### Core Infrastructure

| Service | Port | Credentials |
|---------|------|-------------|
| PostgreSQL | 5432 | dev / dev123 |
| MongoDB | 27017 | admin / password123 |
| Redis | 6379 | (no auth) |
| Kafka | 9094 | (external listener) |

### Web UIs

| Service | URL | Credentials |
|---------|-----|-------------|
| Kafka UI | http://localhost:8082 | - |
| Mongo Express | http://localhost:8083 | admin / admin |
| Redis Commander | http://localhost:8084 | - |
| pgAdmin | http://localhost:8085 | admin@mangala.local / admin |

## Running Backend Services

After starting infrastructure, run the backend services:

### Option 1: Run from IDE (Recommended for development)

1. **Authentication Service** (port 8080)
   - Run `MangalaAuthenticationApplication.java`
   - Or: `cd mangala-authentication && mvn spring-boot:run`

2. **Gateway Service** (port 8000)
   - Run `MangalaGatewayApplication.java`
   - Or: `cd mangala-gateway && mvn spring-boot:run`

### Option 2: Run with Docker

```bash
# Build and run authentication service
cd mangala-authentication
mvn clean package -DskipTests
docker build -f Dockerfile.simple -t mangala-auth .
docker run -d --name mangala-auth \
  --network mangala-network \
  -p 8080:8080 \
  -e DB_HOST=mangala-postgres \
  -e REDIS_HOST=mangala-redis \
  mangala-auth

# Build and run gateway service
cd mangala-gateway
mvn clean package -DskipTests
docker build -t mangala-gateway .
docker run -d --name mangala-gateway \
  --network mangala-network \
  -p 8000:8000 \
  -e AUTH_SERVICE_URL=http://mangala-auth:8080 \
  -e REDIS_HOST=mangala-redis \
  -e KAFKA_BOOTSTRAP_SERVERS=mangala-kafka:9092 \
  mangala-gateway
```

## Database Initialization

### PostgreSQL

The `init-db/01-init-schemas.sql` script automatically:
- Creates the `auth` schema
- Sets up the `auth_service` user
- Flyway handles table migrations on first app start

### MongoDB

The `init-mongo/01-init-wallet-schema.js` script automatically:
- Creates `wallet_db` database
- Sets up `users` and `transactions` collections with indexes

## Data Management

```bash
# Stop services, keep data
./stop.sh

# Stop and DELETE all data
./stop.sh clean

# Full reset (containers + volumes + images)
./stop.sh reset
```

## Troubleshooting

### Kafka not starting
Wait for the health check to pass (30s startup period):
```bash
docker logs mangala-kafka -f
```

### MongoDB replica set issues
The `mongo-init-replica` container should run once and exit. Check:
```bash
docker logs mangala-mongo-init
```

### PostgreSQL connection refused
Ensure the health check passes:
```bash
docker exec mangala-postgres pg_isready -U dev
```

## Environment Variables

Backend services use these environment variables to connect:

```bash
# PostgreSQL
DB_HOST=localhost  # or mangala-postgres in Docker
DB_PORT=5432
DB_NAME=mangala_dev
DB_USERNAME=dev
DB_PASSWORD=dev123

# Redis
REDIS_HOST=localhost  # or mangala-redis in Docker
REDIS_PORT=6379

# Kafka
KAFKA_BOOTSTRAP_SERVERS=localhost:9094  # or mangala-kafka:9092 in Docker

# MongoDB
MONGO_URI=mongodb://admin:password123@localhost:27017/wallet_db?replicaSet=rs0
```

## Resolve mongodb failed to start
Run this command to generate mongodb.key in the folder docker/local
``
openssl rand -base64 756 > mongodb.key
chmod 400 mongodb.key
``
