#!/bin/bash
set -e

# FastFi V6 Ruijie EW1200G Pro image builder
# Runs inside WSL (Ubuntu) to produce a router firmware image.

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
# ImageBuilder requires a case-sensitive filesystem. /mnt/c is case-insensitive,
# so build in the WSL home directory and copy the result back.
WSL_BUILD_ROOT="$HOME/fastfi-build"
mkdir -p "$WSL_BUILD_ROOT"
cd "$WSL_BUILD_ROOT"

RELEASE="${RELEASE:-24.10.7}"
TARGET="${TARGET:-ramips}"
SUBTARGET="${SUBTARGET:-mt7621}"
IB_FILE="openwrt-imagebuilder-${RELEASE}-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.zst"
IB_URL="https://downloads.openwrt.org/releases/${RELEASE}/targets/${TARGET}/${SUBTARGET}/${IB_FILE}"
PROFILE="${PROFILE:-ruijie_rg-ew1200g-pro-v1.1}"

echo "[build] Release: $RELEASE"
echo "[build] Target:  $TARGET/$SUBTARGET"
echo "[build] Profile: $PROFILE"
echo "[build] Overlay: $REPO_ROOT"
echo "[build] Workspace: $WSL_BUILD_ROOT"

# Install prerequisites if missing
# NOTE: libncurses5-dev/libncursesw5-dev were dropped from Ubuntu 26.04;
# libncurses-dev is the current name. dosfstools/mtools/parted are needed by
# the ImageBuilder for FAT/ext4 image assembly (mkfs.fat, mcopy, parted).
for pkg in zstd unzip build-essential libncurses-dev zlib1g-dev gawk git gettext libssl-dev xsltproc rsync wget curl dosfstools mtools parted e2fsprogs python3 lua5.1 nodejs npm; do
    if ! dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        echo "[build] Installing $pkg..."
        sudo apt-get update -qq
        sudo apt-get install -y "$pkg" || true
    fi
done

# terser (real JS parser) for Tier 1 JS minification. Best-effort: if it can't
# be installed, fastfi-harden.py skips JS (it's client-visible anyway).
if ! command -v terser >/dev/null 2>&1; then
    echo "[build] Installing terser (npm -g)..."
    sudo npm install -g terser || true
fi

# Copy overlay into workspace (case-sensitive filesystem)
OVERLAY_DIR="$WSL_BUILD_ROOT/overlay"
rm -rf "$OVERLAY_DIR"
mkdir -p "$OVERLAY_DIR"
if [ ! -f "$IB_FILE" ]; then
    echo "[build] Downloading ImageBuilder..."
    wget -q --show-progress "$IB_URL" -O "$IB_FILE"
fi

# Extract if needed
IB_DIR="openwrt-imagebuilder-${RELEASE}-${TARGET}-${SUBTARGET}.Linux-x86_64"
if [ ! -d "$IB_DIR" ]; then
    echo "[build] Extracting ImageBuilder..."
    tar --zstd -xf "$IB_FILE"
fi

cd "$IB_DIR"

# Verify profile exists
if ! make info | grep -q "^${PROFILE}:"; then
    echo "[build] ERROR: Profile '$PROFILE' not found. Available profiles:"
    make info | grep -E "^[^ ]*:" | head -20
    exit 1
fi

PACKAGES="lua lsqlite3 sqlite3-cli curl jq uhttpd uhttpd-mod-ubus cgi-io nodogsplash openvpn-openssl kmod-nft-connlimit tc-tiny kmod-sched-core kmod-sched-cake kmod-ifb sqm-scripts dnsmasq ca-bundle coreutils-timeout ppp ppp-mod-pppoe kmod-pppoe"

# Sanitize PATH: remove any Windows entries that contain relative components like 'Files'.
# OpenWrt's find checks for insecure PATH entries.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Optional suffix to distinguish image variants
OUT_SUFFIX="${1:-}"
if [ -n "$OUT_SUFFIX" ]; then
    OUT_SUFFIX="-${OUT_SUFFIX}"
fi

