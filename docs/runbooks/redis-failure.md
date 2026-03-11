# Redis Failure / Recovery - Troubleshooting Runbook

**Severity**: P2 (rate limiter disabled, elevated risk) / P3 (policy pub/sub degraded)
**Services affected**: `mangala-gateway` (rate limiter, policy pub/sub), `mangala-redis` (port 6379)
**Alert name**: `RedisDown`, `RateLimiterFailing`, `PolicyPubSubDegraded`

---

## Symptoms

**Automated alerts:**
- `RedisDown`: Redis health check (`redis-cli ping`) fails
- `RateLimiterFailing`: Gateway logs show `RequestRateLimiter` errors
- Gateway logs: `"Error acquiring token from Redis"`
- Policy update broadcasts not being received by gateway

**User-visible impact:**
- Rate limiting stops working (users may be over-rate-limited or under-protected)
- Policy cache may become stale if pub/sub channel is down
- In extreme cases, gateway startup fails if Redis is required for initial policy version fetch

---

## Redis Role in Mangala

Redis serves two distinct roles in the gateway:

**1. Rate Limiter Backend** (high criticality)
```yaml
# gateway application.yml
spring:
  data:
    redis:
      host: ${REDIS_HOST:localhost}
      port: ${REDIS_PORT:6379}
      password: ${REDIS_PASSWORD:}
      timeout: 2000ms

spring.cloud.gateway.default-filters:
  - name: RequestRateLimiter
    args:
      redis-rate-limiter:
        replenishRate: ${RATE_LIMIT_REPLENISH:10}   # tokens/second per key
        burstCapacity: ${RATE_LIMIT_BURST:20}        # max burst size
        requestedTokens: 1
      key-resolver: "#{@compositeKeyResolver}"
```

**2. Policy Version & Pub/Sub Channel** (medium criticality)
```yaml
# Policy version stored in Redis key: "policy:version"
# Policy update broadcasts on channel: ${POLICY_REDIS_CHANNEL:policy:updates}
gateway:
  policy:
    redis-channel: ${POLICY_REDIS_CHANNEL:policy:updates}
```

The gateway fetches the policy version from Redis first, falling back to the auth service if Redis is unavailable.

---

## Detection

**Direct Redis check:**
```bash
# Ping Redis
redis-cli -h localhost -p 6379 ping
# Expected: PONG

# Check Redis info
redis-cli -h localhost -p 6379 info server | grep -E "redis_version|uptime|connected"

# Check memory usage
redis-cli -h localhost -p 6379 info memory | grep -E "used_memory_human|maxmemory"

# List all keys (be careful in production - use SCAN instead)
redis-cli -h localhost -p 6379 scan 0 count 100

# Check policy version key
redis-cli -h localhost -p 6379 get "policy:version"
```

**Docker container status:**
```bash
docker ps | grep mangala-redis
docker logs mangala-redis --tail=50
```

**Gateway logs showing Redis errors:**
```bash
docker logs mangala-gateway 2>&1 | grep -iE "redis|lettuce|rate.limit|connection refused" | tail -30
```

**Redis Commander (UI):** http://localhost:8084

---

## Diagnosis Steps

### Step 1: Confirm Redis is unreachable

```bash
# Test TCP connectivity
nc -zv localhost 6379

# Test with redis-cli
redis-cli -h localhost -p 6379 ping

# Docker container status
docker inspect mangala-redis --format='{{.State.Status}} {{.State.Health.Status}}'
```

### Step 2: Check Redis container logs

```bash
docker logs mangala-redis --tail=100

# Common error patterns:
# "MISCONF Redis is configured to save RDB snapshots..."  -> disk full
# "Can't save in background: fork: Cannot allocate memory" -> OOM
# "ERR max number of clients reached" -> connection exhaustion
```

### Step 3: Check Redis memory

Redis is configured with `maxmemory 256mb` and `allkeys-lru` eviction policy (from docker-compose.yml):
```yaml
command: redis-server --appendonly yes --maxmemory 256mb --maxmemory-policy allkeys-lru
```

```bash
redis-cli -h localhost -p 6379 info memory
# Check: used_memory_human vs maxmemory_human
# If used_memory >= maxmemory, LRU eviction is happening - this is expected behavior
# but may cause rate limiter inconsistency if rate limit keys are evicted

# Check eviction stats
redis-cli -h localhost -p 6379 info stats | grep evicted
```

### Step 4: Assess rate limiter impact

When Redis is down, the `RequestRateLimiter` filter cannot function. Depending on the Spring Cloud Gateway version and configuration, this may:
- Cause all requests to fail with 500 (Redis connection error propagated)
- Allow all requests through (fail-open behavior)

Check gateway behavior:
```bash
# Are requests getting through?
curl -s -o /dev/null -w "%{http_code}" http://gateway:8000/actuator/health

# Check rate limiter errors in gateway logs
docker logs mangala-gateway 2>&1 | grep -E "RateLimiter|429|RATE_LIMIT" | tail -20
```

