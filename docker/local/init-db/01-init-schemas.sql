CREATE SCHEMA IF NOT EXISTS auth;
CREATE USER auth_service WITH PASSWORD 'auth123';
GRANT ALL PRIVILEGES ON SCHEMA auth TO auth_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA auth GRANT ALL ON TABLES TO auth_service;

-- Wallet Service Schema
CREATE SCHEMA IF NOT EXISTS wallet;
CREATE USER wallet_service WITH PASSWORD 'wallet123';
GRANT ALL PRIVILEGES ON SCHEMA wallet TO wallet_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA wallet GRANT ALL ON TABLES TO wallet_service;

-- Portfolio Service Schema
CREATE SCHEMA IF NOT EXISTS portfolio;
CREATE USER portfolio_service WITH PASSWORD 'portfolio123';
GRANT ALL PRIVILEGES ON SCHEMA portfolio TO portfolio_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA portfolio GRANT ALL ON TABLES TO portfolio_service;

-- Crawler Service Schema
CREATE SCHEMA IF NOT EXISTS crawler;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'crawler_service') THEN
    CREATE USER crawler_service WITH PASSWORD 'crawler123';
  END IF;
END
$$;

GRANT ALL PRIVILEGES ON SCHEMA crawler TO crawler_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA crawler GRANT ALL ON TABLES TO crawler_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA crawler GRANT ALL ON SEQUENCES TO crawler_service;
ALTER DEFAULT PRIVILEGES IN SCHEMA crawler GRANT ALL ON FUNCTIONS TO crawler_service;