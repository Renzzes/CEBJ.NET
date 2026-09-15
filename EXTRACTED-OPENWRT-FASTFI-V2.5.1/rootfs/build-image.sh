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
mkdir -p tmp
export TMPDIR="$PWD/tmp"

# Verify profile exists (write to file to avoid SIGPIPE/Broken pipe with grep -q)
make info > "$WSL_BUILD_ROOT/ib-info.txt" 2>&1 || true
if ! grep -q "^${PROFILE}:" "$WSL_BUILD_ROOT/ib-info.txt"; then
    echo "[build] ERROR: Profile '$PROFILE' not found. Available profiles:"
    grep -E "^[^ ]*:" "$WSL_BUILD_ROOT/ib-info.txt" | head -20
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
# ---------------------------------------------------------------------------
# Windows/NTFS symlink placeholders
# ---------------------------------------------------------------------------
# When FASTFI SquashFS is extracted on Windows, Unix symlinks become tiny
# regular files whose contents look like:
#   SYMLINK -> busybox
# (see ../symlinks.json).  ImageBuilder FILES= then overwrites the real
# package-provided symlinks with those placeholders, so the final SquashFS
# contains /bin/sh as ASCII text instead of a symlink — fatal on-device.
#
# /var was the only case previously restored (mkdir: Not a directory).
# Restore ALL placeholders here on the Linux overlay (WSL ext4) before
# `make image`. Prefer scanning content so we do not depend on a fixed list.
restore_symlink_placeholders() {
    local root="$1"
    local restored=0
    local f content target

    # Content-based restore (primary)
    while IFS= read -r -d '' f; do
        content=$(dd if="$f" bs=512 count=1 2>/dev/null | tr -d '\000' || true)
        case "$content" in
            "SYMLINK ->"*|"SYMLINK->"*)
                target=${content#SYMLINK ->}
                target=${target#SYMLINK->}
                # strip CR/LF/spaces
                target=$(printf '%s' "$target" | tr -d '\r\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                if [ -z "$target" ]; then
                    echo "[build] WARN: empty symlink target for $f — leaving as-is"
                    continue
                fi
                rm -f "$f"
                ln -s "$target" "$f"
                restored=$((restored + 1))
                ;;
        esac
    done < <(find "$root" -type f -size -512c -print0 2>/dev/null)

    # Optional JSON manifest (written next to rootfs during FASTFI extract)
    local manifest=""
    if [ -f "$REPO_ROOT/../symlinks.json" ]; then
        manifest="$REPO_ROOT/../symlinks.json"
    elif [ -f "$REPO_ROOT/symlinks.json" ]; then
        manifest="$REPO_ROOT/symlinks.json"
    fi
    if [ -n "$manifest" ] && command -v python3 >/dev/null 2>&1; then
        local json_restored
        json_restored=$(MANIFEST="$manifest" ROOT="$root" python3 - <<'PY'
import json, os
from pathlib import Path
root = Path(os.environ["ROOT"])
manifest = Path(os.environ["MANIFEST"])
n = 0
for e in json.loads(manifest.read_text(encoding="utf-8")):
    rel = e["path"].lstrip("/")
    target = e["target"]
    dest = root / rel
    if dest.is_symlink():
        continue
    if dest.exists() and dest.is_file():
        try:
            txt = dest.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        if not txt.startswith("SYMLINK"):
            # real file — do not clobber KonekSik customizations
            continue
        dest.unlink()
    elif dest.exists():
        continue
    dest.parent.mkdir(parents=True, exist_ok=True)
    os.symlink(target, dest)
    n += 1
print(n)
PY
)
        restored=$((restored + json_restored))
        echo "[build] symlinks.json pass restored/ensured: $json_restored"
    fi

    echo "[build] Restored $restored Windows SYMLINK placeholder(s) to real Unix symlinks"

    # Hard fail if any placeholders remain (would brick applets like /bin/sh)
    local leftover
    leftover=$(find "$root" -type f -size -512c -print0 2>/dev/null \
        | xargs -0 -r grep -l '^SYMLINK ->' 2>/dev/null || true)
    if [ -n "$leftover" ]; then
        echo "[build] ERROR: SYMLINK placeholder files still present in overlay:"
        echo "$leftover" | head -n 30
        exit 1
    fi

    # Sanity: critical paths must be symlinks after restore
    local crit
    for crit in bin/sh bin/ash bin/busybox usr/bin/env lib/ld-musl-mipsel-sf.so.1 etc/os-release; do
        if [ -e "$root/$crit" ] || [ -L "$root/$crit" ]; then
            if [ "$crit" = "bin/busybox" ]; then
                # busybox must be a real binary, not a symlink placeholder
                if [ -L "$root/$crit" ]; then
                    echo "[build] ERROR: $crit unexpectedly a symlink"
                    exit 1
                fi
            else
                if [ ! -L "$root/$crit" ]; then
                    echo "[build] ERROR: expected symlink at overlay /$crit"
                    ls -la "$root/$crit" 2>/dev/null || true
                    exit 1
                fi
            fi
        fi
    done
}

# Windows extracts OpenWrt /var symlink as a tiny regular file. That makes
# prepare_rootfs fail with: mkdir: Not a directory
if [ -e "$OVERLAY_DIR/var" ] && [ ! -d "$OVERLAY_DIR/var" ] && [ ! -L "$OVERLAY_DIR/var" ]; then
    echo "[build] Fixing overlay /var (was a file; restoring symlink to tmp)"
    rm -f "$OVERLAY_DIR/var"
fi
if [ ! -e "$OVERLAY_DIR/var" ] && [ ! -L "$OVERLAY_DIR/var" ]; then
    ln -s tmp "$OVERLAY_DIR/var"
fi
# Ensure /tmp exists as a directory in overlay (OpenWrt expects it)
if [ -e "$OVERLAY_DIR/tmp" ] && [ ! -d "$OVERLAY_DIR/tmp" ]; then
    rm -f "$OVERLAY_DIR/tmp"
fi
mkdir -p "$OVERLAY_DIR/tmp"

echo "[build] Restoring Unix symlinks mangled by Windows extraction..."
restore_symlink_placeholders "$OVERLAY_DIR"

# Drop host-side junk that must not land in router rootfs
rm -rf "$OVERLAY_DIR/.claude" "$OVERLAY_DIR/__pycache__" \
    "$OVERLAY_DIR/fastfi-coinslot-lanbase" 2>/dev/null || true
rm -f "$OVERLAY_DIR"/build-image.sh "$OVERLAY_DIR"/luacheck.py \
    "$OVERLAY_DIR"/make_archive.py "$OVERLAY_DIR"/migrate.sh \
    "$OVERLAY_DIR"/*.manifest "$OVERLAY_DIR"/*.bom.cdx.json \
    "$OVERLAY_DIR"/.gitattributes "$OVERLAY_DIR"/.gitignore 2>/dev/null || true

# Tier 1 harden is optional — tools/ may be absent in this tree.
if [ -f "$REPO_ROOT/tools/fastfi-harden.py" ]; then
    echo "[build] Hardening overlay source (Tier 1: strip)..."
    python3 "$REPO_ROOT/tools/fastfi-harden.py" "$OVERLAY_DIR"
else
    echo "[build] Skipping harden (tools/fastfi-harden.py not found)"
fi

# Tier 2 (opt-in via FASTFI_BYTECODE=1)
if [ "${FASTFI_BYTECODE:-0}" = "1" ] && [ -f "$REPO_ROOT/tools/fastfi-bytecode.py" ]; then
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
rm -rf build_dir/target-*/root-*-* 2>/dev/null || true
# Also wipe any leftover TARGET_DIR_ORIG copies
find build_dir -maxdepth 2 -type d -name 'root-*' -exec rm -rf {} + 2>/dev/null || true
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
