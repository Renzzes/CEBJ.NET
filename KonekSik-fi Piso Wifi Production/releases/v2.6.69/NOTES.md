GitHub system updates are the customer update path.

2.6.69 — OTA overlay recovery for tight 16 MB routers:
- Check for Updates downloads a tiny bootstrap update.tar.gz (fits ~168KB free).
- After reboot the router automatically pulls update-full.tar.gz (Delete/Unbind lifecycle + Stage 2 fixes).
- New OTA engine reclaims recoverable overlay space, detects in-place overlay code, and copies file-by-file (rm-before-cp) to avoid peak double-space failures.
- Do not interrupt power during the second automatic apply. Watch Admin OTA progress / /tmp/ota-continue-full.log if needed.

Flash KonekSik-fi-EW1200G-PRO-sysupgrade.bin for a new router. Customers should use Check for Updates (not a manual .bin) when possible. This build has not been flashed on hardware.
