# Mangala On-Call Runbooks

This directory contains operational runbooks for diagnosing and resolving incidents in the Mangala platform.

---

## Runbook Index

| Runbook | Description | Typical Alert |
|---------|-------------|---------------|
| [gateway-5xx.md](./gateway-5xx.md) | Gateway returning 5xx errors to clients | `GatewayErrorRateHigh` |
| [auth-degradation.md](./auth-degradation.md) | Auth service login / passkey failures | `AuthServiceDegraded` |
| [redis-failure.md](./redis-failure.md) | Redis unavailable or data loss | `RedisDown`, `RateLimiterFailing` |
| [policy-reload-failure.md](./policy-reload-failure.md) | Policy cache stale or reload failing | `PolicyCacheUnhealthy` |
| [database-connection.md](./database-connection.md) | PostgreSQL or MongoDB connection issues | `DBConnectionPoolExhausted` |

---

## Severity Classification

| Severity | Label | Definition | Response SLA |
|----------|-------|------------|--------------|
| Critical | **P1** | Full service outage. All users cannot authenticate or transact. | 15 minutes |
| High     | **P2** | Partial outage. A significant subset of users is impacted. | 30 minutes |
| Medium   | **P3** | Degraded performance or non-critical feature broken. | 2 hours |
| Low      | **P4** | Minor issue, no user-visible impact yet. | Next business day |

### Severity Decision Tree

```
Is any authentication completely broken?
  YES -> P1

Are >25% of requests failing?
  YES -> P1 (if auth) / P2 (other services)

Is a single downstream service down?
  YES -> P2

Is there elevated latency but requests still succeeding?
  YES -> P3

Is the issue isolated to a dev/staging environment?
  YES -> P4
```

---

## Escalation Path

```
L1 - On-Call Engineer (first responder)
  |  Diagnose using the relevant runbook.
  |  Attempt resolution steps.
  |  Escalate if unresolved within SLA or root cause is unknown.
  v
L2 - Senior Engineer / Tech Lead
  |  Deeper investigation, code-level analysis.
  |  Coordinate cross-service fixes.
  |  Authorize infrastructure changes (restarts, failovers).
  v
L3 - Platform / Infrastructure Lead
     Database failovers, Redis cluster recovery.
     Secrets rotation, emergency deploys.
     Executive communication for P1 outages.
```

---

## Communication Channels

| Channel | Purpose |
|---------|---------|
| `#incidents` (Slack) | Real-time incident coordination |
| `#alerts` (Slack) | Automated alert feed from monitoring |
| `#deployments` (Slack) | Deployment notifications |
| PagerDuty | On-call paging for P1/P2 |
| Email: `oncall@mangala.io` | Stakeholder notifications for P1 |

### Incident Communication Template (P1/P2)

```
[INCIDENT - P{severity}] {Short description}

Status: Investigating | Identified | Mitigating | Resolved
Started: {time UTC}
Impact: {which users / services are affected}
Current action: {what is being done right now}
Next update: {time UTC}
```

---

## General First-Response Checklist

Before opening a runbook, verify the basics:

- [ ] Check the health endpoint: `GET http://gateway:8000/actuator/health`
- [ ] Check if a recent deployment preceded the alert
- [ ] Verify infrastructure is healthy: `docker ps` or Kubernetes pod status
- [ ] Check `#deployments` for recent changes
- [ ] Confirm the alert is not a monitoring false-positive

---

## Service Port Reference

| Service | Default Port | Health Endpoint |
|---------|-------------|-----------------|
| Gateway | 8000 | `/actuator/health` |
| Auth Service | 8080 | `/actuator/health` |
| Wallet Service | 8081 | `/actuator/health` |
| Portfolio Service | 8182 | `/actuator/health` |
| Transaction Service | 8083 | `/actuator/health` |
| Price Feed Service | 8084 | `/actuator/health` |
| Crawler Service | 8085 | `/actuator/health` |
| Notification Service | 8086 | `/actuator/health` |
| Transaction History Service | 8087 | `/actuator/health` |

## Infrastructure Port Reference (Local / Dev)

| Service | Port | UI |
|---------|------|----|
| PostgreSQL | 5432 | pgAdmin: http://localhost:8085 |
| MongoDB | 27017 | Mongo Express: http://localhost:8083 |
| Redis | 6379 | Redis Commander: http://localhost:8084 |
| Kafka | 9092 (internal) / 9094 (external) | Kafka UI: http://localhost:8082 |