echo "[build] Copying overlay to workspace..."
# Exclude build artifacts, outputs, VCS, and reference/working directories that
# are NOT part of the device rootfs. ojo-ref is the cloned ojopisowifi reference
# (~7400 files incl. .git) — sweeping it into the overlay exhausts the ext4
# rootfs inodes ("make_file: failed to allocate inode"). fastfi-coinslot is a
# scratch dir. Only FHS dirs (usr/etc/www/bin/...) belong in the image.
rsync -a "$REPO_ROOT/" "$OVERLAY_DIR/" \
    --exclude=build --exclude='*.img.gz*' --exclude='*.img.gz.sha256' \
    --exclude='build.log' --exclude='.git' \
    --exclude=ojo-ref --exclude=fastfi-coinslot --exclude=opiwork \
    --exclude=dist --exclude='*.spec' \
    --exclude=companion-app \
    --exclude='*.exe' \
    --exclude=update \
    --exclude=flasher \
    --exclude=fastfi-cloud \
    --exclude=tools \
    --exclude='*.tar.zst' --exclude='*.tar.gz' --exclude='*.bin' \
    --exclude='*.sha256' --exclude='*.log' --exclude='/*.png' \
    --exclude='/*.jpg' --exclude='*.md' --exclude='build-overlay-*' \
    --exclude='/*.bin.db' --exclude='/*.db' \
    --exclude='*.mp4' --exclude='*.pdf' \
    --exclude='/GCASH_SETUP_GUIDE.txt' \
    --exclude='/GCASH_SETUP_GUIDE.html' \
    --exclude='/INSTALLATION_GUIDE.html'
    # Operator-facing guides/tutorials live in the repo root (GCASH_SETUP_GUIDE.*,
    # INSTALLATION_GUIDE.*, INSTALLATION_GUIDE.*, *.mp4 tutorial videos) and must
    # NOT ship on router flash — they ballooned the rootfs past the 16 MB Ruijie
    # partition limit. They are excluded by EXPLICIT ROOT NAME, not by extension:
    #   - *.html CANNOT be blanket-excluded: www/*.html (admin.html, index.html,
    #     hotspot-detect.html, license.html) IS the device web UI and must ship.
    #   - *.txt CANNOT be blanket-excluded: www/version.txt (OTA version source)
    #     and www/connecttest.txt (captive-portal "Success" page) must ship.
    #   - *.mp4 / *.pdf ARE blanket-excluded: no legit copies exist anywhere
    #     under www/ etc/ usr/, so a recursive exclude is safe for those two.

# Apply variant-specific overlay on top of the base overlay.
if [ -n "$OUT_SUFFIX" ] && [ -d "$REPO_ROOT/build-overlay${OUT_SUFFIX}" ]; then
    echo "[build] Applying variant overlay: build-overlay${OUT_SUFFIX}"
    rsync -a "$REPO_ROOT/build-overlay${OUT_SUFFIX}/" "$OVERLAY_DIR/"
fi

# --- Source hardening: protect the shipped Lua/JS/CSS from trivial RE -------
# Without this, the .img.gz rootfs exposes the full commented Lua backend; a
# cloner reads the design notes, patches out the license check, rebrands. The
# cloud license is the real anti-clone anchor; this raises the RE cost so the
# check can't be trivially patched out.
#
# Runs ONLY against the overlay COPY ($OVERLAY_DIR) — the repo source tree stays
# fully readable for maintenance. The harden tools themselves are excluded from
# the rsync above (--exclude=tools) so they never ship in the image.
#
# Tier 1 (always on): strip comments/whitespace from Lua (validated by
# lua5.1 loadfile) + minify FastFi's own JS (terser, best-effort) + strip CSS.
echo "[build] Hardening overlay source (Tier 1: strip)..."
python3 "$REPO_ROOT/tools/fastfi-harden.py" "$OVERLAY_DIR"

# Tier 2 (opt-in via FASTFI_BYTECODE=1): byte-compile eligible Lua to
# non-human-readable bytecode with a host luac whose format matches the on-device
# OpenWrt lua (built+verified by build-luac-openwrt.sh). Bare-exec files
# (fastfi-gate.lua, fastfi-shaper.lua — invoked without an interpreter) stay
# source. Requires a test-boot on real hardware before shipping broadly; if it
# fails, fall back to Tier 1 only (omit FASTFI_BYTECODE).
if [ "${FASTFI_BYTECODE:-0}" = "1" ]; then
    echo "[build] Tier 2: byte-compiling Lua (FASTFI_BYTECODE=1)..."
    LUAC_HOST="$WSL_BUILD_ROOT/luac-host"
    bash "$REPO_ROOT/tools/build-luac-openwrt.sh"
    python3 "$REPO_ROOT/tools/fastfi-bytecode.py" "$OVERLAY_DIR" "$LUAC_HOST/luac"
fi

# Ensure all executable scripts remain executable regardless of Windows NTFS permissions.
find "$OVERLAY_DIR" -type f \( -path '*/uci-defaults/*' -o -path '*/init.d/*' -o -path '*/cgi-bin/*' -o -path '*/bin/*' -o -path '*/usr/libexec/fastfi/*' -o -name '*.sh' \) -exec chmod +x {} \;

