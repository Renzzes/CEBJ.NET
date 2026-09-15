#!/bin/sh
# FastFi SQM Atomic Applier v6 - WAN-targeted
ENABLED="$1"
DOWNLOAD="$2"
UPLOAD="$3"
IFACE="$4"

# Set internal values
[ "$ENABLED" = "1" ] && SQM_VAL="1" || SQM_VAL="0"

# Resolve the actual WAN device so this follows the router if the operator
# switches to VLAN mode. Do NOT write to eth0/eth1/wan blindly: shaping both the
# LAN and WAN NIC applies cake twice to the same traffic, each at the full rate.
WAN_DEV="$(/sbin/uci -q get network.wan.device)"
[ -z "$WAN_DEV" ] && WAN_DEV="$IFACE"
[ -z "$WAN_DEV" ] && WAN_DEV="eth0"

# Drop every stale sqm section left behind by the old multi-target write.
for _s in $(/sbin/uci -q show sqm 2>/dev/null | sed -n 's/^sqm\.\([^.=]*\)=queue$/\1/p'); do
    /sbin/uci -q delete "sqm.${_s}"
done

/sbin/uci set sqm."$WAN_DEV"=queue
/sbin/uci set sqm."$WAN_DEV".interface="$WAN_DEV"
/sbin/uci set sqm."$WAN_DEV".enabled="$SQM_VAL"        # 1 or 0 — NEVER 'on'
/sbin/uci set sqm."$WAN_DEV".download="$DOWNLOAD"
/sbin/uci set sqm."$WAN_DEV".upload="$UPLOAD"
/sbin/uci set sqm."$WAN_DEV".qdisc='cake'
/sbin/uci set sqm."$WAN_DEV".script='piece_of_cake.qos'
/sbin/uci set sqm."$WAN_DEV".linklayer='none'
/sbin/uci commit sqm
/bin/sync

# Detailed diagnostic log
echo "$(date): SQM APPLY (WAN_DEV=$WAN_DEV) - Enabled: $ENABLED, DL: $DOWNLOAD, UL: $UPLOAD" > /tmp/sqm_last_apply
/sbin/uci show sqm >> /tmp/sqm_last_apply

# Signal background restart
touch /tmp/fastfi_sqm_restart_pending
exit 0
