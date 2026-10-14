# KonekSik-Fi OTA & GitHub Release Process

**Audience:** ACE / release agent  
**First used:** v2.6.69 (overlay recovery)  
**Customer path:** Admin → System OTA → Check for Updates (GitHub). Do **not** require customers to flash `.bin` for normal code updates.

---

## Why this exists

Ruijie EW1200G Pro has a **~16 MB overlay**. Old OTA clients measure:

`need = du(www + lua/fastfi + libexec/fastfi + etc)` + `peak = largest file`

A full code bundle is ~2.0–2.5 MB copy-up. Boxes with only **~168 KB free** fail with:

`FATAL: Insufficient overlay space for .tar.gz apply...`

Customers rely on GitHub OTA, so every release must remain installable on a tight overlay.

---

## Dual-asset model (required every release)

| GitHub asset | Role | Who downloads it |
|--------------|------|------------------|
| **`update.tar.gz`** | **Bootstrap** — tiny; fits ≤ ~160 KB need+peak | Check for Updates (always) |
| **`update-full.tar.gz`** | **Full** code overlay (www + lua + libexec + kept etc) | Auto `continue-full` after bootstrap reboot |
| **`KonekSik-fi-EW1200G-PRO-sysupgrade.bin`** | Fresh flash / recovery only | Manual Admin flash + Flash Auth |
| **`sha256sums`** | Digests for all of the above | OTA verify |

### Bootstrap rules

- **Must include lifecycle** (so Delete/Unbind work even if `update-full` cannot land yet):
  - `usr/lib/lua/fastfi/db/sqlite.lua`
  - `usr/lib/lua/fastfi/api/routes/esp.lua`
  - `usr/lib/lua/fastfi/api/routes/esp_license.lua`
  - `www/admin-esp-lifecycle.js` (tiny UI override; `migrate.sh` injects into `admin.html`)
- Optional if budget allows: `etc/init.d/fastfi`, `usr/libexec/fastfi/core/fastfi-ota.sh`
- Build with: `python tools/make_ota_bootstrap.py` (writes `rootfs/update.tar.gz`).
- Gate: **need_kb + peak_kb ≤ 160** (target: boxes with ~168 KB free).
- `migrate.sh` must set `/etc/fastfi/ota_pending_full`, inject lifecycle JS, and keep an `rc.local` one-shot fallback.
- **Do not** set `/etc/fastfi/.ota_overlay_code` unless www+lua+libexec all copied.

### Full package rules

- Build with: `python make_archive.py` in `EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs`, then rename to **`update-full.tar.gz`**.
- Copy-up budget: **need + peak ≤ 3200 KB** (`make_archive.py` enforces).
- Keep excluding vendor/static media and preview/dev assets (see `make_archive.py` filter).
- Never put secrets, `/www/data`, or private keys in either tarball.

### After bootstrap reboot

1. `etc/init.d/fastfi` (or `rc.local` fallback) sees `ota_pending_full`.
2. Runs `fastfi-ota.sh continue-full` (~20–25 s after boot).
3. Downloads **`update-full.tar.gz`** from the **same** GitHub release, verifies, applies, reboots.
4. Flag is cleared when apply is armed; restored if apply fails so the next boot retries.

---

## Version bump checklist

1. Bump **both**:
   - `EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs/VERSION`
   - `EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs/www/version.txt`
2. Same version string in bootstrap and full (e.g. `2.6.70`).
3. Cache-bust admin assets when UI changes (`admin-ext.js?v=N` in `admin.html`).

---

## Build & publish checklist

Work from repo root. Use **absolute** overlay path for WSL ImageBuilder (relative paths break `wslpath`).