# The OpenWrt imagebuilder reuses the assembled rootfs in build_dir/target-*/root-*
# across `make image` calls and does NOT reliably overwrite config files that are
# already present. Wipe the assembled rootfs so each build re-applies FILES fresh.
# Also delete any stale sysupgrade.bin for this profile in bin/targets — otherwise
# `make image` may leave the previous build's bin in place (Make sees it as
# up-to-date) and the script would copy that stale image under a new filename.
echo "[build] Cleaning assembled rootfs + stale output (force fresh FILES apply)..."
rm -rf build_dir/target-*/root-* 2>/dev/null || true
rm -f bin/targets/${TARGET}/${SUBTARGET}/*${PROFILE}*sysupgrade.bin 2>/dev/null || true
rm -f bin/targets/${TARGET}/${SUBTARGET}/*${PROFILE}*factory.bin 2>/dev/null || true
# Also clear this profile's package manifest + CycloneDX SBOM so the copy
# step below never ships a stale manifest from a prior build of the same
# profile (make image does not reliably overwrite metadata files).
rm -f bin/targets/${TARGET}/${SUBTARGET}/*${PROFILE}*.manifest 2>/dev/null || true
rm -f bin/targets/${TARGET}/${SUBTARGET}/*${PROFILE}*.bom.cdx.json 2>/dev/null || true

# Variant-apply diagnostic to a file: stdout is block-buffered and the early/middle
# echoes are dropped by the wsl.exe background-capture pipe, so a file is the only
# reliable way to verify which variant overlay was actually merged.
{
    echo "OUT_SUFFIX=${OUT_SUFFIX}"
    echo "variant dir $REPO_ROOT/build-overlay${OUT_SUFFIX} present: $([ -d "$REPO_ROOT/build-overlay${OUT_SUFFIX}" ] && echo yes || echo no)"
    echo "--- network br_lan/ports ---"; grep -nE 'br_lan|list ports|device .eth|wan' "$OVERLAY_DIR/etc/config/network" 2>/dev/null || true
} > "$WSL_BUILD_ROOT/last_overlay_diag.txt" 2>&1 || true

echo "[build] Building image..."
make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="$OVERLAY_DIR"

# Copy output image to repo root with a unique timestamp so builds are never overwritten.
BUILD_TS=$(date +%Y%m%d-%H%M%S)
OUTPUT=$(find bin/targets/${TARGET}/${SUBTARGET}/ -maxdepth 1 -name "*${PROFILE}*sysupgrade.bin" 2>/dev/null | head -n1)
if [ -z "$OUTPUT" ]; then
    OUTPUT=$(find bin/targets/${TARGET}/${SUBTARGET}/ -maxdepth 1 -name "*${PROFILE}*factory.bin" 2>/dev/null | head -n1)
fi
# DO NOT fall back to a bare "*${PROFILE}*" match: make image also writes a
# .manifest and .bom.cdx.json matching the profile name, and if the real
# sysupgrade/factory .bin was NOT produced (make image failed partway), that
# fallback would copy a ~20 KB manifest as the "firmware" and the script would
# falsely report success. A missing real image is a hard error.
if [ -z "$OUTPUT" ]; then
    echo "[build] ERROR: make image produced no sysupgrade.bin or factory.bin — build failed."
    echo "[build] bin/targets/${TARGET}/${SUBTARGET}/ contents:"
    ls -la bin/targets/${TARGET}/${SUBTARGET}/ || true
    exit 1
fi
# Sanity: a real EW1200G Pro image is several MB. A sub-1MB "image" is a
# manifest/metadata file, not firmware — refuse it rather than ship a broken bin.
IMG_SIZE=$(stat -c%s "$OUTPUT" 2>/dev/null || echo 0)
if [ "$IMG_SIZE" -lt 1048576 ]; then
    echo "[build] ERROR: output '$OUTPUT' is only ${IMG_SIZE} bytes — not a real firmware image. Aborting."
    exit 1
fi

echo "[build] Output: $OUTPUT"
CLEAN_PROFILE=$(echo "$PROFILE" | sed 's/_/-/g' | sed 's/d-team-//' | sed 's/ruijie-rg-//' | sed 's/-v1.1//')
OUT_NAME="fastfi-v6-${RELEASE}-${CLEAN_PROFILE}-${BUILD_TS}.bin"
cp "$OUTPUT" "$REPO_ROOT/$OUT_NAME"
echo "[build] Copied to: $REPO_ROOT/$OUT_NAME"
# Capture the imagebuilder targets dir while still inside $IB_DIR (absolute), so
# the manifest/SBOM copy below — which runs after `cd "$REPO_ROOT"` — can still
# locate the per-profile .manifest / .bom.cdx.json the imagebuilder just wrote.
# (Relative bin/targets/... would resolve against $REPO_ROOT after the cd and
# match nothing, silently skipping provenance sidecars.)
TARGETS_DIR="$(cd bin/targets/${TARGET}/${SUBTARGET} && pwd)"
cd "$REPO_ROOT"
sha256sum "$OUT_NAME" > "$OUT_NAME.sha256"
echo "[build] SHA256 written to $OUT_NAME.sha256"

# --- Manifest / SBOM plumbing ----------------------------------------------
# make image also writes a per-profile installed-package manifest
# (*${PROFILE}*-manifest) and a CycloneDX SBOM (*${PROFILE}*.bom.cdx.json).
# Copy them next to the .bin so every shipped variant carries its provenance
# alongside the image + sha256 (used by the build matrix + release inventory).
# Best-effort: NAND/factory-only profiles or partial builds may omit one.
for mtype in manifest bom.cdx.json; do
    MSRC=$(find "$TARGETS_DIR/" -maxdepth 1 -name "*${PROFILE}*${mtype}" 2>/dev/null | head -n1)
    if [ -n "$MSRC" ]; then
        cp "$MSRC" "$REPO_ROOT/${OUT_NAME}.${mtype}"
        echo "[build] Manifest copied to ${OUT_NAME}.${mtype}"
    else
        echo "[build] (no ${mtype} produced for this profile — skipped)"
    fi
done

echo "[build] Done."
