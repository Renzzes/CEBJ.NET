#!/bin/sh

allow_vpn_tunnel() {
    # Allow HTTP/HTTPS from VPN tunnel (tun0) for remote access
    # Check before adding to prevent duplicate rules accumulating
    nft list chain inet fw4 input 2>/dev/null | grep -q 'iifname "tun0" tcp dport 80 accept' || \
        nft insert rule inet fw4 input iifname "tun0" tcp dport 80 accept 2>/dev/null
    nft list chain inet fw4 input 2>/dev/null | grep -q 'iifname "tun0" tcp dport 443 accept' || \
        nft insert rule inet fw4 input iifname "tun0" tcp dport 443 accept 2>/dev/null
}
