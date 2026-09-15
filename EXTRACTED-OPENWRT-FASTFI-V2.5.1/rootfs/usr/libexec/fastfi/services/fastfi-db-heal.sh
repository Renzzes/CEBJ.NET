#!/bin/sh
# FastFi DB Health Monitor
# Cron: 0 * * * * /root/fastfi-db-heal.sh

# Heal bindcode.db
DB="/www/data/bindcode.db"
BACKUP="/www/data/bindcode.db.bak"

CHECK=$(sqlite3 "$DB" "PRAGMA integrity_check;" 2>/dev/null)
if [ "$CHECK" != "ok" ]; then
    [ -f "$BACKUP" ] && cp "$BACKUP" "$DB"
fi

CHECK2=$(sqlite3 "$DB" "PRAGMA integrity_check;" 2>/dev/null)
[ "$CHECK2" = "ok" ] && cp "$DB" "$BACKUP"

# Heal sessions.db and esp_coinslot.db - WAL mode on jffs2 causes corruption
for DBFILE in /www/data/sessions.db /www/data/esp_coinslot.db; do
    [ ! -f "$DBFILE" ] && continue

    # Force DELETE journal mode (WAL is unsafe on jffs2 flash)
    JMODE=$(sqlite3 "$DBFILE" "PRAGMA journal_mode;" 2>/dev/null)
    if [ "$JMODE" = "wal" ]; then
        sqlite3 "$DBFILE" "PRAGMA journal_mode=DELETE;" 2>/dev/null
        rm -f "${DBFILE}-shm" "${DBFILE}-wal"
        logger -t fastfi-db-heal "Converted $DBFILE from WAL to DELETE mode"
    fi

    # Check integrity
    SCHECK=$(sqlite3 "$DBFILE" "PRAGMA integrity_check;" 2>/dev/null)
    if [ "$SCHECK" != "ok" ]; then
        logger -t fastfi-db-heal "CORRUPT: $DBFILE - attempting rebuild"
        cp "$DBFILE" "/tmp/$(basename $DBFILE).recover"
        sqlite3 "/tmp/$(basename $DBFILE).recover" ".dump" > "/tmp/$(basename $DBFILE).sql" 2>/dev/null
        if [ -s "/tmp/$(basename $DBFILE).sql" ]; then
            rm -f "$DBFILE" "${DBFILE}-shm" "${DBFILE}-wal"
            sqlite3 "$DBFILE" < "/tmp/$(basename $DBFILE).sql"
            sqlite3 "$DBFILE" "PRAGMA journal_mode=DELETE;" 2>/dev/null
            logger -t fastfi-db-heal "Rebuilt $DBFILE from dump"
        elif [ -f "${DBFILE}.bak" ]; then
            cp "${DBFILE}.bak" "$DBFILE"
            logger -t fastfi-db-heal "Restored $DBFILE from backup"
        fi
    else
        # Healthy: refresh a known-good .bak so a future corruption has a restore
        # source (the elif above already falls back to it). Refresh only when missing
        # or older than 24h to limit overlay writes on 16/32 MB flash (ZBT wg1608/wg3526),
        # where sessions.db row loss on corruption is most acute.
        BAK="${DBFILE}.bak"
        if [ ! -f "$BAK" ] || [ -z "$(find "$BAK" -mmin -1440 2>/dev/null)" ]; then
            cp "$DBFILE" "$BAK" 2>/dev/null
        fi
    fi
done

exit 0
