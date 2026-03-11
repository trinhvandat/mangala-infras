# Secrets Inventory

All secrets used across Mangala services. Every item in this table must be stored in a secrets manager (e.g. AWS Secrets Manager, HashiCorp Vault) and never committed to source control.

Last updated: 2026-03-06

---

## Legend

| Column | Meaning |
|--------|---------|
| **Secret** | Environment variable name |
| **Service(s)** | Service(s) that consume the secret |
| **Type** | Category of secret |
| **Rotation** | Recommended rotation cadence |
| **Shared** | Whether the same value must be identical across services |
| **Notes** | Generation / validation guidance |

---

## Secrets Table

| Secret | Service(s) | Type | Rotation | Shared | Notes |
|--------|-----------|------|----------|--------|-------|
| `JWT_SECRET` | gateway, authentication | Signing key | 90 days | YES — must match | Base64-encoded 256-bit random bytes. Generate: `openssl rand -base64 32`. Both services must use the identical value or tokens will be rejected. |
| `DB_PASSWORD` | authentication | Database credential | 30 days | No | PostgreSQL password for the `auth` schema user. Use a minimum 24-char random string. |
| `DB_PASSWORD` | notification-service | Database credential | 30 days | No | PostgreSQL password for the `notification` schema user. Separate credential from auth DB. |
| `REDIS_PASSWORD` | gateway | Cache credential | 90 days | No | Redis AUTH password. Leave empty only for local dev with no network exposure. |
| `POLICY_MTLS_KEY_STORE_PASSWORD` | gateway | TLS credential | On cert rotation | No | Password protecting the gateway's PKCS12 key store used for mTLS policy fetching. |
| `POLICY_MTLS_TRUST_STORE_PASSWORD` | gateway | TLS credential | On cert rotation | No | Password protecting the gateway's PKCS12 trust store. |
| `KAFKA_BOOTSTRAP_SERVERS` | gateway, notification-service, price-service | Connection string | N/A | No | Not a secret per se, but treated as sensitive infrastructure config — do not expose publicly. |

---

## Secrets by Service

### mangala-gateway

| Variable | Required in Prod | Source |
|----------|-----------------|--------|
| `JWT_SECRET` | Yes | Secrets manager (shared with authentication) |
| `REDIS_PASSWORD` | Yes | Secrets manager |
| `POLICY_MTLS_KEY_STORE_PASSWORD` | Yes (when mTLS enabled) | Secrets manager |
| `POLICY_MTLS_TRUST_STORE_PASSWORD` | Yes (when mTLS enabled) | Secrets manager |
| `KAFKA_BOOTSTRAP_SERVERS` | Yes | Infrastructure config |

### mangala-authentication

| Variable | Required in Prod | Source |
|----------|-----------------|--------|
| `JWT_SECRET` | Yes | Secrets manager (shared with gateway) |
| `DB_PASSWORD` | Yes | Secrets manager |

### mangala-notification-service

| Variable | Required in Prod | Source |
|----------|-----------------|--------|
| `DB_PASSWORD` | Yes | Secrets manager |
| `REDIS_URL` | Yes | Infrastructure config |
| `KAFKA_BOOTSTRAP_SERVERS` | Yes | Infrastructure config |

### mangala-price-service

| Variable | Required in Prod | Source |
|----------|-----------------|--------|
| `REDIS_URL` | Yes | Infrastructure config |
| `KAFKA_BOOTSTRAP_SERVERS` | Yes | Infrastructure config |

---

## Rotation Procedure

1. Generate the new secret value using the method specified in the Notes column.
2. Update the value in the secrets manager (do not delete the old version yet).
3. For `JWT_SECRET`: deploy both `gateway` and `authentication` atomically — staggered rollout will cause token validation failures.
4. Perform a rolling restart of all affected services.
5. Verify health checks pass and error rates are nominal.
6. Delete the old secret version from the secrets manager after a 24-hour observation window.

---

## mTLS Certificate Inventory

| Certificate | Used By | Issued To | Validity | Rotation |
|-------------|---------|-----------|----------|----------|
| Gateway client cert | gateway (policy fetch) | `gateway-service` | 1 year | 90 days before expiry |
| Auth server cert | authentication (internal API) | `mangala-authentication` | 1 year | 90 days before expiry |

Certificate files are referenced by path via `POLICY_MTLS_KEY_STORE_PATH` and `POLICY_MTLS_TRUST_STORE_PATH`. Store the PKCS12 bundles in a mounted secret volume, not on the container image.
