# Environment Promotion Checklist

Step-by-step checklist for promoting a release through the dev -> staging -> production pipeline.

Complete every item before marking a stage as done. Items marked **(BLOCKER)** must pass before promotion can proceed.

---

## Stage 0 — Pre-Promotion (all stages)

- [ ] Feature branch merged to `main` and CI pipeline is green.
- [ ] All unit and integration tests pass.
- [ ] No `CRITICAL` or `HIGH` findings in the latest dependency scan (OWASP, Snyk, or equivalent).
- [ ] Docker image built and tagged with the git SHA.
- [ ] Image pushed to the container registry.
- [ ] Release notes or changelog entry drafted.

---

## Stage 1 — Dev -> Staging

### Configuration

- [ ] `.env.example` is up to date — all new variables documented with comments.
- [ ] `application-staging.yml` reviewed for accuracy — no dev-only defaults leaking in.
- [ ] All secrets for staging retrieved from secrets manager (not hardcoded in config files).
- [ ] `CORS_ALLOWED_ORIGINS` set to the staging frontend URL only.
- [ ] `JWT_SECRET` is a unique staging value, not reused from dev. **(BLOCKER)**

### Infrastructure

- [ ] Staging database migration dry-run executed (`flyway validate` / `flyway migrate --dry-run`).
- [ ] Redis and Kafka connectivity verified from the staging network.
- [ ] mTLS certificates for gateway <-> authentication internal API are valid and not expired.
- [ ] `INTERNAL_API_MTLS_ENABLED=true` confirmed in staging authentication config.

### Gateway

- [ ] `SECURITY_HEADERS_ENABLED=true` verified.
- [ ] `SECURITY_HSTS_ENABLED=true` verified.
- [ ] Rate limits (`RATE_LIMIT_REPLENISH`, `RATE_LIMIT_BURST`) set to staging values.
- [ ] `POLICY_NO_MATCH_BEHAVIOR=DENY` confirmed.
- [ ] `POLICY_FAIL_ON_LOAD_ERROR=true` confirmed.

### Deployment

- [ ] Kubernetes manifests / Docker Compose updated with the new image tag.
- [ ] Rolling deployment executed — old pods drain before new pods receive traffic.
- [ ] All service health endpoints (`/actuator/health`) return `UP`. **(BLOCKER)**
- [ ] Smoke tests executed against the staging API.
- [ ] Log aggregation shows no `ERROR` or `WARN` spike in the first 10 minutes.

### Sign-off

- [ ] QA sign-off on test coverage of new functionality.
- [ ] Security review completed for any new API endpoints or permission changes.

---

## Stage 2 — Staging -> Production

### Configuration

- [ ] `application-prod.yml` reviewed — all `${VAR}` references have corresponding secrets in prod secrets manager. **(BLOCKER)**
- [ ] `CORS_ALLOWED_ORIGINS` set to production domain(s) only — no `localhost` entries. **(BLOCKER)**
- [ ] `JWT_SECRET` is a unique production value, rotated if older than 90 days. **(BLOCKER)**
- [ ] `DB_PASSWORD` for all services is a strong random string (min 24 chars). **(BLOCKER)**
- [ ] `REDIS_PASSWORD` set (not empty) in production. **(BLOCKER)**

### Database

- [ ] Production database backup taken immediately before migration. **(BLOCKER)**
- [ ] Flyway migration scripts reviewed and approved by a second engineer.
- [ ] `baseline-on-migrate: false` confirmed — no accidental schema baseline in prod.
- [ ] Migration executed against production DB and verified (`flyway info` shows all migrations applied).

### Gateway

- [ ] `SECURITY_HEADERS_ENABLED=true` confirmed.
- [ ] `SECURITY_HSTS_ENABLED=true` confirmed.
- [ ] CSP (`SECURITY_CSP`) reviewed and validated with CSP evaluator.
- [ ] `REFERRER_POLICY` and `PERMISSIONS_POLICY` set to production values.
- [ ] Rate limits (`RATE_LIMIT_REPLENISH=100`, `RATE_LIMIT_BURST=200`) confirmed.
- [ ] `POLICY_MTLS_ENABLED=true` — gateway uses mTLS for policy fetch. **(BLOCKER)**
- [ ] mTLS key/trust store files mounted in production and passwords set. **(BLOCKER)**
- [ ] Audit logging enabled (`AUDIT_ENABLED=true`) and Kafka topic confirmed reachable.

### Authentication

- [ ] `INTERNAL_API_MTLS_ENABLED=true` confirmed. **(BLOCKER)**
- [ ] `PASSKEY_AUTHENTICATOR_USER_VERIFICATION=required` confirmed for production.
- [ ] `springdoc.api-docs.enabled=false` and `swagger-ui.enabled=false` confirmed (no OpenAPI exposure in prod).
- [ ] `RP_ID` and `RP_ORIGIN` match the production domain exactly. **(BLOCKER)**

### Notification Service

- [ ] `NOTIFICATION_RATE_LIMIT` set to production value (e.g. 20/hour).
- [ ] `NOTIFICATION_RETENTION_DAYS` set to production value (e.g. 90).
- [ ] Kafka consumer group ID verified — no collision with staging consumers.
- [ ] `spring.json.trusted.packages` scoped to `org.mangala.notification` (not `*`).

### Price Service

- [ ] `PRICE_SCHEDULER_INTERVAL` set to production value (e.g. 120000 ms = 2 min).
- [ ] CoinGecko API rate limit headroom confirmed for the configured interval and token count.
- [ ] Kafka producer `acks=all` and `retries=5` confirmed.

### Observability

- [ ] Log level `WARN` confirmed for all services in prod.
- [ ] Prometheus metrics endpoint reachable from monitoring stack.
- [ ] Alerting rules active: error rate, circuit breaker open, Redis connectivity, Kafka lag.
- [ ] Distributed tracing (traceId/spanId) flowing into log aggregator.

### Deployment

- [ ] Deployment window communicated to stakeholders.
- [ ] Rollback procedure documented and rehearsed.
- [ ] Rolling deployment executed — zero downtime confirmed.
- [ ] All service health endpoints return `UP` within 2 minutes of deployment. **(BLOCKER)**
- [ ] Synthetic / smoke tests executed against production.
- [ ] Error rates and latency p99 normal for 15 minutes post-deployment. **(BLOCKER)**

### Post-Deployment

- [ ] Old secret versions deleted from secrets manager after 24-hour observation window.
- [ ] Release tagged in git (`git tag v{version}`).
- [ ] Changelog published.
- [ ] Incident runbook updated if new operational procedures were introduced.

---

## Rollback Procedure

If a **(BLOCKER)** check fails post-deployment:

1. Re-deploy the previous image tag immediately (keep it pinned in the registry for 30 days).
2. If a database migration was applied, assess whether it is backward-compatible.
   - If backward-compatible: rollback app only, leave schema in place.
   - If destructive: restore from pre-migration backup. **(This requires a maintenance window.)**
3. Notify stakeholders and open a post-incident review within 24 hours.
