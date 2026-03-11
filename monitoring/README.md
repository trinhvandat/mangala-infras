# Mangala Monitoring

This directory contains Prometheus alert rules and Alertmanager configuration for production observability.

## Directory Structure

```
monitoring/
├── alertmanager/
│   └── alertmanager.yml       # Alertmanager routing and receiver config
├── prometheus/
│   └── alerts/
│       ├── gateway-alerts.yml # HTTP gateway error rate and latency alerts
│       ├── auth-alerts.yml    # Authentication failure and policy reload alerts
│       └── redis-alerts.yml   # Redis availability alert
└── README.md
```

## Slack Webhook Configuration

1. Create an Incoming Webhook in your Slack workspace:
   - Go to https://api.slack.com/apps -> Create New App -> Incoming Webhooks
   - Enable Incoming Webhooks and add a new webhook to the `#alerts` channel
   - Copy the generated webhook URL

2. Set the environment variable before starting Alertmanager:

   ```bash
   export SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

3. When using Docker Compose, pass it via environment substitution or a `.env` file:

   ```env
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```

## Alert Rules

### Gateway Alerts (`gateway-alerts.yml`)

| Alert | Severity | Condition | For |
|---|---|---|---|
| HighErrorRate | critical | 5xx rate > 1% of all requests | 5m |
| HighGatewayLatency | warning | p99 latency > 500ms | 5m |

### Auth Alerts (`auth-alerts.yml`)

| Alert | Severity | Condition | For |
|---|---|---|---|
| AuthFailureSpike | warning | Auth failures > 10/s over 5m window | 2m |
| PolicyReloadFailure | critical | Any policy reload failure in 10m window | immediate |

### Redis Alerts (`redis-alerts.yml`)

| Alert | Severity | Condition | For |
|---|---|---|---|
| RedisConnectionFailure | critical | `redis_up == 0` | 1m |

## Testing Each Alert

### HighErrorRate

Trigger by generating 5xx responses on the gateway and querying Prometheus:

```promql
sum(rate(http_server_requests_seconds_count{status=~"5.."}[5m])) / sum(rate(http_server_requests_seconds_count[5m])) > 0.01
```

Use a load tool such as `k6` or `hey` to send requests that produce 5xx responses, then verify the alert fires in Prometheus UI at `http://localhost:9090/alerts`.

### HighGatewayLatency

Introduce artificial latency on the gateway (e.g., via a slow downstream mock) and check:

```promql
histogram_quantile(0.99, rate(http_server_requests_seconds_bucket{application="mangala-gateway"}[5m])) > 0.5
```

### AuthFailureSpike

Send repeated requests with invalid credentials:

```bash
for i in $(seq 1 200); do
  curl -s -o /dev/null -X POST http://localhost:8080/auth/login \
    -H 'Content-Type: application/json' \
    -d '{"username":"bad","password":"wrong"}'
done
```

Then verify the metric increments:

```promql
sum(rate(auth_failures_total[5m]))
```

### PolicyReloadFailure

Corrupt the policy file temporarily and trigger a reload, then verify:

```promql
increase(policy_reload_failures_total[10m]) > 0
```

### RedisConnectionFailure

Stop the Redis container and confirm the alert fires within 1 minute:

```bash
docker stop mangala-redis
```

Verify in Prometheus UI:

```promql
redis_up == 0
```

Restart Redis to resolve:

```bash
docker start mangala-redis
```
