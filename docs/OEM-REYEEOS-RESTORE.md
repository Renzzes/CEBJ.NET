# OEM ReyeeOS Restore (KonekSik)

## Overview

Two independent firmware paths exist under **Firmware / OTA**:

| Path | Purpose | Mechanism |
|------|---------|-----------|
| **KonekSik Firmware** | Update KonekSik/OpenWrt | Existing `upload_firmware` → `sysupgrade -n` (unchanged) |
| **OEM Firmware — ReyeeOS** | Restore official Ruijie/Reyee | New `upload_oem_firmware` → validate → decrypt → `mtd write firmware` |

## Supported OEM formats

1. Official `.tar.gz` encrypto package (preferred), e.g. `EW_3.0(1)B11P313_*_encrypto.tar.gz`
2. Encrypted installer `*_install_encypto.bin` (magic `upgrade_crypt_v1!@2021`)
3. Decrypted `rgos.bin` / raw uImage (`0x27051956`) without OpenWrt metadata

OpenWrt/KonekSik sysupgrade images are **rejected** on the OEM path.

## Validation

Checks include: package members, Product ID `0x60010085`, `EW1200G-PRO` support_pids, package MD5, decryption, uImage magic, MIPS, size ≤ firmware MTD (`0xF70000`), optional known-good SHA-256.

## Flash target

**Named MTD partition `firmware` only.** Never numeric `/dev/mtdN` guesses. Never u-boot / factory / product_info / kdump.

Flash helper: `/usr/libexec/fastfi/core/koneksik-oem-restore.sh`

Command (lab only): `mtd -r write <validated-rgos.bin> firmware`

## Config behavior

OEM restore does **not** migrate KonekSik `/etc/config` or overlay into ReyeeOS. The firmware partition is replaced; OpenWrt overlay is discarded with the old rootfs. After reboot, expect ReyeeOS defaults (often `192.168.110.1`).

## Offline validator

```bat
py -3 tools\validate-oem-firmware.py "RG-EW1200G PRO Router ReyeeOS 1.313 firmware\EW_3.0(1)B11P313_EW1200GI_11240601_encrypto.tar.gz"
py -3 tools\test-oem-firmware-negative.py
```

## Evidence status

| Item | Status |
|------|--------|
| OEM package format / decrypt | **PROVEN** (static RE + offline round-trip to known rgos.bin) |
| Reyee web upgrade writes `firmware` | **PROVEN** (stock rootfs scripts) |
| KonekSik OEM path implementation | **STATICALLY VERIFIED** |
| Live `/proc/mtd` on production unit | **NOT YET VERIFIED** |
| Destructive OEM restore flash | **REQUIRES LAB TEST** — not executed |

## Recovery

If OEM flash fails to boot: use U-Boot Option 2 + TFTP with verified `rgos.bin` (previously proven recovery path).