### Step 5: Assess policy pub/sub impact

The policy update channel (`policy:updates`) is used for real-time policy cache invalidation. If Redis pub/sub is down:
- New policy changes from auth service will NOT be pushed to gateway in real-time
- The fallback: `PolicyVersionChecker` polls every 60 seconds (configured via `POLICY_VERSION_CHECK_INTERVAL:60`)
- Policy version is fetched from auth service directly when Redis is unavailable

```bash
# Check if policy cache is still healthy
curl -s http://gateway:8000/actuator/health | jq '.components.policyLoaderHealth'

# Check gateway logs for pub/sub errors
docker logs mangala-gateway 2>&1 | grep -iE "pub.sub|subscribe|policy:updates|channel" | tail -20
```

---

## Resolution Steps

### Resolution A: Restart Redis container

```bash
docker restart mangala-redis

# Watch for healthy state
docker logs mangala-redis -f --tail=20

# Verify Redis is up
sleep 5 && redis-cli -h localhost -p 6379 ping
```

After Redis recovers:
- Rate limiter resumes automatically (Lettuce client reconnects)
- Policy pub/sub subscription resumes automatically
- Policy version key TTL: 5 minutes (will be repopulated on next version check)

### Resolution B: Redis data is corrupt or AOF is broken

If Redis fails to start due to AOF (Append Only File) corruption:
```bash
docker logs mangala-redis 2>&1 | grep -i "aof\|corrupt\|bad file"

# Fix corrupted AOF
docker exec -it mangala-redis redis-check-aof --fix /data/appendonly.aof

# Then restart
docker restart mangala-redis
```

**Warning:** Fixing AOF may lose the most recent writes (rate limit counters, policy version). This is acceptable as rate limit counters will reset and policy version will be re-fetched from the auth service.

### Resolution C: Redis out of memory

If Redis is hitting `maxmemory` limit and critical keys are being evicted:

```bash
# Flush only rate limit keys (pattern: request_rate_limiter.*)
redis-cli -h localhost -p 6379 --scan --pattern "request_rate_limiter.*" | xargs redis-cli del

# Or increase maxmemory (requires restart or CONFIG SET)
redis-cli -h localhost -p 6379 config set maxmemory 512mb
```

### Resolution D: Temporarily disable rate limiting

If Redis cannot be recovered quickly and requests are failing due to rate limiter errors:

```bash
# Set RATE_LIMIT_ENABLED=false and restart gateway
# Update environment variable and restart
docker stop mangala-gateway
# Edit docker-compose or env file to set RATE_LIMIT_ENABLED=false
docker start mangala-gateway
```

**Note:** Disabling rate limiting exposes the API to potential abuse. Re-enable as soon as Redis is recovered. Monitor request volume manually during this period.

### Resolution E: Repopulate policy version key after Redis restart

After Redis restarts, the `policy:version` key will be empty until the next policy check cycle (up to 60 seconds). Force an immediate policy reload:

```bash
# Trigger gateway to re-fetch policy from auth service
# The PolicyVersionChecker will do this automatically within 60s
# Or restart the gateway to trigger immediate reload at startup
docker restart mangala-gateway
```

---

## Recovery Verification

```bash
# 1. Redis is up and responding
redis-cli -h localhost -p 6379 ping
# Expected: PONG

# 2. Policy version key exists
redis-cli -h localhost -p 6379 get "policy:version"
# Expected: a numeric value (e.g., "1234567890")

# 3. Gateway health is UP
curl -s http://gateway:8000/actuator/health | jq .status
# Expected: "UP"

# 4. Policy cache is healthy
curl -s http://gateway:8000/actuator/health | jq '.components.policyLoaderHealth.status'
# Expected: "UP"

# 5. Rate limiter is working (check gateway logs for no Redis errors)
docker logs mangala-gateway 2>&1 | grep -iE "redis|rate.limit" | tail -10
```

---

## Escalation Path

- **L1 -> L2**: Redis cannot start due to data corruption, or memory issues persist after flush
- **L2 -> L3**: Redis cluster failover needed, persistent disk issues, or infrastructure-level Redis replacement required

---

## Post-Incident Checklist

- [ ] Redis container is healthy (`docker inspect mangala-redis --format='{{.State.Health.Status}}'`)
- [ ] `redis-cli ping` returns `PONG`
- [ ] `policy:version` key exists in Redis
- [ ] Gateway rate limiter is functioning (no Redis errors in logs)
- [ ] Policy pub/sub subscription active (gateway received at least one version check)
- [ ] Gateway health endpoint returns `UP`
- [ ] Rate limiting re-enabled if it was disabled during incident
- [ ] Root cause documented (OOM, corruption, container crash, etc.)
