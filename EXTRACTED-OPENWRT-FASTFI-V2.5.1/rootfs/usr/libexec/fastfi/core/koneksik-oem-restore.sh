#!/bin/sh
# KonekSik OEM ReyeeOS restore — firmware MTD ONLY
# Usage: koneksik-oem-restore.sh <validated-rgos.bin>
# DO NOT flash from callers without prior validation receipt.

set -e
IMAGE="$1"
LOG="/tmp/fw_progress.log"
OEM_LOG() { echo "[OEM] $(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

if [ -z "$IMAGE" ] || [ ! -f "$IMAGE" ]; then
  OEM_LOG "Flash aborted: image missing"
  exit 1
fi

# Refuse encrypted/tar wrappers
MAGIC4=$(hexdump -v -n 4 -e '1/1 "%02x"' "$IMAGE" 2>/dev/null || true)
if [ "$MAGIC4" != "27051956" ]; then
  OEM_LOG "Flash aborted: not uImage (got $MAGIC4)"
  exit 1
fi

# Named partition only — never numeric /dev/mtdN guesses
PART="firmware"
MTD_LINE=$(awk -F: '/"firmware"/{print; exit}' /proc/mtd 2>/dev/null || true)
if [ -z "$MTD_LINE" ]; then
  OEM_LOG "Flash aborted: firmware MTD not found"
  exit 1
fi

MTD_SIZE_HEX=$(echo "$MTD_LINE" | awk '{print $2}')
MTD_SIZE=$(printf "%d" "0x$MTD_SIZE_HEX" 2>/dev/null || echo 0)
IMG_SIZE=$(wc -c < "$IMAGE" | tr -d ' ')

OEM_LOG "firmware MTD line: $MTD_LINE"
OEM_LOG "firmware size=$MTD_SIZE image size=$IMG_SIZE"

if [ "$MTD_SIZE" -le 0 ] || [ "$IMG_SIZE" -le 0 ] || [ "$IMG_SIZE" -gt "$MTD_SIZE" ]; then
  OEM_LOG "Flash aborted: size check failed"
  exit 1
fi

# Guard: refuse if caller accidentally pointed at protected names
case "$PART" in
  firmware) ;;
  *) OEM_LOG "Flash aborted: refusing partition $PART"; exit 1 ;;
esac

# Final safety: ensure protected partitions exist as separate named MTDs
for p in u-boot factory product_info; do
  if ! grep -q "\"$p\"" /proc/mtd 2>/dev/null; then
    OEM_LOG "Warning: partition $p not listed in /proc/mtd (continuing; DTS may differ)"
  fi
done

OEM_LOG "Flash target: firmware (named). Starting mtd write..."
OEM_LOG "NOTE: This replaces OpenWrt/KonekSik rootfs/kernel. Config is not migrated."

# Match upstream OpenWrt stock-revert guidance: mtd write to firmware, then reboot.
# -r requests reboot after write when supported by mtd utility.
if command -v mtd >/dev/null 2>&1; then
  sync
  if mtd -r write "$IMAGE" "$PART" >>"$LOG" 2>&1; then
    OEM_LOG "mtd write completed; reboot requested"
    exit 0
  fi
  OEM_LOG "mtd -r write failed; trying mtd write + reboot"
  mtd write "$IMAGE" "$PART" >>"$LOG" 2>&1
  sync
  OEM_LOG "Reboot requested"
  reboot -f
  exit 0
fi

OEM_LOG "Flash aborted: mtd utility not found"
exit 1
