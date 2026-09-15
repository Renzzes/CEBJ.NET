#!/bin/sh

LICENSE_FILE="/etc/fastfi/license.json"

get_license_status() {

    if [ ! -f "$LICENSE_FILE" ]; then
        echo "inactive"
        return
    fi

    # Extract status field if present
    STATUS=$(grep '"status"' "$LICENSE_FILE" | cut -d '"' -f4)

    # If status exists, return it
    if [ -n "$STATUS" ]; then
        echo "$STATUS"
        return
    fi

    # Treat "License key has already been used" as active
    USED=$(grep 'License key has already been used' "$LICENSE_FILE")

    if [ -n "$USED" ]; then
        echo "active"
        return
    fi

    # Fallback
    echo "inactive"
}
