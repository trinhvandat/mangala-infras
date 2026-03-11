-- =============================================================================
-- StarRocks Analytics Schema for Mangala Portfolio Service
-- =============================================================================

CREATE DATABASE IF NOT EXISTS mangala_analytics;
USE mangala_analytics;

-- =============================================================================
-- Portfolio Snapshots - Time-series data for portfolio value tracking
-- =============================================================================
CREATE TABLE IF NOT EXISTS portfolio_snapshots (
    snapshot_id BIGINT,
    user_id VARCHAR(64),
    portfolio_id VARCHAR(64),
    wallet_address VARCHAR(128),
    chain_type VARCHAR(32),
    token_symbol VARCHAR(32),
    token_address VARCHAR(128),
    balance DECIMAL(38, 18),
    price_usd DECIMAL(20, 8),
    value_usd DECIMAL(20, 2),
    snapshot_time DATETIME,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
) ENGINE=OLAP
DUPLICATE KEY(snapshot_id)
PARTITION BY RANGE(snapshot_time) (
    PARTITION p202401 VALUES LESS THAN ("2024-02-01"),
    PARTITION p202402 VALUES LESS THAN ("2024-03-01"),
    PARTITION p202403 VALUES LESS THAN ("2024-04-01"),
    PARTITION p202404 VALUES LESS THAN ("2024-05-01"),
    PARTITION p202405 VALUES LESS THAN ("2024-06-01"),
    PARTITION p202406 VALUES LESS THAN ("2024-07-01"),
    PARTITION p202407 VALUES LESS THAN ("2024-08-01"),
    PARTITION p202408 VALUES LESS THAN ("2024-09-01"),
    PARTITION p202409 VALUES LESS THAN ("2024-10-01"),
    PARTITION p202410 VALUES LESS THAN ("2024-11-01"),
    PARTITION p202411 VALUES LESS THAN ("2024-12-01"),
    PARTITION p202412 VALUES LESS THAN ("2025-01-01"),
    PARTITION p202501 VALUES LESS THAN ("2025-02-01"),
    PARTITION p202502 VALUES LESS THAN ("2025-03-01"),
    PARTITION p202503 VALUES LESS THAN ("2025-04-01"),
    PARTITION p202504 VALUES LESS THAN ("2025-05-01"),
    PARTITION p202505 VALUES LESS THAN ("2025-06-01"),
    PARTITION p202506 VALUES LESS THAN ("2025-07-01")
)
DISTRIBUTED BY HASH(user_id) BUCKETS 8
PROPERTIES (
    "replication_num" = "1"
);

-- =============================================================================
-- Daily P&L Aggregation Table
-- =============================================================================
CREATE TABLE IF NOT EXISTS pnl_daily (
    user_id VARCHAR(64),
    portfolio_id VARCHAR(64),
    date DATE,
    total_value_usd DECIMAL(20, 2) SUM,
    daily_pnl DECIMAL(20, 2) SUM,
    daily_pnl_percentage DECIMAL(10, 4) REPLACE,
    cumulative_pnl DECIMAL(20, 2) REPLACE,
    holding_count INT SUM
) ENGINE=OLAP
AGGREGATE KEY(user_id, portfolio_id, date)
DISTRIBUTED BY HASH(user_id) BUCKETS 4
PROPERTIES (
    "replication_num" = "1"
);

-- =============================================================================
-- Token Performance Tracking
-- =============================================================================
CREATE TABLE IF NOT EXISTS token_performance (
    user_id VARCHAR(64),
    portfolio_id VARCHAR(64),
    token_symbol VARCHAR(32),
    chain_type VARCHAR(32),
    date DATE,
    avg_buy_price DECIMAL(20, 8) REPLACE,
    current_price DECIMAL(20, 8) REPLACE,
    total_quantity DECIMAL(38, 18) SUM,
    total_value_usd DECIMAL(20, 2) SUM,
    realized_pnl DECIMAL(20, 2) SUM,
    unrealized_pnl DECIMAL(20, 2) REPLACE
) ENGINE=OLAP
AGGREGATE KEY(user_id, portfolio_id, token_symbol, chain_type, date)
DISTRIBUTED BY HASH(user_id) BUCKETS 4
PROPERTIES (
    "replication_num" = "1"
);

-- =============================================================================
-- Chain Distribution Analytics
-- =============================================================================
CREATE TABLE IF NOT EXISTS chain_distribution (
    user_id VARCHAR(64),
    portfolio_id VARCHAR(64),
    snapshot_date DATE,
    chain_type VARCHAR(32),
    total_value_usd DECIMAL(20, 2) SUM,
    token_count INT SUM,
    percentage DECIMAL(10, 4) REPLACE
) ENGINE=OLAP
AGGREGATE KEY(user_id, portfolio_id, snapshot_date, chain_type)
DISTRIBUTED BY HASH(user_id) BUCKETS 4
PROPERTIES (
    "replication_num" = "1"
);
