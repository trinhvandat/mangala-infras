# Policy Reload Failure - Troubleshooting Runbook

**Severity**: P2 (gateway denying all requests) / P3 (stale rules, elevated risk)
**Services affected**: `mangala-gateway` (port 8000), `mangala-authentication` (port 8080)
**Alert name**: `PolicyCacheUnhealthy`, `PolicyLoadFailed`, `PolicyCacheStale`

---

## Symptoms

**Automated alerts:**
- `PolicyCacheUnhealthy`: `/actuator/health/policyLoaderHealth` returns `DOWN` or `DEGRADED`
- `PolicyLoadFailed`: Gateway logs show repeated policy load failures at startup
- `PolicyCacheStale`: Policy cache last updated more than 5 minutes ago

**User-visible impact:**
- If `POLICY_NO_MATCH_BEHAVIOR=DENY` (default): all authenticated requests return 403 Forbidden
- If `POLICY_FAIL_ON_LOAD_ERROR=true` (default): gateway fails to start entirely
- Users see "Access Denied" errors for operations that should be permitted
- New permission changes are not taking effect (stale policy rules)

---

## Architecture Overview

The gateway uses an ABAC (Attribute-Based Access Control) policy system:

```
[Auth Service] --policy API--> [PolicyLoader] --loads--> [PolicyCache]
                                     |
                              [CircuitBreaker: policyLoaderCircuitBreaker]
                                     |
                              [PolicyVersionChecker] (polls every 60s)
                                     |
                              [PolicyUpdateListener] (Redis pub/sub: policy:updates)
```

**Key config values** (from `gateway/application.yml`):
```yaml
gateway:
  policy:
    auth-service-url: ${AUTH_SERVICE_URL:http://localhost:8080}
    initial-load-timeout-seconds: ${POLICY_LOAD_TIMEOUT:30}
    version-check-initial-delay-seconds: ${POLICY_VERSION_CHECK_INITIAL_DELAY:15}
    version-check-interval-seconds: ${POLICY_VERSION_CHECK_INTERVAL:60}
    fail-on-load-error: ${POLICY_FAIL_ON_LOAD_ERROR:true}
    redis-channel: ${POLICY_REDIS_CHANNEL:policy:updates}
    use-kafka: ${POLICY_USE_KAFKA:false}
    no-match-behavior: ${POLICY_NO_MATCH_BEHAVIOR:DENY}
    include-in-health-check: ${POLICY_HEALTH_CHECK:true}

resilience4j:
  circuitbreaker:
    instances:
      policyLoaderCircuitBreaker:
        slidingWindowSize: 5
        minimumNumberOfCalls: 3
        failureRateThreshold: 60      # trips at 60% failure rate
        waitDurationInOpenState: 30s  # waits 30s before HALF_OPEN
        permittedNumberOfCallsInHalfOpenState: 2
```

---

## Detection

**Health check:**
```bash
curl -s http://gateway:8000/actuator/health | jq '.components.policyLoaderHealth'

# Healthy:
# {
#   "status": "UP",
#   "details": {
#     "circuitBreakerState": "CLOSED",
#     "failureRate": "0.00%",
#     "failedCalls": 0
#   }
# }

# Degraded (circuit breaker HALF_OPEN):
# { "status": "DEGRADED", "details": { "circuitBreakerState": "HALF_OPEN" } }

# Unhealthy (circuit breaker OPEN):
# { "status": "DOWN", "details": { "circuitBreakerState": "OPEN", "failureRate": "80.00%" } }
```

**Gateway logs - policy-related:**
```bash
docker logs mangala-gateway 2>&1 | grep -iE "policy|PolicyLoader|PolicyVersionChecker|circuit.breaker" | tail -50

# Key log lines to look for:
# "Loading policies from Auth Service: http://..."   -> policy load attempt
# "Loaded N policies, version: X"                    -> successful load
# "Policy load blocked by circuit breaker"            -> CB is OPEN
# "Policy load failed: ..."                           -> failed with reason
# "Policy cache may be stale (last load: Xms ago)"   -> staleness warning
# "Policy cache unhealthy, attempting reload..."      -> auto-recovery attempt
# "Retrying policy load, attempt: X"                  -> retry in progress
```

---

## Diagnosis Steps

### Step 1: Identify the failure mode

```bash
# Check circuit breaker state
curl -s http://gateway:8000/actuator/health | jq '.components.policyLoaderHealth.details.circuitBreakerState'
# CLOSED = healthy
# HALF_OPEN = recovering
# OPEN = tripped, auth service calls blocked
```

```bash
# Check if policy cache has any rules loaded
# (visible in logs at startup)
docker logs mangala-gateway 2>&1 | grep "Loaded .* policies" | tail -5

# Check for startup failure
docker logs mangala-gateway 2>&1 | grep -E "Initial policy load|fail-on-load|POLICY_FAIL" | tail -10
```

### Step 2: Check the auth service internal policy API

The gateway calls this endpoint to load policies:
```bash
# Fetch all policies
curl -s http://auth-service:8080/v1/internal/policies | jq '. | length'
# Expected: a number > 0 (number of policy rules)

# Fetch policy version
curl -s http://auth-service:8080/v1/internal/policies/version | jq .
# Expected: {"version": 1234567890}
```

If these return errors, the auth service is the root cause. See [auth-degradation.md](./auth-degradation.md).

### Step 3: Check mTLS configuration (if enabled)

```yaml
# gateway application.yml
gateway:
  policy:
    mtls:
      enabled: ${POLICY_MTLS_ENABLED:false}   # default: disabled
```

