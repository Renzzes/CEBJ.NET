#!/bin/sh
# ---------------------------------------------------------------
# FastFi canonical device_id (MACHINE_ID) derivation helper.
#
# The device_id sent to FastFi Cloud MUST survive a reflash so keyless
# license recovery can match the device. NIC MACs are unreliable on
# single-Ethernet SBCs (Allwinner boards often generate a random MAC
# per boot), and the /etc/fastfi/machine_id cache that
# stabilises the MAC lives on the SD card and is wiped by a reflash.
# So we prefer a factory-burned hardware ID (Allwinner sunxi eFuse SID
# / SoC serial) which survives reflash. Once a device_id is cached it
# is never changed, so already-deployed devices keep their identity.
#
# KEEP IN SYNC with usr/lib/lua/fastfi/config.lua (find_stable_hw_id).
#
# Priority:
#   1. cached /etc/fastfi/machine_id        (preserves deployed devices)
#   2. product_info ASCII ethaddr           (Ruijie RG-EW1200G Pro / MT7621 — base
#      MAC is ASCII "ethaddr=" in the read-only product_info partition, NOT at
#      factory@0x4 which is MT7615 WiFi eeprom; board-correct & reflash-stable)
#   3. factory/caldata partition MAC @0x4   (ramips/MT7621 Newifi D2, ZBT-WG3526;
#      burned at factory, NEVER written by sysupgrade or breed/OEM recovery,
#      so survives a wipe flash deterministically)
#   4. Allwinner sunxi SID eFuse (binary->hex, survives reflash)
#   5. /sys/class/sunxi_info/chip_id        (text, some OpenWrt builds)
#   6. /proc/cpuinfo Serial                 (SoC serial)
#   7. first stable wired NIC MAC           (eth0/eth1/eth2/dynamic, excl. virtual)
#   8. fallback placeholder 000000000000
#
# WHY steps 2-3 exist: on MT7621 DSA the eth0 master conduit (step 7) can carry a
# PER-BOOT RANDOM MAC. A wipe flash (breed/OEM recovery) erases the step-1
# cache, so re-derivation would then return a DIFFERENT device_id every flash
# and keyless license recovery could never match the cloud binding. The
# product_info (step 2, Ruijie) and factory/caldata (step 3, Newifi/ZBT)
# partitions are the reflash-stable, boot-stable hardware IDs on these routers,
# so they are preferred over the volatile NIC MAC.
#
# Usage:   . /usr/libexec/fastfi/core/fastfi-machine-id.sh
#          MACHINE_ID=$(fastfi_machine_id)
# ---------------------------------------------------------------

