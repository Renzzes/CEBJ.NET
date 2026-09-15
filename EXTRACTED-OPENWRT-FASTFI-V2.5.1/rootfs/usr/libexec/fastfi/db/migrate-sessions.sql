-- FastFi V6 - Migration Script: sessions_v2 to sessions
-- Purpose: Consolidate dual-table architecture into single sessions table
-- Location: /usr/libexec/fastfi/db/migrate-sessions.sql
-- Usage: sqlite3 /www/data/sessions.db < /usr/libexec/fastfi/db/migrate-sessions.sql
-- 
-- IMPORTANT: Run this ONLY if you have data in both sessions and sessions_v2 tables
-- This script will merge sessions_v2 data into sessions table, then drop sessions_v2

BEGIN TRANSACTION;

-- ========================================
# STEP 1: Backup existing data
-- ========================================

-- Create backup of current sessions table
CREATE TABLE IF NOT EXISTS sessions_backup AS SELECT * FROM sessions;

-- ========================================
# STEP 2: Merge sessions_v2 into sessions
-- ========================================

-- Insert records from sessions_v2 that don't exist in sessions (by device_id)
INSERT OR IGNORE INTO sessions (
    device_id, mac_address, session_end, active, paused, remaining, 
    download_bytes, upload_bytes, ip_address, hostname, 
    created_at, updated_at, last_paused_at, pause_count, total_paused_duration
)
SELECT 
    device_id, mac_address, session_end, active, paused, remaining,
    download_bytes, upload_bytes, ip_address, hostname,
    created_at, updated_at, last_paused_at, pause_count, total_paused_duration
FROM sessions_v2
WHERE device_id NOT IN (SELECT device_id FROM sessions WHERE device_id != '');

-- Update existing records in sessions with newer data from sessions_v2
UPDATE sessions SET
    session_end = v2.session_end,
    active = v2.active,
    paused = v2.paused,
    remaining = v2.remaining,
    download_bytes = COALESCE(v2.download_bytes, sessions.download_bytes),
    upload_bytes = COALESCE(v2.upload_bytes, sessions.upload_bytes),
    ip_address = COALESCE(v2.ip_address, sessions.ip_address),
    hostname = COALESCE(v2.hostname, sessions.hostname),
    updated_at = v2.updated_at,
    last_paused_at = COALESCE(v2.last_paused_at, sessions.last_paused_at),
    pause_count = COALESCE(v2.pause_count, sessions.pause_count),
    total_paused_duration = COALESCE(v2.total_paused_duration, sessions.total_paused_duration)
FROM sessions_v2 v2
WHERE sessions.device_id = v2.device_id 
  AND sessions.device_id != ''
  AND v2.updated_at > sessions.updated_at;

-- ========================================
# STEP 3: Verify migration
-- ========================================

-- Count records in each table
SELECT 'Sessions before migration: ' || COUNT(*) FROM sessions_backup;
SELECT 'Sessions after migration: ' || COUNT(*) FROM sessions;
SELECT 'Sessions_v2 records: ' || COUNT(*) FROM sessions_v2;

-- Check for any orphaned records in sessions_v2
SELECT 'Orphaned sessions_v2 records: ' || COUNT(*) 
FROM sessions_v2 
WHERE device_id NOT IN (SELECT device_id FROM sessions WHERE device_id != '');

-- ========================================
# STEP 4: Drop sessions_v2 table (UNCOMMENT TO EXECUTE)
-- ========================================

-- WARNING: Uncomment the following lines ONLY after verifying the migration was successful
-- DROP TABLE IF EXISTS sessions_v2;
-- DROP INDEX IF EXISTS idx_sessions_v2_mac_active;
-- DROP INDEX IF EXISTS idx_sessions_v2_end_active;
-- DROP INDEX IF EXISTS idx_sessions_v2_paused;
-- DROP INDEX IF EXISTS idx_sessions_v2_device_id;

-- ========================================
# STEP 5: Rebuild indexes on sessions table
-- ========================================

-- Recreate all indexes on sessions table
DROP INDEX IF EXISTS idx_sessions_mac_active;
DROP INDEX IF EXISTS idx_sessions_end_active;
DROP INDEX IF EXISTS idx_sessions_paused;
DROP INDEX IF EXISTS idx_sessions_device_id;
DROP INDEX IF EXISTS idx_sessions_updated;
DROP INDEX IF EXISTS idx_sessions_remaining;

CREATE INDEX idx_sessions_mac_active ON sessions(mac_address, active);
CREATE INDEX idx_sessions_end_active ON sessions(session_end, active);
CREATE INDEX idx_sessions_paused ON sessions(paused, active);
CREATE INDEX idx_sessions_device_id ON sessions(device_id);
CREATE INDEX idx_sessions_updated ON sessions(updated_at);
CREATE INDEX idx_sessions_remaining ON sessions(remaining, active);

-- ========================================
# STEP 6: Optimize database
-- ========================================

ANALYZE sessions;
VACUUM;

COMMIT;

-- Output migration summary
SELECT '✅ Migration complete!' as status;
SELECT 'Sessions table records: ' || COUNT(*) as info FROM sessions;
SELECT 'Backup table records: ' || COUNT(*) as info FROM sessions_backup;
SELECT '' as info;
SELECT 'IMPORTANT: Verify data integrity, then manually drop sessions_v2 table' as warning;
SELECT 'Run: DROP TABLE sessions_v2;' as instruction;
