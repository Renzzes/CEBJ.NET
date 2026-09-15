#!/bin/sh
# FastFi V6 - Database Maintenance Script
# Purpose: Automated database cleanup, vacuum, and optimization
# Location: /usr/libexec/fastfi/db/maintenance.sh
# Usage: Run weekly via cron or manually

set -e

DB_DIR="/www/data"
CONFIG_DB="$DB_DIR/bindcode.db"
SESSIONS_DB="$DB_DIR/sessions.db"
VOUCHER_DB="$DB_DIR/vouchers.db"
ESP_DB="$DB_DIR/esp_coinslot.db"

echo "=== FastFi V6 Database Maintenance ==="
echo "Started at: $(date)"
echo ""

# ========================================
# 1. BACKUP DATABASES
# ========================================

echo "[1/5] Creating backups..."

for db in "$CONFIG_DB" "$SESSIONS_DB" "$VOUCHER_DB" "$ESP_DB"; do
    if [ -f "$db" ]; then
        backup_file="${db}.bak.$(date +%Y%m%d%H%M%S)"
        cp "$db" "$backup_file"
        echo "✓ Backed up: $(basename $db)"
        
        # Keep only last 3 backups
        ls -t ${db}.bak.* 2>/dev/null | tail -n +4 | xargs rm -f 2>/dev/null || true
    fi
done

echo ""

# ========================================
# 2. CLEANUP EXPIRED DATA
# ========================================

echo "[2/5] Cleaning expired data..."

# Remove expired sessions (older than 7 days)
if [ -f "$SESSIONS_DB" ]; then
    EXPIRED_SESSIONS=$(sqlite3 "$SESSIONS_DB" "SELECT COUNT(*) FROM sessions WHERE active=0 AND session_end < $(date -d '7 days ago' +%s 2>/dev/null || date -v-7d +%s 2>/dev/null || echo $(($(date +%s) - 604800)));")
    sqlite3 "$SESSIONS_DB" "DELETE FROM sessions WHERE active=0 AND session_end < $(date +%s) - 604800;" 2>/dev/null || true
    echo "✓ Removed $EXPIRED_SESSIONS expired sessions"
    
    # Clean old session history (keep last 1000 events)
    OLD_HISTORY=$(sqlite3 "$SESSIONS_DB" "SELECT COUNT(*) FROM session_history WHERE id NOT IN (SELECT id FROM session_history ORDER BY timestamp DESC LIMIT 1000);" 2>/dev/null || echo "0")
    sqlite3 "$SESSIONS_DB" "DELETE FROM session_history WHERE id NOT IN (SELECT id FROM session_history ORDER BY timestamp DESC LIMIT 1000);" 2>/dev/null || true
    echo "✓ Cleaned $OLD_HISTORY old history events"
fi

# Remove used vouchers older than 30 days
if [ -f "$VOUCHER_DB" ]; then
    EXPIRED_VOUCHERS=$(sqlite3 "$VOUCHER_DB" "SELECT COUNT(*) FROM vouchers WHERE status='used' AND used_at < $(date +%s) - 2592000;" 2>/dev/null || echo "0")
    sqlite3 "$VOUCHER_DB" "DELETE FROM vouchers WHERE status='used' AND used_at < $(date +%s) - 2592000;" 2>/dev/null || true
    echo "✓ Removed $EXPIRED_VOUCHERS old used vouchers"
    
    # Remove expired unused vouchers. expires_at=0 is the "never expires"
    # sentinel, so it must be excluded or every no-expiry voucher is purged.
    EXPIRED_UNUSED=$(sqlite3 "$VOUCHER_DB" "SELECT COUNT(*) FROM vouchers WHERE status='active' AND expires_at > 0 AND expires_at < $(date +%s);" 2>/dev/null || echo "0")
    sqlite3 "$VOUCHER_DB" "DELETE FROM vouchers WHERE status='active' AND expires_at > 0 AND expires_at < $(date +%s);" 2>/dev/null || true
    echo "✓ Removed $EXPIRED_UNUSED expired unused vouchers"
fi