```text
# 1) Version files already bumped

# 2) Full OTA
cd EXTRACTED-OPENWRT-FASTFI-V2.5.1/rootfs
python make_archive.py
ren update.tar.gz update-full.tar.gz

# 3) Bootstrap OTA (overwrites update.tar.gz — correct)
python ../../tools/make_ota_bootstrap.py
# Confirm printed need+peak ≤ 160

# 4) Sysupgrade .bin (WSL ImageBuilder + symlink gate)
powershell -File tools/build-ruijie-wsl.ps1 -OverlayPath "<ABS>\rootfs" -LogPath "<ABS>\...\ruijie-build-X.Y.Z.log" -Suffix koneksik

# 5) Stage
KonekSik-fi Piso Wifi Production/releases/vX.Y.Z/
  update.tar.gz              # bootstrap
  update-full.tar.gz         # full
  KonekSik-fi-EW1200G-PRO-sysupgrade.bin
  *.sha256 / sha256sums / NOTES.md

# 6) Verify image version
unsquashfs … www/version.txt  →  must equal X.Y.Z

# 7) GitHub release (Latest)
gh release create vX.Y.Z --latest --target main \
  update.tar.gz update-full.tar.gz \
  KonekSik-fi-EW1200G-PRO-sysupgrade.bin \
  KonekSik-fi-EW1200G-PRO-sysupgrade.bin.sha256 \
  sha256sums
```

### NOTES.md must say

- Customers use **Check for Updates** (GitHub).
- Bootstrap then **automatic** full apply (two reboots possible).
- Do not cut power during the second apply.
- `.bin` is for new routers / recovery, not the default customer path.
- “This build has not been flashed on hardware” until validated.

---

## OTA engine invariants (`fastfi-ota.sh`)

Keep these behaviors; do not regress:

| Behavior | Purpose |
|----------|---------|
| `overlay_reclaim` | Drop backups, opkg lists, stale extracts, large logs — never wipe `/www/data` DBs |
| `overlay_code_in_upper` | Treat existing overlay code as in-place (need≈0) even if marker missing |
| Skip backup if free &lt; 256 KB | Backup must not block Apply on full overlays |
| `overlay_cp_tree` (rm-before-cp) | Avoid old+new peak headroom on in-place replaces |
| Marker only after **full** www+lua+libexec copy | Bootstrap must not set marker |
| `continue-full` | Pull `update-full.tar.gz` (fallback: `update.tar.gz`) |
| OTA is **`.tar.gz` only** | Never auto-select `.bin` (preserves `/www/data`) |

---

## Operator / customer expectations

1. Check for Updates → Apply (bootstrap).
2. Router reboots.
3. Wait 1–2 minutes for automatic full apply + second reboot.
4. Confirm `/www/version.txt` matches the release.
5. If stuck: `/tmp/ota-continue-full.log` or  
   `/usr/libexec/fastfi/core/fastfi-ota.sh continue-full`

---

## Agent quick reference

When the user says **create a release** / **new version**:

1. Read this doc + `.cursor/rules/koneksik-ota-release.mdc`.
2. Bump version → build **full then bootstrap** → build `.bin` → stage `releases/vX.Y.Z/` → `gh release create` with **both** tarballs.
3. Never publish a Latest release whose only `update.tar.gz` is the multi-MB full package (breaks tight overlays).
4. Do not flash production routers unless explicitly authorized.
5. Preserve KSK / RTR / Flash Auth / SET-HOLD / Autopause Grace Period (sec) unless the release’s change list says otherwise.

---

## Related paths

| Path | Role |
|------|------|
| `tools/make_ota_bootstrap.py` | Bootstrap tarball |
| `EXTRACTED-…/rootfs/make_archive.py` | Full tarball |
| `EXTRACTED-…/rootfs/usr/libexec/fastfi/core/fastfi-ota.sh` | OTA engine |
| `EXTRACTED-…/rootfs/etc/init.d/fastfi` | `ota_pending_full` hook |
| `tools/build-ruijie-wsl.ps1` | `.bin` ImageBuilder |
| `KonekSik-fi Piso Wifi Production/releases/v*/` | Staged artifacts |