If `POLICY_MTLS_ENABLED=true`, the gateway uses mutual TLS to call the auth service internal API. Certificate issues will cause policy load to fail.

```bash
# Check mTLS config
docker inspect mangala-gateway | jq '.[0].Config.Env | map(select(startswith("POLICY_MTLS")))'

# If mTLS is enabled, verify certificates
openssl verify -CAfile trust-store.pem key-store.pem
```

### Step 4: Check Redis pub/sub channel

```bash
# Subscribe to policy updates channel to verify it works
redis-cli -h localhost -p 6379 subscribe "policy:updates"
# (This will block - Ctrl+C to exit)

# Check if policy version is in Redis
redis-cli -h localhost -p 6379 get "policy:version"
```

If Redis is down, see [redis-failure.md](./redis-failure.md). The gateway will fall back to polling the auth service directly.

### Step 5: Check for stale cache

The `PolicyVersionChecker` logs a warning if the cache has not been updated in 5 minutes:
```
"Policy cache may be stale (last load: Xms ago). Checking version..."
```

```bash
docker logs mangala-gateway 2>&1 | grep -i "stale\|last load\|version check" | tail -20
```

Stale cache with correct rules is not an emergency but indicates the pub/sub or polling mechanism is broken. Investigate why version checks are failing.

### Step 6: Check circuit breaker metrics

```bash
curl -s http://gateway:8000/actuator/health | jq '.components.policyLoaderHealth.details'

# Key fields:
# failureRate: % of calls that failed in sliding window (trips at 60%)
# failedCalls: number of failed calls
# notPermittedCalls: number blocked by open circuit breaker
# bufferedCalls: total calls in sliding window
```

The `policyLoaderCircuitBreaker` trips when 60% of the last 5 calls fail (min 3 calls required). It then waits 30 seconds before allowing test calls through.

---

## Resolution Steps

### Resolution A: Wait for automatic recovery

If the auth service was temporarily down and has recovered:
1. The circuit breaker will transition to `HALF_OPEN` after 30 seconds
2. It will allow 2 test calls through (`permittedNumberOfCallsInHalfOpenState: 2`)
3. If those succeed, it returns to `CLOSED` and the next `PolicyVersionChecker` run (within 60s) will reload policies

Monitor:
```bash
watch -n 10 'curl -s http://gateway:8000/actuator/health | jq ".components.policyLoaderHealth"'
```

### Resolution B: Trigger manual policy reload

The gateway exposes an internal endpoint to force a policy reload (if configured):

```bash
# Force policy reload via actuator (if endpoint exposed)
curl -X POST http://gateway:8000/actuator/gateway/refresh

# Or restart the gateway to trigger the ApplicationRunner-based reload
docker restart mangala-gateway
```

After restart, watch for:
```
"Starting policy loader..."
"Loading policies from Auth Service: http://..."
"Loaded N policies, version: X"
"Initial policy load completed successfully"
```

If the load fails at startup and `POLICY_FAIL_ON_LOAD_ERROR=true`, the gateway will exit. Fix the auth service first, then restart the gateway.

### Resolution C: Disable fail-on-load-error for emergency start

If the gateway cannot start because the auth service is down and `POLICY_FAIL_ON_LOAD_ERROR=true`:

```bash
# Temporarily disable fail-on-load to start gateway with empty/cached policy
# WARNING: With POLICY_NO_MATCH_BEHAVIOR=DENY, all requests will be denied
# Change to ALLOW only in extreme emergency
POLICY_FAIL_ON_LOAD_ERROR=false docker restart mangala-gateway
```

After the auth service recovers, `PolicyVersionChecker` will reload policies automatically within 60 seconds.

### Resolution D: Change no-match behavior for emergency access

**DANGER: Use only in P1 emergencies with explicit L3 approval.**

If `POLICY_NO_MATCH_BEHAVIOR=DENY` is causing all requests to fail and policy cannot be loaded:

```bash
# Allows all unmatched requests through (bypasses ABAC)
POLICY_NO_MATCH_BEHAVIOR=ALLOW docker restart mangala-gateway
```

Revert to `DENY` as soon as the policy cache is restored.

### Resolution E: Auth service internal API returning wrong data

If the policy API returns empty or malformed data:

```bash
# Check what auth service is returning
curl -s http://auth-service:8080/v1/internal/policies | jq '. | length'

# If 0 policies returned, check auth service DB for policy rules
docker exec -it mangala-postgres psql -U dev -d mangala_dev \
  -c "SELECT count(*) FROM auth.api_permissions;"
```

If DB is empty, a data migration may have failed. Escalate to L2.

---

## Escalation Path

- **L1 -> L2**: Circuit breaker stays OPEN after auth service recovery, or policy DB is empty
- **L2 -> L3**: mTLS certificate rotation needed, or emergency `no-match-behavior=ALLOW` required

---

## Post-Incident Checklist

- [ ] `policyLoaderHealth` status is `UP`
- [ ] Circuit breaker state is `CLOSED`
- [ ] Policy count is non-zero: `Loaded N policies, version: X` in logs
- [ ] `POLICY_NO_MATCH_BEHAVIOR` restored to `DENY` if it was changed
- [ ] `POLICY_FAIL_ON_LOAD_ERROR` restored to `true` if it was changed
- [ ] Redis pub/sub channel `policy:updates` is active
- [ ] `PolicyVersionChecker` is running (check logs for periodic `"Checking version..."` messages)
- [ ] Test a protected endpoint to confirm policies are enforced correctly
- [ ] Document what caused the policy load failure
