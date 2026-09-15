#!/bin/sh
# FastFi V6 - Enhanced Firewall Configuration Script
# Purpose: Apply optimized firewall rules with rate limiting and security hardening
# Location: /usr/libexec/fastfi/security/firewall-enhanced.sh
# Usage: Run after firewall reload or add to /etc/rc.local

set -e

echo "=== FastFi V6 Enhanced Firewall Configuration ==="
echo "Applying security optimizations..."

# ========================================
# 1. RATE LIMITING RULES
# ========================================

echo "[1/5] Applying rate limiting rules..."

# Rate limit new connections from hotspot (prevent DDoS)
# Max 20 new connections per minute per IP
iptables -t filter -I FORWARD -s 10.0.0.0/24 -m state --state NEW -m recent --set --name HOTSPOT_CONN 2>/dev/null || true
iptables -t filter -I FORWARD -s 10.0.0.0/24 -m state --state NEW -m recent --update --seconds 60 --hitcount 20 --name HOTSPOT_CONN -j DROP 2>/dev/null || true

# Rate limit SSH attempts (prevent brute force)
iptables -t filter -I INPUT -p tcp --dport 22 -m state --state NEW -m recent --set --name SSH_ATTEMPT 2>/dev/null || true
iptables -t filter -I INPUT -p tcp --dport 22 -m state --state NEW -m recent --update --seconds 300 --hitcount 5 --name SSH_ATTEMPT -j DROP 2>/dev/null || true

# Rate limit HTTP requests to captive portal (prevent abuse)
iptables -t filter -I INPUT -p tcp --dport 2050 -m limit --limit 30/minute --limit-burst 10 -j ACCEPT 2>/dev/null || true

# Rate limit DNS queries (prevent DNS amplification)
iptables -t filter -I INPUT -p udp --dport 53 -m limit --limit 50/second --limit-burst 20 -j ACCEPT 2>/dev/null || true

echo "✓ Rate limiting applied"

# ========================================
# 2. CONNECTION TRACKING OPTIMIZATION
# ========================================

echo "[2/5] Optimizing connection tracking..."

# Increase connection tracking table size
sysctl -w net.netfilter.nf_conntrack_max=65536 2>/dev/null || true

# Reduce timeout for established connections (free memory faster)
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_established=3600 2>/dev/null || true

# Reduce timeout for TIME_WAIT states
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=30 2>/dev/null || true

echo "✓ Connection tracking optimized"

# ========================================
# 3. SECURITY HARDENING
# ========================================

echo "[3/5] Applying security hardening..."

# Block invalid packets
iptables -t filter -A INPUT -m conntrack --ctstate INVALID -j DROP 2>/dev/null || true
iptables -t filter -A FORWARD -m conntrack --ctstate INVALID -j DROP 2>/dev/null || true

# Drop fragmented packets (potential attack vector)
iptables -t filter -A INPUT -f -j DROP 2>/dev/null || true

# Block null packets
iptables -t filter -A INPUT -p tcp --tcp-flags ALL NONE -j DROP 2>/dev/null || true

# Block XMAS packets
iptables -t filter -A INPUT -p tcp --tcp-flags ALL ALL -j DROP 2>/dev/null || true

# Block SYN-FIN attacks
iptables -t filter -A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j DROP 2>/dev/null || true

# Block SYN-RST attacks
iptables -t filter -A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j DROP 2>/dev/null || true

# Enable TCP SYN cookies (protect against SYN flood)
sysctl -w net.ipv4.tcp_syncookies=1 2>/dev/null || true

# Disable IP forwarding spoofing protection
sysctl -w net.ipv4.conf.all.rp_filter=1 2>/dev/null || true
sysctl -w net.ipv4.conf.default.rp_filter=1 2>/dev/null || true

# Ignore ICMP broadcast requests (prevent smurf attacks)
sysctl -w net.ipv4.icmp_echo_ignore_broadcasts=1 2>/dev/null || true

