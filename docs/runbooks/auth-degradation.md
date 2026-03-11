# Auth Service Degradation - Troubleshooting Runbook

**Severity**: P1 (all logins failing) / P2 (passkey failures, partial login issues)
**Services affected**: `mangala-authentication` (port 8080), `mangala-gateway` (port 8000)
**Alert name**: `AuthServiceDegraded`, `LoginFailureRateHigh`

---

## Symptoms

**Automated alerts:**
- `AuthServiceDegraded`: `/actuator/health` on auth service returns `DOWN`
- `LoginFailureRateHigh`: elevated HTTP 5xx on `POST /api/v1/authenticate/**`
- `authServiceCircuitBreaker` in gateway transitions to `OPEN`

**User reports:**
- "I can't log in with my passkey"
- "Login button does nothing / spins forever"
- "I get a 'Service Unavailable' error when trying to register"
- JWT token refresh fails, users are logged out unexpectedly

---

## Detection

**Auth service health:**
```bash
curl -s http://auth-service:8080/actuator/health | jq .
```

**Gateway circuit breaker state for auth:**
```bash
curl -s http://gateway:8000/actuator/health | jq '.components'

# Check auth circuit breaker specifically in gateway logs
docker logs mangala-gateway 2>&1 | grep "authServiceCircuitBreaker"
```

**Auth service logs:**
```bash
docker logs mangala-authentication -f --tail=100

# Filter for errors
docker logs mangala-authentication 2>&1 | grep -E "ERROR|WARN|Exception" | tail -50
```

**Affected endpoints:**
```
POST /api/v1/register/**           -> Registration (passkey initiation)
POST /api/v1/authenticate/**       -> Authentication (passkey verification)
POST /api/v1/auth/refresh          -> JWT token refresh
GET  /api/v1/auth/**               -> Auth status / internal policy API
```

---

## Diagnosis Steps

### Step 1: Check auth service health endpoint

```bash
curl -s http://auth-service:8080/actuator/health | jq .
```

If the response is `DOWN`, proceed to Step 2. If `UP` but users still can't log in, jump to Step 4 (JWT secret check).

### Step 2: Check database connectivity (PostgreSQL)

The auth service requires PostgreSQL for all user data, passkey credentials, and JWT refresh tokens.

```bash
# Check PostgreSQL container
docker ps | grep mangala-postgres
docker logs mangala-postgres --tail=50

# Test PostgreSQL connectivity directly
docker exec -it mangala-postgres psql -U dev -d mangala_dev -c "SELECT 1;"

# Or from host if psql is available
psql -h localhost -p 5432 -U dev -d mangala_dev -c "\dn"
# Expected: should show 'auth' schema listed
```

**Auth service DB config** (from `application.yml`):
```yaml
datasource:
  url: jdbc:postgresql://${DB_HOST}:${DB_PORT}/${DB_NAME}?currentSchema=${DB_SCHEMA}
  # DB_HOST, DB_PORT, DB_NAME, DB_SCHEMA, DB_USERNAME, DB_PASSWORD are all env vars
```

Check for connection pool exhaustion in auth service logs:
```bash
docker logs mangala-authentication 2>&1 | grep -iE "connection|pool|timeout|hikari" | tail -30
```

If PostgreSQL is down, see [database-connection.md](./database-connection.md).

### Step 3: Check Flyway migration status

The auth service runs Flyway migrations on startup (`baseline-on-migrate: true`). A failed migration will prevent startup.

```bash
# Look for Flyway errors in startup logs
docker logs mangala-authentication 2>&1 | grep -iE "flyway|migration|schema" | tail -30

# Expected successful output:
# "Successfully applied N migrations to schema 'auth'"
# "Flyway Community Edition ... has successfully finished"

# Schema check in DB
docker exec -it mangala-postgres psql -U dev -d mangala_dev -c "\dt auth.*"
```

If migration failed, do NOT run the service again without understanding the failure. Escalate to L2.

### Step 4: Check JWT secret consistency

The gateway validates JWT tokens issued by the auth service. Both must share the same `JWT_SECRET`.

**Auth service** (from `application.yml`):
```yaml
application:
  authentication:
    jwt:
      secret: ${JWT_SECRET:your-256-bit-secret-key-for-jwt-signing-replace-in-production}
      issuer: ${JWT_ISSUER:mangala}
      access-token-expiration-seconds: ${JWT_ACCESS_EXPIRATION_SECONDS:900}   # 15 minutes
      refresh-token-expiration-seconds: ${JWT_REFRESH_EXPIRATION_SECONDS:604800}  # 7 days
      access-token-audience: ${JWT_ACCESS_AUDIENCE:mangala-gateway}
      refresh-token-audience: ${JWT_REFRESH_AUDIENCE:mangala-auth-refresh}
```

**Gateway** (from `application.yml`):
```yaml
gateway:
  jwt:
    secret: ${JWT_SECRET:your-256-bit-secret-key-for-jwt-signing-replace-in-production}
    issuer: ${JWT_ISSUER:mangala}
```

