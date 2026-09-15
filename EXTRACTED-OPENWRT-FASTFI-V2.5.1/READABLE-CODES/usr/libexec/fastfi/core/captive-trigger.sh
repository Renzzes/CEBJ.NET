#!/bin/sh
# FastFi V6 Captive Portal Trigger Daemon
# Lightweight keepalive daemon managed by procd
# Monitors nodogsplash health and provides a stable process for system checks

logger -t fastfi-trigger "Starting FastFi Captive Trigger Daemon..."

# Wait for nodogsplash to be ready
while ! pidof nodogsplash >/dev/null 2>&1; do
    sleep 5
done

logger -t fastfi-trigger "Nodogsplash detected. Trigger daemon active."

# Simple health-monitoring loop
while true; do
    if ! pidof nodogsplash >/dev/null 2>&1; then
        logger -t fastfi-trigger "Nodogsplash not detected. Waiting for core-loop recovery..."
    fi
    sleep 60
done