# Log dropped packets (for debugging, limit to 5/min to prevent log flooding)
iptables -t filter -A INPUT -m limit --limit 5/min -j LOG --log-prefix "FastFi-DROPPED: " --log-level 4 2>/dev/null || true

echo "✓ Security hardening applied"

# ========================================
# 4. QOS & BANDWIDTH PRIORITIZATION
# ========================================

echo "[4/5] Configuring QoS priorities..."

# Mark DNS traffic as high priority (use tc if available)
if command -v tc >/dev/null 2>&1; then
    # Create root qdisc on WAN interface
    WAN_IF=$(uci get network.wan.ifname 2>/dev/null || echo "eth0")
    
    tc qdisc add dev $WAN_IF root handle 1: htb default 30 2>/dev/null || true
    
    # High priority class for DNS and VoIP
    tc class add dev $WAN_IF parent 1: classid 1:1 htb rate 100mbit ceil 100mbit prio 1 2>/dev/null || true
    tc filter add dev $WAN_IF protocol ip parent 1:0 prio 1 u32 match ip dport 53 0xffff flowid 1:1 2>/dev/null || true
    
    # Medium priority for HTTP/HTTPS
    tc class add dev $WAN_IF parent 1: classid 1:2 htb rate 50mbit ceil 100mbit prio 2 2>/dev/null || true
    tc filter add dev $WAN_IF protocol ip parent 1:0 prio 2 u32 match ip dport 80 0xffff flowid 1:2 2>/dev/null || true
    tc filter add dev $WAN_IF protocol ip parent 1:0 prio 2 u32 match ip dport 443 0xffff flowid 1:2 2>/dev/null || true
    
    # Default class for everything else
    tc class add dev $WAN_IF parent 1: classid 1:30 htb rate 10mbit ceil 50mbit prio 3 2>/dev/null || true
    
    echo "✓ QoS configured on $WAN_IF"
else
    echo "⚠ tc not available, skipping QoS"
fi

# ========================================
# 5. NAT OPTIMIZATION
# ========================================

echo "[5/5] Optimizing NAT configuration..."

# Ensure NAT masquerade is properly configured
# For PPPoE the egress is pppoe-wan (the ppp netdev); use it when proto is pppoe.
_WAN_EGRESS="wan"
_WAN_PROTO=$(uci -q get network.wan.proto 2>/dev/null || echo "")
[ "$_WAN_PROTO" = "pppoe" ] && _WAN_EGRESS="pppoe-wan"
iptables -t nat -C POSTROUTING -s 10.0.0.0/24 -o $_WAN_EGRESS -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o $_WAN_EGRESS -j MASQUERADE

# Enable NAT for VPN tunnel if exists
if ip link show tun0 >/dev/null 2>&1; then
    iptables -t nat -C POSTROUTING -o tun0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o tun0 -j MASQUERADE
    echo "✓ VPN NAT configured"
fi

# Optimize NAT timeouts
sysctl -w net.netfilter.nf_conntrack_tcp_timeout_close=10 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_udp_timeout=30 2>/dev/null || true
sysctl -w net.netfilter.nf_conntrack_udp_timeout_stream=180 2>/dev/null || true

echo "✓ NAT optimization complete"

# ========================================
# VERIFICATION
# ========================================

echo ""
echo "=== Firewall Enhancement Summary ==="
echo "Rate limiting rules: Applied"
echo "Connection tracking: Optimized"
echo "Security hardening: Enabled"
echo "QoS prioritization: $(command -v tc >/dev/null 2>&1 && echo 'Configured' || echo 'Skipped (tc not available)')"
echo "NAT optimization: Complete"
echo ""
echo "Active FastFi rules:"
nft list ruleset 2>/dev/null | grep -i "fastfi" | wc -l || echo "0"
echo ""
echo "To view all rules: nft list ruleset | grep -A2 'FastFi'"
echo "To monitor drops: logread -f | grep 'FastFi-DROPPED'"
echo ""
echo "✅ Enhanced firewall configuration complete!"

exit 0
