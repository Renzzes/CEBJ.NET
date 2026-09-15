#!/bin/sh

echo "Content-Type: application/json"
echo ""

DB="/www/data/esp_coinslot.db"
LOG_FILE="/var/log/esp-monitor.log"

OFFLINE_THRESHOLD=180

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_esp_online() {
    local mac="$1"
    local last_seen="$2"
    local slot_name="$3"
    
    NOW=$(date +%s)
    
    # last_seen is now stored as Unix timestamp
    LAST_SEEN_EPOCH="$last_seen"
    
    if [ -z "$LAST_SEEN_EPOCH" ] || [ "$LAST_SEEN_EPOCH" = "" ]; then
        return
    fi
    
    DIFF=$((NOW - LAST_SEEN_EPOCH))
    MINUTES_OFFLINE=$((DIFF / 60))
    
    # Base offline threshold is 3 minutes. After that, mark as offline every 30 minutes.
    if [ "$MINUTES_OFFLINE" -ge 3 ]; then
        REMAINDER=$(((MINUTES_OFFLINE - 3) % 30))
        
        if [ "$REMAINDER" -eq 0 ]; then
            sqlite3 "$DB" "UPDATE esp_slots SET status='offline' WHERE slot_mac='$mac';" 2>/dev/null
            log "Sub Vendo $mac is offline for $MINUTES_OFFLINE minutes"
        fi
    fi
}

log "=== ESP Monitor Starting ==="

ESP_LIST=$(sqlite3 "$DB" "SELECT slot_mac, CAST(last_seen AS INTEGER), slot_name FROM esp_slots WHERE status='online' OR status='offline';" 2>/dev/null)

if [ -z "$ESP_LIST" ]; then
    log "No ESP devices found in database"
    exit 0
fi

IFS='
'
for row in $ESP_LIST; do
    MAC=$(echo "$row" | cut -d'|' -f1)
    LAST_SEEN=$(echo "$row" | cut -d'|' -f2)
    SLOT_NAME=$(echo "$row" | cut -d'|' -f3)
    
    if [ -n "$MAC" ] && [ -n "$LAST_SEEN" ]; then
        check_esp_online "$MAC" "$LAST_SEEN" "$SLOT_NAME"
    fi
done

log "=== ESP Monitor Complete ==="