fastfi_machine_id() {
    local id mid p nic dev wan_nic

    # 1. cached identity (never change an already-deployed device's id)
    if [ -f /etc/fastfi/machine_id ]; then
        id=$(cat /etc/fastfi/machine_id 2>/dev/null | tr -d ' \n\r' | tr 'a-z' 'A-Z')
        if [ -n "$id" ] && [ "$id" != "000000000000" ] && [ ${#id} -ge 4 ]; then
            printf '%s' "$id"
            return 0
        fi
    fi

    # 2. product_info ASCII base MAC — Ruijie RG-EW1200G Pro (MT7621) stores the
    # device base MAC as ASCII "ethaddr=AA:BB:CC:DD:EE:FF" in the read-only
    # "product_info" partition, NOT at factory@0x4 (which is MT7615 WiFi eeprom).
    # This is the board-correct, reflash-stable base MAC OpenWrt's own 02_network
    # uses (lan_mac=$(mtd_get_mac_ascii product_info ethaddr)). Prefer it so a
    # cache-wiping reflash on the SAME hardware re-derives the SAME id and
    # keyless license recovery can match the cloud binding. KEEP IN SYNC with
    # usr/lib/lua/fastfi/config.lua find_stable_hw_id. The mtdN device is parsed
    # with -F: (the first colon ends the "mtd2" device name); -F'"' would wrongly
    # yield "mtd2: 00020000 00020000 " and build an invalid /dev/mtdblock path.
    # Read the WHOLE partition (ethaddr can sit anywhere in it, not just the
    # first page) and grep for the ASCII "ethaddr=" token.
    PI_MTD=$(awk -F: '/"(product_info|product-info|productinfo)"/{print $1; exit}' /proc/mtd 2>/dev/null)
    if [ -n "$PI_MTD" ]; then
        id=$(dd if="/dev/mtdblock${PI_MTD#mtd}" bs=4096 2>/dev/null | tr -d '\0' | sed -n 's/.*ethaddr=\([0-9A-Fa-f:]\{17\}\).*/\1/p' | head -1)
        id=$(printf '%s' "$id" | tr -d ':' | tr 'a-z' 'A-Z')
        if [ -n "$id" ] && [ ${#id} -eq 12 ] && [ "$id" != "000000000000" ]; then
            mid="$id"
        fi
    fi

    # 3. Factory/caldata partition MAC @0x4 (reflash-stable on other MT7621
    # routers). ramips/MT7621 (Newifi D2, ZBT-WG3526) stores the device base MAC
    # at offset 0x4 of the "factory"/"caldata" partition — never written by
    # sysupgrade or breed/OEM recovery, so a wipe flash reproduces the same
    # value. Read directly from /dev/mtdblockN (found via /proc/mtd by label) to
    # avoid depending on which netdev got which MAC. NOT used on the Ruijie
    # EW1200G Pro once product_info above matched — its factory@0x4 is MT7615
    # WiFi eeprom, not the Ethernet base MAC, so guard on a still-empty mid.
    # KEEP IN SYNC with config.lua find_factory_mac. Parse mtdN with -F: (the
    # first colon ends "mtd3"); -F'"' would yield "mtd3: 00020000 00020000 " and
    # build an invalid /dev/mtdblock path, making this step a silent no-op.
    FACT_MTD=$(awk -F: '/"(factory|Factory|caldata|Caldata)"/{print $1; exit}' /proc/mtd 2>/dev/null)
    if [ -z "$mid" ] && [ -n "$FACT_MTD" ]; then
        id=$(dd if="/dev/mtdblock${FACT_MTD#mtd}" bs=1 skip=4 count=6 2>/dev/null | od -An -tx1 | tr -d ' \n' | tr 'a-z' 'A-Z')
        if [ -n "$id" ] && [ ${#id} -eq 12 ] && [ "$id" != "000000000000" ]; then
            mid="$id"
        fi
    fi

    # 4. Allwinner sunxi SID eFuse (factory chip ID, survives reflash)
    # Guarded on an empty $mid like steps 3/5/6/7 — without it this step
    # OVERWRITES an id already resolved by step 2 (product_info) or step 3
    # (factory/caldata), silently changing device_id on any board that exposes
    # both. This function must never change its answer for a given device.
    for p in /sys/bus/nvmem/devices/sunxi-sid0/nvmem /sys/bus/nvmem/devices/sunxi-sid/nvmem; do
        if [ -z "$mid" ] && [ -f "$p" ]; then
            id=$(od -An -tx1 -N16 "$p" 2>/dev/null | tr -d ' \n' | tr 'a-z' 'A-Z')
            if [ -n "$id" ] && [ ${#id} -ge 12 ] && [ "$id" != "00000000000000000000000000000000" ]; then
                mid="$id"; break
            fi
        fi
    done

    # 5. sunxi_info chip_id (text, some OpenWrt builds expose this)
    if [ -z "$mid" ] && [ -f /sys/class/sunxi_info/chip_id ]; then
        id=$(cat /sys/class/sunxi_info/chip_id 2>/dev/null | tr -d ' \n\r' | tr 'a-z' 'A-Z')
        if [ -n "$id" ] && [ ${#id} -ge 12 ] && [ "$id" != "000000000000" ]; then
            mid="$id"
        fi
    fi

    # 6. /proc/cpuinfo Serial (SoC serial)
    if [ -z "$mid" ]; then
        id=$(awk -F: '/^Serial/{v=$2; gsub(/[[:space:]]/,"",v); print v; exit}' /proc/cpuinfo 2>/dev/null | tr 'a-z' 'A-Z')
        if [ -n "$id" ] && [ ${#id} -ge 12 ] && [ "$id" != "000000000000" ]; then
            mid="$id"
        fi
    fi

    # 7. first stable wired NIC MAC (legacy fallback; unstable on random-MAC boards)
    if [ -z "$mid" ]; then
        for nic in eth0 eth1 eth2; do
            id=$(cat "/sys/class/net/$nic/address" 2>/dev/null | tr -d ':' | tr 'a-z' 'A-Z')
            if [ -n "$id" ] && [ "$id" != "000000000000" ]; then mid="$id"; break; fi
        done
        # dynamic scan, excluding virtual interfaces
        if [ -z "$mid" ]; then
            for dev in $(ls /sys/class/net 2>/dev/null); do
                case "$dev" in
                    lo|br-*|tun*|wlan*|wl*) continue ;;
                esac
                id=$(cat "/sys/class/net/$dev/address" 2>/dev/null | tr -d ':' | tr 'a-z' 'A-Z')
                if [ -n "$id" ] && [ "$id" != "000000000000" ]; then mid="$id"; break; fi
            done
        fi
        # fall back to the configured WAN NIC's MAC (e.g. USB Ethernet adapter)
        if [ -z "$mid" ]; then
            wan_nic=$(uci -q get network.wan.device 2>/dev/null)
            if [ -n "$wan_nic" ] && [ -f "/sys/class/net/$wan_nic/address" ]; then
                id=$(cat "/sys/class/net/$wan_nic/address" 2>/dev/null | tr -d ':' | tr 'a-z' 'A-Z')
                if [ -n "$id" ] && [ "$id" != "000000000000" ]; then mid="$id"; fi
            fi
        fi
    fi

    # 8. placeholder
    [ -z "$mid" ] && mid="000000000000"

    # Persist so all scripts agree and it survives reboots (a reflash wipes it,
    # but then the stable hardware ID above reproduces the same value).
    mkdir -p /etc/fastfi
    printf '%s' "$mid" > /etc/fastfi/machine_id

    printf '%s' "$mid"
}