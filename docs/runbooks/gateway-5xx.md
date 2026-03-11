# Gateway 5xx Error Rate - Troubleshooting Runbook

**Severity**: P1 (>10% error rate) / P2 (elevated, <10%)
**Services affected**: `mangala-gateway` (port 8000)
**Alert name**: `GatewayErrorRateHigh`

---

## Symptoms

**Automated alerts:**
- `GatewayErrorRateHigh` fires when 5xx responses exceed threshold
- Circuit breaker state transitions (CLOSED -> OPEN) visible in logs
- `/actuator/health` reports `DOWN` or `DEGRADED`

**User reports:**
- "I can't log in"
- "The app is down"
- API clients receiving HTTP 502, 503, or 504 responses
- Fallback responses from `/fallback/**` endpoints being returned

---

## Detection

**Health dashboard:**
```
GET http://gateway:8000/actuator/health
GET http://gateway:8000/actuator/health/policyLoaderHealth
GET http://gateway:8000/actuator/metrics/http.server.requests
GET http://gateway:8000/actuator/gateway/routes
```

**Key metrics to check:**
```
# Error rate by status code
http.server.requests{status="5xx"}

# Circuit breaker states
resilience4j.circuitbreaker.state{name="authServiceCircuitBreaker"}
resilience4j.circuitbreaker.state{name="defaultCircuitBreaker"}

# Rate limiter rejections
spring.cloud.gateway.requests{outcome="FORWARD_ERROR"}
```

**Log tailing (Docker):**
```bash
docker logs mangala-gateway -f --tail=100

# Filter for errors only
docker logs mangala-gateway 2>&1 | grep -E "ERROR|WARN|CircuitBreaker"
```

**Log tailing (Kubernetes):**
```bash
kubectl logs -n mangala -l app=mangala-gateway --tail=100 -f
kubectl logs -n mangala -l app=mangala-gateway --tail=100 | grep -E "ERROR|WARN"
```

---

## Diagnosis Steps

### Step 1: Identify error type

Check what HTTP status codes are being returned and from which route:

```bash
# In gateway logs, look for patterns like:
# "Response status: 502" -> upstream service down
# "Response status: 503" -> circuit breaker OPEN or rate limit
# "Response status: 504" -> upstream timeout (timelimiter fired)
# "Response status: 500" -> gateway internal error

docker logs mangala-gateway 2>&1 | grep -E "5[0-9]{2}" | tail -50
```

### Step 2: Check circuit breaker states

```
GET http://gateway:8000/actuator/health

# Expected healthy response:
{
  "status": "UP",
  "components": {
    "policyLoaderHealth": {
      "status": "UP",
      "details": {
        "circuitBreakerState": "CLOSED",
        "failureRate": "0.00%"
      }
    }
  }
}
```

If `circuitBreakerState` is `OPEN`, a downstream service is failing. Identify which:
- `authServiceCircuitBreaker` -> see [auth-degradation.md](./auth-degradation.md)
- `walletServiceCircuitBreaker` -> check wallet service health
- `portfolioServiceCircuitBreaker` -> check portfolio service health
- `policyLoaderCircuitBreaker` -> see [policy-reload-failure.md](./policy-reload-failure.md)

Circuit breaker config reference (from `application.yml`):
```yaml
# Trips when 50% of last 10 calls fail (min 5 calls)
# Waits 10s in OPEN state before attempting HALF_OPEN
failureRateThreshold: 50
slidingWindowSize: 10
waitDurationInOpenState: 10s
```

### Step 3: Check upstream service health

Test each downstream service directly:

```bash
# Auth service
curl -s http://auth-service:8080/actuator/health | jq .

# Wallet service
curl -s http://wallet-service:8081/actuator/health | jq .

# Portfolio service
curl -s http://portfolio-service:8182/actuator/health | jq .
```

### Step 4: Check Redis connectivity (rate limiter)

The gateway uses Redis for the `RequestRateLimiter` filter. If Redis is down, rate limiting fails and may cause 5xx responses.

```bash
# Check Redis
redis-cli -h localhost -p 6379 ping
# Expected: PONG

# Check gateway Redis config
# REDIS_HOST env var (default: localhost)
# REDIS_PORT env var (default: 6379)
# Timeout: 2000ms
```

If Redis is down, see [redis-failure.md](./redis-failure.md).

### Step 5: Check policy cache health

```
GET http://gateway:8000/actuator/health/policyLoaderHealth
```

If `status` is `DOWN` or `DEGRADED`, the gateway may be denying all requests due to `POLICY_FAIL_ON_LOAD_ERROR=true` or `POLICY_NO_MATCH_BEHAVIOR=DENY`.

See [policy-reload-failure.md](./policy-reload-failure.md).

### Step 6: Check for rate limiting causing 5xx

The gateway applies rate limiting globally:
```yaml
replenishRate: 10   # tokens/second (env: RATE_LIMIT_REPLENISH)
burstCapacity: 20   # max burst (env: RATE_LIMIT_BURST)
```

If legitimate traffic exceeds this, users get 429 (which may appear as 5xx in some monitoring). Verify:
```bash
docker logs mangala-gateway 2>&1 | grep -i "rate.limit\|429\|too many"
```

---

## Resolution Steps

### Resolution A: Circuit breaker is OPEN - wait for recovery

Circuit breakers automatically transition to HALF_OPEN after `waitDurationInOpenState: 10s`. If the upstream service recovers, the circuit breaker will close automatically.

Monitor recovery:
```bash
watch -n 5 'curl -s http://gateway:8000/actuator/health | jq ".components"'
```

If the upstream is still down after 2 minutes, escalate to the relevant service runbook.

### Resolution B: Restart the gateway (last resort)

Only after confirming the upstream services are healthy and the circuit breakers are still stuck:

```bash
# Docker
docker restart mangala-gateway

# Kubernetes
kubectl rollout restart deployment/mangala-gateway -n mangala
kubectl rollout status deployment/mangala-gateway -n mangala
```

**Warning:** Restarting the gateway triggers a fresh policy load from the auth service. If the auth service is also degraded, gateway startup may fail or be delayed by up to `POLICY_LOAD_TIMEOUT: 30` seconds.

### Resolution C: Redis is down causing rate limiter failure

Temporarily disable rate limiting if Redis cannot be recovered quickly:

```bash
# Set env var and restart
RATE_LIMIT_ENABLED=false docker restart mangala-gateway
```

See [redis-failure.md](./redis-failure.md) for full Redis recovery.

### Resolution D: Config or secrets mismatch

If errors appear right after a deployment:
1. Check `JWT_SECRET` is consistent between gateway and auth service
2. Check `AUTH_SERVICE_URL` points to the correct auth service instance
3. Check CORS `CORS_ALLOWED_ORIGINS` includes the frontend origin

```bash
# Verify env vars in running container
docker inspect mangala-gateway | jq '.[0].Config.Env'
```

---

## Escalation Path

- **L1 -> L2**: Upstream service is down and cause is unknown, or restart does not resolve the issue
- **L2 -> L3**: Infrastructure failure (network partition, cloud provider issue, secrets rotation needed)

---

## Post-Incident Checklist

- [ ] Root cause identified and documented
- [ ] Affected time window confirmed (start time, end time)
- [ ] User impact quantified (# requests failed, # users affected)
- [ ] Circuit breaker state returned to CLOSED
- [ ] `/actuator/health` returns `UP` for all components
- [ ] Monitoring alert resolved / silenced if false positive
- [ ] Post-mortem scheduled if P1 or if incident lasted >30 minutes
- [ ] Runbook updated with any new findings
