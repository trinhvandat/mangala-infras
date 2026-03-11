# Database Connection Issues - Troubleshooting Runbook

**Severity**: P1 (auth service cannot connect) / P2 (other services degraded)
**Services affected**: `mangala-authentication` (PostgreSQL), `mangala-wallet-service` / `mangala-transaction-history-service` (MongoDB)
**Alert name**: `DBConnectionPoolExhausted`, `PostgreSQLDown`, `MongoDBDown`

---

## Database Overview

| Database | Engine | Port | Container | Default DB | Used By |
|----------|--------|------|-----------|------------|---------|
| PostgreSQL | postgres:15-alpine | 5432 | `mangala-postgres` | `mangala_dev` | Auth service |
| MongoDB | mongo:7.0 | 27017 | `mangala-mongodb` | `wallet_db` | Wallet, Transaction History |

---

## Symptoms

**PostgreSQL:**
- Auth service fails to start: `"Connection refused"` or `"FATAL: database does not exist"`
- Flyway migration errors on auth service startup
- `HikariPool` timeout errors in auth service logs
- pgAdmin unreachable (http://localhost:8085)

**MongoDB:**
- Wallet service or transaction history service return 500 errors
- Mongo Express unreachable (http://localhost:8083)
- `"MongoTimeoutException"` or `"MongoSocketOpenException"` in service logs
- Replica set `rs0` not initialized

---

## Detection

### PostgreSQL

```bash
# Container status
docker ps | grep mangala-postgres
docker inspect mangala-postgres --format='{{.State.Health.Status}}'

# Direct connectivity test
docker exec -it mangala-postgres pg_isready -U dev -d mangala_dev
# Expected: "localhost:5432 - accepting connections"

# Or from host
pg_isready -h localhost -p 5432 -U dev -d mangala_dev

# Auth service logs
docker logs mangala-authentication 2>&1 | grep -iE "connection|pool|hikari|postgres|flyway" | tail -30
```

### MongoDB

```bash
# Container status
docker ps | grep mangala-mongodb
docker inspect mangala-mongodb --format='{{.State.Health.Status}}'

# Ping MongoDB
docker exec -it mangala-mongodb mongosh \
  --username admin --password password123 \
  --eval 'db.runCommand("ping").ok' localhost:27017/test --quiet
# Expected: 1

# Replica set status
docker exec -it mangala-mongodb mongosh \
  --username admin --password password123 \
  --eval 'rs.status().ok' --quiet
# Expected: 1
```

---

## Diagnosis Steps (PostgreSQL)

### Step 1: Check container health and logs

```bash
docker logs mangala-postgres --tail=100

# Common error patterns:
# "FATAL: role 'dev' does not exist"          -> user not created
# "FATAL: database 'mangala_dev' does not exist" -> DB not initialized
# "FATAL: password authentication failed"      -> wrong password
# "LOG: database system is shut down"          -> clean shutdown
# "PANIC: could not write to file"             -> disk full
```

### Step 2: Verify PostgreSQL database and schema

```bash
# Connect and check
docker exec -it mangala-postgres psql -U dev -d mangala_dev

# Inside psql:
\l          -- list databases
\dn         -- list schemas (should include 'auth')
\dt auth.*  -- list tables in auth schema
\q          -- quit
```

Expected schemas after Flyway migration: `auth` schema with user, credential, and policy tables.

Auth service Flyway config (from `application.yml`):
```yaml
spring:
  flyway:
    enabled: true
    schemas: auth
    default-schema: auth
    locations: classpath:/migration
    baseline-on-migrate: true
```

### Step 3: Check Flyway migration state

```bash
# In psql
docker exec -it mangala-postgres psql -U dev -d mangala_dev \
  -c "SELECT version, description, success, installed_on FROM auth.flyway_schema_history ORDER BY installed_rank;"

# A failed migration will show success = false
# Do NOT manually delete failed migration records without L2 guidance
```

### Step 4: Check connection pool exhaustion

The auth service uses HikariCP for connection pooling. Symptoms of exhaustion:
```
HikariPool-1 - Connection is not available, request timed out after 30000ms
```

```bash
docker logs mangala-authentication 2>&1 | grep -iE "hikari|pool|timeout" | tail -20

# Check active connections in PostgreSQL
docker exec -it mangala-postgres psql -U dev -d mangala_dev \
  -c "SELECT count(*), state, wait_event_type, wait_event \
      FROM pg_stat_activity \
      WHERE datname = 'mangala_dev' \
      GROUP BY state, wait_event_type, wait_event;"

# Check max connections
docker exec -it mangala-postgres psql -U dev -d mangala_dev \
  -c "SHOW max_connections;"
```

### Step 5: Verify auth service environment variables

```bash
docker inspect mangala-authentication | jq '.[0].Config.Env | map(select(startswith("DB_")))'

# Expected env vars:
# DB_HOST -> postgres container hostname or IP
# DB_PORT -> 5432
# DB_NAME -> mangala_dev
# DB_SCHEMA -> auth
# DB_USERNAME -> dev
# DB_PASSWORD -> dev123 (in local dev)
```

---

## Diagnosis Steps (MongoDB)

### Step 1: Check container health and logs

```bash
docker logs mangala-mongodb --tail=100

# Common error patterns:
# "ERROR: Insufficient free space"             -> disk full
# "Address already in use"                     -> port conflict
# "Bad file magic number"                      -> data corruption
# "Couldn't connect to local 27017"            -> startup failure
```

### Step 2: Verify replica set initialization

MongoDB requires a replica set (`rs0`) for Change Streams support. The `mongo-init-replica` container initializes it.

```bash
# Check replica set status
docker exec -it mangala-mongodb mongosh \
  --username admin --password password123 \
  --eval 'JSON.stringify(rs.status())' --quiet | jq '.ok, .myState, .members[0].stateStr'

# Expected: ok=1, myState=1 (PRIMARY), stateStr="PRIMARY"

# If replica set is not initialized
docker exec -it mangala-mongodb mongosh \
  --username admin --password password123 \
  --eval 'rs.initiate({_id: "rs0", members: [{_id: 0, host: "mongodb:27017"}]})'
```

### Step 3: Check MongoDB authentication

```bash
# MongoDB credentials (from docker-compose.yml):
# MONGO_INITDB_ROOT_USERNAME: admin
# MONGO_INITDB_ROOT_PASSWORD: password123
# MONGO_INITDB_DATABASE: wallet_db

# Connect and verify
docker exec -it mangala-mongodb mongosh \
  --username admin --password password123 \
  --authenticationDatabase admin \
  --eval 'db.adminCommand({listDatabases: 1}).databases.map(d => d.name)'
```

### Step 4: Check mongodb.key file

MongoDB uses a keyfile for replica set authentication:
```bash
# Verify keyfile exists and has correct permissions
ls -la /Users/dat.trinhvan/Workspaces/Projects/mangala/mangala-infras/docker/local/mongodb.key

# Inside container
docker exec -it mangala-mongodb ls -la /data/configdb/mongodb.key
# Expected: -r-------- (400 permissions)
```

---

## Resolution Steps

### Resolution A: Restart PostgreSQL

```bash
docker restart mangala-postgres

# Wait for healthy state
docker logs mangala-postgres -f --tail=30 &
sleep 15
docker exec -it mangala-postgres pg_isready -U dev -d mangala_dev
```

After PostgreSQL is healthy, restart the auth service:
```bash
docker restart mangala-authentication
docker logs mangala-authentication -f --tail=50
# Wait for: "Started MangalaAuthenticationApplication in X seconds"
```

### Resolution B: Reinitialize PostgreSQL from scratch (data loss - local dev only)

**WARNING: This destroys all data. Only use in local development.**

```bash
docker stop mangala-authentication mangala-postgres
docker rm mangala-postgres
docker volume rm mangala_postgres_data
docker compose -f /Users/dat.trinhvan/Workspaces/Projects/mangala/mangala-infras/docker/local/docker-compose.yml up -d postgres
# Wait for healthy, then start auth service
docker compose -f /Users/dat.trinhvan/Workspaces/Projects/mangala/mangala-infras/docker/local/docker-compose.yml up -d
```

### Resolution C: Fix a failed Flyway migration

**Do not attempt without L2 guidance.**

```bash
# View failed migrations
docker exec -it mangala-postgres psql -U dev -d mangala_dev \
  -c "SELECT * FROM auth.flyway_schema_history WHERE success = false;"

# If the failed script is idempotent, delete the record and retry
# (L2 decision required)
docker exec -it mangala-postgres psql -U dev -d mangala_dev \
  -c "DELETE FROM auth.flyway_schema_history WHERE success = false AND version = 'X';"

docker restart mangala-authentication
```

### Resolution D: Fix connection pool exhaustion

```bash
# Kill idle/long-running connections in PostgreSQL
docker exec -it mangala-postgres psql -U dev -d mangala_dev \
  -c "SELECT pg_terminate_backend(pid) \
      FROM pg_stat_activity \
      WHERE datname = 'mangala_dev' \
        AND state = 'idle' \
        AND query_start < now() - interval '10 minutes';"

# Restart auth service to reset connection pool
docker restart mangala-authentication
```

### Resolution E: Restart MongoDB

```bash
docker restart mangala-mongodb

# Wait for healthy
sleep 15
docker exec -it mangala-mongodb mongosh \
  --username admin --password password123 \
  --eval 'db.runCommand("ping").ok' --quiet

# Re-initialize replica set if needed
docker restart mangala-mongo-init
```

After MongoDB is healthy, restart dependent services:
```bash
docker restart mangala-wallet-service mangala-transaction-history-service
```

### Resolution F: Full infrastructure restart (local dev)

```bash
docker compose -f /Users/dat.trinhvan/Workspaces/Projects/mangala/mangala-infras/docker/local/docker-compose.yml down
docker compose -f /Users/dat.trinhvan/Workspaces/Projects/mangala/mangala-infras/docker/local/docker-compose.yml up -d

# Verify all services healthy
docker compose -f /Users/dat.trinhvan/Workspaces/Projects/mangala/mangala-infras/docker/local/docker-compose.yml ps
```

---

## Schema Verification Checklist

### PostgreSQL (`auth` schema)

```sql
-- Run in psql as dev user
\c mangala_dev
SET search_path TO auth;

-- Verify key tables exist
\dt auth.*

-- Check Flyway history
SELECT version, description, success
FROM auth.flyway_schema_history
ORDER BY installed_rank;

-- Check row counts (sanity check)
SELECT 'users' as tbl, count(*) FROM auth.users
UNION ALL
SELECT 'credentials', count(*) FROM auth.credentials;
```

### MongoDB (`wallet_db`)

```javascript
// Run in mongosh
use wallet_db

// List collections
db.listCollections().toArray().map(c => c.name)

// Replica set health
rs.status().members.map(m => ({name: m.name, state: m.stateStr}))
```

---

## Escalation Path

- **L1 -> L2**: Failed Flyway migration, data corruption suspected, or connection pool exhaustion that does not resolve after restart
- **L2 -> L3**: PostgreSQL failover to replica, MongoDB replica set reconfiguration, or persistent disk errors

---

## Post-Incident Checklist

**PostgreSQL:**
- [ ] `pg_isready` returns `"accepting connections"`
- [ ] `auth` schema exists and all tables present
- [ ] All Flyway migrations show `success = true`
- [ ] Auth service health returns `UP`
- [ ] Login flow works end-to-end

**MongoDB:**
- [ ] `mongosh ping` returns `1`
- [ ] Replica set `rs0` is `PRIMARY` with state `1`
- [ ] `wallet_db` collections are accessible
- [ ] Wallet service health returns `UP`
- [ ] Transaction history service health returns `UP`

**General:**
- [ ] Root cause identified (disk, memory, config, network, etc.)
- [ ] No failed Flyway migrations
- [ ] Connection pool metrics back to normal
- [ ] Monitoring alerts resolved
