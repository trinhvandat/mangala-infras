// MongoDB 7.0 Schema Initialization for Web3 Wallet
// Run: mongosh < 01-init-wallet-schema.js

db = db.getSiblingDB('wallet_db');

// ============================================
// USERS COLLECTION
// ============================================
db.createCollection('users', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['publicKey', 'createdAt', 'status'],
      properties: {
        publicKey: {
          bsonType: 'string',
          pattern: '^0x[a-fA-F0-9]{40}$',
          description: 'Ethereum address format'
        },
        status: {
          enum: ['ACTIVE', 'SUSPENDED', 'PENDING_VERIFICATION'],
          description: 'Account status'
        },
        // EMBEDDED: Security settings (1-to-1, always read together)
        security: {
          bsonType: 'object',
          properties: {
            passkeys: {
              bsonType: 'array',
              maxItems: 5, // Bounded array - safe to embed
              items: {
                bsonType: 'object',
                required: ['credentialId', 'publicKey', 'createdAt'],
                properties: {
                  credentialId: { bsonType: 'string' },
                  publicKey: { bsonType: 'string' },
                  deviceName: { bsonType: 'string' },
                  createdAt: { bsonType: 'date' },
                  lastUsedAt: { bsonType: 'date' }
                }
              }
            },
            twoFactorEnabled: { bsonType: 'bool' },
            withdrawalWhitelist: {
              bsonType: 'array',
              maxItems: 20,
              items: { bsonType: 'string' }
            }
          }
        },
        // EMBEDDED: Asset balances snapshot (denormalized for fast reads)
        // Updated via Change Streams khi có transaction mới
        balanceSnapshot: {
          bsonType: 'object',
          additionalProperties: {
            bsonType: 'object',
            properties: {
              amount: { bsonType: 'decimal' },
              lastUpdated: { bsonType: 'date' }
            }
          }
        },
        createdAt: { bsonType: 'date' },
        updatedAt: { bsonType: 'date' }
      }
    }
  }
});

// ============================================
// TRANSACTIONS COLLECTION
// ============================================
db.createCollection('transactions', {
  validator: {
    $jsonSchema: {
      bsonType: 'object',
      required: ['userId', 'txHash', 'type', 'status', 'createdAt'],
      properties: {
        userId: { bsonType: 'objectId' },
        // DENORMALIZED: Avoid $lookup for common queries
        userPublicKey: { bsonType: 'string' },

        txHash: {
          bsonType: 'string',
          pattern: '^0x[a-fA-F0-9]{64}$'
        },
        type: {
          enum: ['DEPOSIT', 'WITHDRAWAL', 'SWAP', 'TRANSFER', 'CONTRACT_CALL']
        },
        status: {
          enum: ['PENDING', 'CONFIRMED', 'FAILED', 'CANCELLED']
        },
        chain: {
          bsonType: 'string',
          description: 'ethereum, polygon, arbitrum, etc.'
        },
        // Flexible metadata - varies by transaction type
        // MongoDB 7.0: Use Compound Wildcard Index for this
        metadata: {
          bsonType: 'object',
          properties: {
            fromAddress: { bsonType: 'string' },
            toAddress: { bsonType: 'string' },
            tokenSymbol: { bsonType: 'string' },
            tokenAddress: { bsonType: 'string' },
            amount: { bsonType: 'decimal' },
            amountUsd: { bsonType: 'decimal' },
            gasUsed: { bsonType: 'long' },
            gasPrice: { bsonType: 'decimal' },
            blockNumber: { bsonType: 'long' },
            // Swap specific
            swapRate: { bsonType: 'decimal' },
            slippage: { bsonType: 'decimal' }
          }
        },
        createdAt: { bsonType: 'date' },
        confirmedAt: { bsonType: 'date' }
      }
    }
  },
  // Time Series optimization hint (không phải Time Series collection thật)
  // Vì transactions cần flexible queries
  timeseries: undefined
});

// ============================================
// INDEXES - Critical for Performance
// ============================================

// Users indexes
db.users.createIndex({ publicKey: 1 }, { unique: true });
db.users.createIndex({ 'security.passkeys.credentialId': 1 });
db.users.createIndex({ status: 1, createdAt: -1 });

// Transactions indexes
// Compound index cho query phổ biến nhất: "Lấy transactions của user X, sắp xếp theo thời gian"
db.transactions.createIndex(
  { userId: 1, createdAt: -1 },
  { name: 'idx_user_transactions_timeline' }
);

// Compound index cho filter by status
db.transactions.createIndex(
  { userId: 1, status: 1, createdAt: -1 },
  { name: 'idx_user_transactions_by_status' }
);

// Unique constraint on txHash per chain
db.transactions.createIndex(
  { chain: 1, txHash: 1 },
  { unique: true, name: 'idx_unique_tx_per_chain' }
);

// MongoDB 7.0: Compound Wildcard Index for flexible metadata queries
// Cho phép query bất kỳ field nào trong metadata mà vẫn dùng được userId prefix
db.transactions.createIndex(
  { userId: 1, 'metadata.$**': 1 },
  { name: 'idx_user_metadata_wildcard' }
);

// Partial index cho pending transactions (hot data)
db.transactions.createIndex(
  { status: 1, createdAt: 1 },
  {
    partialFilterExpression: { status: 'PENDING' },
    name: 'idx_pending_transactions'
  }
);

print('✅ Wallet schema initialized successfully');
print('Collections: users, transactions');
print('Indexes created for optimal query patterns');
