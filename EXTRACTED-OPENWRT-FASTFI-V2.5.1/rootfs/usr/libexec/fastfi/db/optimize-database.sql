-- FastFi V6 - Database Optimization Script
-- Purpose: Add missing indexes, optimize schema, improve query performance
-- Location: /usr/libexec/fastfi/db/optimize-database.sql
-- Usage: sqlite3 /www/data/sessions.db < /usr/libexec/fastfi/db/optimize-database.sql

BEGIN TRANSACTION;

-- ========================================
# SESSIONS TABLE OPTIMIZATION
-- ========================================

-- Create composite index for common queries (MAC + active status)
CREATE INDEX IF NOT EXISTS idx_sessions_mac_active 
ON sessions(mac_address, active);

-- Index for session expiry checks
CREATE INDEX IF NOT EXISTS idx_sessions_end_active 
ON sessions(session_end, active);

-- Index for paused sessions
CREATE INDEX IF NOT EXISTS idx_sessions_paused 
ON sessions(paused, active);

-- Index for device_id lookups (Android/iOS MAC randomization support)
CREATE INDEX IF NOT EXISTS idx_sessions_device_id 
ON sessions(device_id);

-- Index for batch operations
CREATE INDEX IF NOT EXISTS idx_sessions_updated 
ON sessions(updated_at);

-- Index for remaining time queries
CREATE INDEX IF NOT EXISTS idx_sessions_remaining 
ON sessions(remaining, active);

-- ========================================
# SALES TABLE OPTIMIZATION
-- ========================================

-- Index for date range queries (monthly/daily reports)
CREATE INDEX IF NOT EXISTS idx_sales_created 
ON sales(created_at);

-- Composite index for MAC-based sales history
CREATE INDEX IF NOT EXISTS idx_sales_mac_date 
ON sales(mac_address, created_at);

-- Index for amount aggregation
CREATE INDEX IF NOT EXISTS idx_sales_amount 
ON sales(amount);

-- ========================================
# VOUCHERS TABLE OPTIMIZATION
-- ========================================

-- Unique index on code (should already exist, but ensure)
CREATE UNIQUE INDEX IF NOT EXISTS idx_vouchers_code_unique 
ON vouchers(code);

-- Index for batch filtering
CREATE INDEX IF NOT EXISTS idx_vouchers_batch 
ON vouchers(batch);

-- Index for status filtering
CREATE INDEX IF NOT EXISTS idx_vouchers_status 
ON vouchers(status);

-- Index for expiry checks
CREATE INDEX IF NOT EXISTS idx_vouchers_expires 
ON vouchers(expires_at, status);

-- Composite index for active vouchers by batch
CREATE INDEX IF NOT EXISTS idx_vouchers_batch_active 
ON vouchers(batch, status);

-- ========================================
# ESP DEVICES TABLE OPTIMIZATION
-- ========================================

-- Unique index on MAC address
CREATE UNIQUE INDEX IF NOT EXISTS idx_esp_mac_unique 
ON esp_devices(mac_address);

-- Index for slot number lookups
CREATE INDEX IF NOT EXISTS idx_esp_slot 
ON esp_devices(slot_number);

-- Index for active ESP devices
CREATE INDEX IF NOT EXISTS idx_esp_active 
ON esp_devices(active);

-- ========================================
# ANALYTICS & PERFORMANCE VIEWS
-- ========================================

-- Create view for active sessions with formatted data
DROP VIEW IF EXISTS v_active_sessions;
CREATE VIEW v_active_sessions AS
SELECT 
    s.device_id,
    s.mac_address,
    s.ip_address,
    s.hostname,
    s.session_end,
    s.active,
    s.paused,
    s.remaining,
    s.download_bytes,
    s.upload_bytes,
    s.created_at,
    s.updated_at,
    CASE 
        WHEN s.paused = 1 THEN 'PAUSED'
        WHEN s.active = 1 AND s.session_end > strftime('%s','now') THEN 'ACTIVE'
        ELSE 'EXPIRED'
    END as session_state,
    CASE 
        WHEN s.paused = 1 THEN s.remaining
        WHEN s.active = 1 THEN MAX(0, s.session_end - strftime('%s','now'))
        ELSE 0
    END as time_remaining_seconds
FROM sessions s
WHERE s.active = 1;

-- Create view for daily sales summary
DROP VIEW IF EXISTS v_daily_sales;
CREATE VIEW v_daily_sales AS
SELECT 
    DATE(created_at, 'unixepoch', 'localtime') as sale_date,
    COUNT(*) as transaction_count,
    SUM(amount) as total_revenue,
    AVG(amount) as avg_transaction,
    MIN(amount) as min_sale,
    MAX(amount) as max_sale
FROM sales
GROUP BY DATE(created_at, 'unixepoch', 'localtime')
ORDER BY sale_date DESC;

-- Create view for monthly sales summary
DROP VIEW IF EXISTS v_monthly_sales;
CREATE VIEW v_monthly_sales AS
SELECT 
    strftime('%Y-%m', created_at, 'unixepoch', 'localtime') as month,
    COUNT(*) as transaction_count,
    SUM(amount) as total_revenue,
    AVG(amount) as avg_transaction
FROM sales
GROUP BY strftime('%Y-%m', created_at, 'unixepoch', 'localtime')
ORDER BY month DESC;

-- Create view for voucher statistics
DROP VIEW IF EXISTS v_voucher_stats;
CREATE VIEW v_voucher_stats AS
SELECT 
    batch,
    COUNT(*) as total_vouchers,
    SUM(CASE WHEN status = 'active' THEN 1 ELSE 0 END) as active_count,
    SUM(CASE WHEN status = 'used' THEN 1 ELSE 0 END) as used_count,
    SUM(CASE WHEN status = 'active' AND expires_at < strftime('%s','now') THEN 1 ELSE 0 END) as expired_count,
    SUM(price) as total_value,
    MIN(created_at) as first_generated,
    MAX(created_at) as last_generated
FROM vouchers
GROUP BY batch
ORDER BY last_generated DESC;

-- ========================================
# DATABASE MAINTENANCE
-- ========================================

-- Analyze tables to update query planner statistics
ANALYZE sessions;
ANALYZE sales;
ANALYZE vouchers;
ANALYZE esp_devices;
ANALYZE session_history;

-- Vacuum database to reclaim space and defragment
VACUUM;

COMMIT;

-- Output optimization summary
SELECT '✅ Database optimization complete!' as status;
SELECT 'Indexes created: ' || COUNT(*) as info FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%';
SELECT 'Views created: ' || COUNT(*) as info FROM sqlite_master WHERE type='view' AND name LIKE 'v_%';