# Clean old sales records (keep last 90 days for analytics)
# Note: sales table is inside sessions.db
if [ -f "$SESSIONS_DB" ]; then
    OLD_SALES=$(sqlite3 "$SESSIONS_DB" "SELECT COUNT(*) FROM sales WHERE created_at < $(date +%s) - 7776000;" 2>/dev/null || echo "0")
    sqlite3 "$SESSIONS_DB" "DELETE FROM sales WHERE created_at < $(date +%s) - 7776000;" 2>/dev/null || true
    echo "✓ Archived $OLD_SALES old sales records"
fi

echo ""

# ========================================
# 3. APPLY OPTIMIZATIONS
# ========================================

echo "[3/5] Applying database optimizations..."

OPTIMIZE_SCRIPT="/usr/libexec/fastfi/db/optimize-database.sql"
if [ -f "$OPTIMIZE_SCRIPT" ] && [ -f "$SESSIONS_DB" ]; then
    sqlite3 "$SESSIONS_DB" < "$OPTIMIZE_SCRIPT" 2>/dev/null
    echo "✓ Applied SQL optimizations"
else
    # Manual optimization if script not found
    for db in "$CONFIG_DB" "$SESSIONS_DB" "$VOUCHER_DB"; do
        if [ -f "$db" ]; then
            sqlite3 "$db" "ANALYZE;" 2>/dev/null || true
            sqlite3 "$db" "VACUUM;" 2>/dev/null || true
            echo "✓ Optimized: $(basename $db)"
        fi
    done
fi

echo ""

# ========================================
# 4. INTEGRITY CHECKS
# ========================================

echo "[4/5] Running integrity checks..."

for db in "$CONFIG_DB" "$SESSIONS_DB" "$VOUCHER_DB" "$ESP_DB"; do
    if [ -f "$db" ]; then
        result=$(sqlite3 "$db" "PRAGMA integrity_check;" 2>/dev/null)
        if [ "$result" = "ok" ]; then
            echo "✓ $(basename $db): OK"
        else
            echo "⚠ $(basename $db): ISSUES DETECTED"
            echo "  Details: $result"
        fi
    fi
done

echo ""

# ========================================
# 5. DATABASE STATISTICS
# ========================================

echo "[5/5] Database statistics:"

if [ -f "$SESSIONS_DB" ]; then
    ACTIVE_SESSIONS=$(sqlite3 "$SESSIONS_DB" "SELECT COUNT(*) FROM sessions WHERE active=1;" 2>/dev/null || echo "0")
    TOTAL_SESSIONS=$(sqlite3 "$SESSIONS_DB" "SELECT COUNT(*) FROM sessions;" 2>/dev/null || echo "0")
    DB_SIZE=$(du -h "$SESSIONS_DB" 2>/dev/null | cut -f1)
    echo "  Sessions DB: $DB_SIZE"
    echo "    - Active sessions: $ACTIVE_SESSIONS"
    echo "    - Total records: $TOTAL_SESSIONS"
fi

if [ -f "$VOUCHER_DB" ]; then
    ACTIVE_VOUCHERS=$(sqlite3 "$VOUCHER_DB" "SELECT COUNT(*) FROM vouchers WHERE status='active';" 2>/dev/null || echo "0")
    USED_VOUCHERS=$(sqlite3 "$VOUCHER_DB" "SELECT COUNT(*) FROM vouchers WHERE status='used';" 2>/dev/null || echo "0")
    DB_SIZE=$(du -h "$VOUCHER_DB" 2>/dev/null | cut -f1)
    echo "  Vouchers DB: $DB_SIZE"
    echo "    - Active: $ACTIVE_VOUCHERS"
    echo "    - Used: $USED_VOUCHERS"
fi

# Sales stats (sales table lives in sessions.db)
if [ -f "$SESSIONS_DB" ]; then
    TODAY_SALES=$(sqlite3 "$SESSIONS_DB" "SELECT COALESCE(SUM(amount),0) FROM sales WHERE created_at > $(date +%s) - 86400;" 2>/dev/null || echo "0")
    echo "    - Today's revenue: ₱$TODAY_SALES"
fi

echo ""
echo "=== Maintenance Complete ==="
echo "Finished at: $(date)"
echo ""
echo "Next scheduled maintenance: $(date -d '+7 days' 2>/dev/null || date -v+7d 2>/dev/null || echo 'In 7 days')"

exit 0