Verify both services use the same `JWT_SECRET` env var value:
```bash
# Check auth service
docker inspect mangala-authentication | jq '.[0].Config.Env | map(select(startswith("JWT_")))'

# Check gateway
docker inspect mangala-gateway | jq '.[0].Config.Env | map(select(startswith("JWT_")))'
```

If secrets differ, update the misconfigured service env var and restart it. Do not change the auth service secret without also updating the gateway simultaneously, as all existing tokens will be invalidated.

### Step 5: Check passkey (WebAuthn) configuration

Passkey failures are often caused by RP (Relying Party) configuration mismatches between what the client sends and what the server expects.

**Auth service passkey config** (from `application.yml`):
```yaml
application:
  authentication:
    passkey:
      rp:
        id: ${RP_ID}          # Must match the domain (e.g., "mangala.io")
        name: ${RP_NAME}      # Display name (e.g., "Mangala Wallet")
        origin: ${RP_ORIGIN}  # Must match the exact origin (e.g., "https://mangala.io")
      timeout: ${PASSKEY_TIMEOUT}
      authenticator:
        attachment: ${PASSKEY_AUTHENTICATOR_ATTACHMENT:platform}
        resident-key: ${PASSKEY_AUTHENTICATOR_RESIDENT_KEY:true}
        user-verification: ${PASSKEY_AUTHENTICATOR_USER_VERIFICATION:preferred}
```

Common passkey failure causes:
- `RP_ORIGIN` does not match the actual request origin (e.g., HTTP vs HTTPS, missing port)
- `RP_ID` does not match the effective domain of the origin
- Client browser does not support the required authenticator `attachment` type

Check for passkey errors:
```bash
docker logs mangala-authentication 2>&1 | grep -iE "passkey|webauthn|fido|rp\.|origin|attestation" | tail -30
```

### Step 6: Check the internal policy API (used by gateway)

The gateway calls the auth service internal API to load ABAC policies. If this endpoint is broken, the gateway policy cache may fail to refresh.

```bash
# Internal policy API - called by gateway at startup and every 60s
curl -s http://auth-service:8080/v1/internal/policies | jq . | head -20

# Policy version endpoint
curl -s http://auth-service:8080/v1/internal/policies/version | jq .
```

If these return errors, the gateway policy cache will degrade. See [policy-reload-failure.md](./policy-reload-failure.md).

---

## Resolution Steps

### Resolution A: Auth service is down - restart

```bash
# Docker
docker restart mangala-authentication

# Watch startup logs
docker logs mangala-authentication -f --tail=50
```

Wait for: `"Started MangalaAuthenticationApplication in X seconds"`

After restart, verify:
```bash
curl -s http://auth-service:8080/actuator/health | jq .
```

### Resolution B: PostgreSQL is down or unreachable

See [database-connection.md](./database-connection.md) for full diagnosis and recovery.

Quick check:
```bash
docker restart mangala-postgres
# Wait ~30s then
docker restart mangala-authentication
```

### Resolution C: JWT secret mismatch after rotation

If `JWT_SECRET` was rotated in the auth service but not the gateway (or vice versa):

1. All currently-valid tokens will be rejected by the gateway until secrets are aligned
2. Update the env var in the misconfigured service
3. Restart the misconfigured service
4. Users will need to log in again to get new tokens signed with the new secret

**Note:** Rotating `JWT_SECRET` invalidates ALL existing sessions. Coordinate with stakeholders before rotating in production.

### Resolution D: Passkey RP origin mismatch

If the frontend changed domains or the service moved:
1. Update `RP_ORIGIN` and/or `RP_ID` environment variables to match the new origin
2. Restart the auth service
3. Users with previously registered passkeys may need to re-register if the `RP_ID` changed

### Resolution E: Reset the authServiceCircuitBreaker in gateway

After auth service recovers, the gateway circuit breaker will automatically attempt HALF_OPEN after 10 seconds. If it is stuck:

```bash
# Gateway logs will show transition:
# "CircuitBreaker 'authServiceCircuitBreaker' changed state from OPEN to HALF_OPEN"
# "CircuitBreaker 'authServiceCircuitBreaker' changed state from HALF_OPEN to CLOSED"

# If stuck, restart gateway (will reset circuit breaker state)
docker restart mangala-gateway
```

---

## Escalation Path

- **L1 -> L2**: Database is inaccessible, Flyway migration failed, or passkey configuration is unclear
- **L2 -> L3**: PostgreSQL failover needed, secrets rotation required, or persistent auth loop affecting all users

---

## Post-Incident Checklist

- [ ] Auth service health returns `UP`
- [ ] `authServiceCircuitBreaker` in gateway is back to `CLOSED`
- [ ] Test login flow end-to-end (passkey registration + authentication)
- [ ] Test JWT refresh: `POST /api/v1/auth/refresh`
- [ ] Test internal policy API: `GET http://auth-service:8080/v1/internal/policies`
- [ ] Confirm no Flyway migration is in a failed state
- [ ] Document root cause and resolution
- [ ] If JWT secret was rotated, confirm user communication was sent
