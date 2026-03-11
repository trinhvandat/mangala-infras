#!/bin/bash
# =============================================================================
# Elasticsearch Setup Script for Mangala
# =============================================================================
# This script initializes Elasticsearch with:
# - ILM (Index Lifecycle Management) policy for transaction index retention
# - Index template with proper mappings
# - Initial index with rollover alias
# =============================================================================

ES_HOST="${ES_HOST:-localhost}"
ES_PORT="${ES_PORT:-9200}"
ES_URL="http://${ES_HOST}:${ES_PORT}"

# Wait for Elasticsearch to be ready
echo "Waiting for Elasticsearch to be ready..."
until curl -s "${ES_URL}/_cluster/health" | grep -q '"status":"green"\|"status":"yellow"'; do
    echo "Elasticsearch not ready, retrying in 5s..."
    sleep 5
done
echo "Elasticsearch is ready!"

# Create ILM policy
echo "Creating ILM policy..."
curl -X PUT "${ES_URL}/_ilm/policy/transactions-ilm-policy" \
    -H "Content-Type: application/json" \
    -d @/init/ilm-policy.json

echo ""

# Create index template
echo "Creating index template..."
curl -X PUT "${ES_URL}/_index_template/transactions-template" \
    -H "Content-Type: application/json" \
    -d @/init/index-template.json

echo ""

# Create initial index with rollover alias
echo "Creating initial index with alias..."
curl -X PUT "${ES_URL}/transactions-000001" \
    -H "Content-Type: application/json" \
    -d '{
        "aliases": {
            "transactions": {
                "is_write_index": true
            }
        }
    }'

echo ""
echo "Elasticsearch setup complete!"

# Display index info
echo ""
echo "Current indices:"
curl -s "${ES_URL}/_cat/indices?v"

echo ""
echo "ILM policy status:"
curl -s "${ES_URL}/_ilm/policy/transactions-ilm-policy" | head -20
