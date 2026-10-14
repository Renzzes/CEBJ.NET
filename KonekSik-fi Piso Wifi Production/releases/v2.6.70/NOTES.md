GitHub Check for Updates is the customer path.

2.6.70 — Proven fix for Delete/Unbind not applying on tight overlays:
Root cause: v2.6.69 bootstrap only shipped OTA engine files; update-full.tar.gz still could not land on ~168KB-free overlays, so Delete/Unbind handlers never reached the router DB.
This bootstrap now ships esp.lua, esp_license.lua, sqlite.lua, and admin-esp-lifecycle.js (need+peak ~116KB) so Unbind clears live_mac and Delete removes the esp_slots row immediately. Writes are transactional and verified.
After reboot, continue-full still pulls update-full.tar.gz when the OTA engine is present.

Do not cut power during applies. .bin is for new routers/recovery only. This build has not been flashed on hardware.
