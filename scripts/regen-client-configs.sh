#!/bin/bash
#
# regen-client-configs.sh
# Regenerates xray-client.json and singbox-client.json for an existing client.
# Called by `swizguard regen` — reuses existing WG keys and tunnel IPs.
#
# Environment variables expected (sourced from credentials.env + client dir):
#   CLIENT_NAME, CLIENT_IPV4, CLIENT_IPV6, CLIENT_WG_PRIVKEY, CLIENT_DIR
#   SERVER_IP, XRAY_PORT, WG_PORT, CLIENT_UUID, CAMOUFLAGE_DEST
#   REALITY_PUBLIC_KEY, SERVER_WG_PUBLIC_KEY
#
# Optional (set in /etc/swizguard/credentials.env), for home-network hostnames
# that only your own DNS server knows about:
#   LAB_DOMAINS  space/comma-separated domains, e.g. "home.example lab.example"
#   LAB_DNS      IPv4 address of the DNS server that answers for them

set -euo pipefail

: "${CLIENT_NAME:?CLIENT_NAME required}"
: "${CLIENT_IPV4:?CLIENT_IPV4 required}"
: "${CLIENT_IPV6:?CLIENT_IPV6 required}"
: "${CLIENT_WG_PRIVKEY:?CLIENT_WG_PRIVKEY required}"
: "${CLIENT_DIR:?CLIENT_DIR required}"
: "${SERVER_IP:?SERVER_IP required}"
: "${XRAY_PORT:?XRAY_PORT required}"
: "${WG_PORT:?WG_PORT required}"
: "${CLIENT_UUID:?CLIENT_UUID required}"
: "${CAMOUFLAGE_DEST:?CAMOUFLAGE_DEST required}"
: "${REALITY_PUBLIC_KEY:?REALITY_PUBLIC_KEY required}"
: "${SERVER_WG_PUBLIC_KEY:?SERVER_WG_PUBLIC_KEY required}"

# ─── Xray DNS (split DNS for LAB_DOMAINS, DoH for everything else) ─
# All DNS that apps send through socks-in is answered by Xray's DNS module;
# every query it makes goes through the tunnel (dns-internal -> wireguard-out).
XRAY_DNS_SERVERS='"https://1.1.1.1/dns-query"'
LAB_DOMAINS="${LAB_DOMAINS:-}"
LAB_DNS="${LAB_DNS:-}"
if [ -n "$LAB_DOMAINS" ] || [ -n "$LAB_DNS" ]; then
    [ -n "$LAB_DOMAINS" ] && [ -n "$LAB_DNS" ] || { echo "LAB_DOMAINS and LAB_DNS must be set together" >&2; exit 1; }
    [[ "$LAB_DNS" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || { echo "LAB_DNS must be an IPv4 address (got: $LAB_DNS)" >&2; exit 1; }
    lab_list=""
    for d in ${LAB_DOMAINS//,/ }; do
        [[ "$d" =~ ^[A-Za-z0-9.-]+$ ]] || { echo "Invalid domain in LAB_DOMAINS: $d" >&2; exit 1; }
        lab_list+="${lab_list:+, }\"domain:${d}\""
    done
    XRAY_DNS_SERVERS="{ \"address\": \"${LAB_DNS}\", \"domains\": [${lab_list}], \"skipFallback\": true },
            ${XRAY_DNS_SERVERS}"
fi

# ─── Xray client config ──────────────────────────────────────────
cat > "$CLIENT_DIR/xray-client.json" <<XCEOF
{
    "log": {
        "loglevel": "warning"
    },
    "dns": {
        "tag": "dns-internal",
        "queryStrategy": "UseIPv4",
        "servers": [
            ${XRAY_DNS_SERVERS}
        ],
        "disableFallbackIfMatch": true
    },
    "inbounds": [
        {
            "tag": "socks-in",
            "listen": "127.0.0.1",
            "port": 10808,
            "protocol": "socks",
            "settings": {
                "udp": true,
                "auth": "noauth"
            },
            "sniffing": {
                "enabled": true,
                "destOverride": ["http", "tls"]
            }
        },
        {
            "tag": "http-in",
            "listen": "127.0.0.1",
            "port": 10809,
            "protocol": "http"
        }
    ],
    "outbounds": [
        {
            "tag": "wireguard-out",
            "protocol": "wireguard",
            "settings": {
                "secretKey": "${CLIENT_WG_PRIVKEY}",
                "address": ["${CLIENT_IPV4}/32", "${CLIENT_IPV6}/128"],
                "peers": [
                    {
                        "publicKey": "${SERVER_WG_PUBLIC_KEY}",
                        "endpoint": "127.0.0.1:${WG_PORT}",
                        "allowedIPs": ["0.0.0.0/0", "::/0"],
                        "keepAlive": 25
                    }
                ],
                "mtu": 1280,
                "noKernelTun": true
            },
            "streamSettings": {
                "sockopt": {
                    "dialerProxy": "proxy"
                }
            }
        },
        {
            "tag": "proxy",
            "protocol": "vless",
            "settings": {
                "vnext": [
                    {
                        "address": "${SERVER_IP}",
                        "port": ${XRAY_PORT},
                        "users": [
                            {
                                "id": "${CLIENT_UUID}",
                                "encryption": "none",
                                "flow": "xtls-rprx-vision"
                            }
                        ]
                    }
                ]
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "show": false,
                    "fingerprint": "chrome",
                    "serverName": "${CAMOUFLAGE_DEST}",
                    "publicKey": "${REALITY_PUBLIC_KEY}",
                    "shortId": "${SHORT_ID:-}",
                    "spiderX": ""
                }
            }
        },
        {
            "tag": "dns-out",
            "protocol": "dns"
        },
        {
            "tag": "direct",
            "protocol": "freedom"
        }
    ],
    "routing": {
        "rules": [
            {
                "type": "field",
                "inboundTag": ["socks-in"],
                "network": "udp",
                "port": "53",
                "outboundTag": "dns-out"
            },
            {
                "type": "field",
                "inboundTag": ["dns-internal"],
                "outboundTag": "wireguard-out"
            },
            {
                "type": "field",
                "inboundTag": ["socks-in", "http-in"],
                "outboundTag": "wireguard-out"
            }
        ]
    }
}
XCEOF

# ─── Sing-box client config ──────────────────────────────────────
cat > "$CLIENT_DIR/singbox-client.json" <<SBEOF
{
    "log": {
        "level": "warning",
        "timestamp": true
    },
    "dns": {
        "servers": [
            {
                "type": "https",
                "tag": "dns-remote",
                "server": "1.1.1.1",
                "detour": "proxy"
            }
        ],
        "final": "dns-remote",
        "strategy": "prefer_ipv4"
    },
    "inbounds": [
        {
            "type": "tun",
            "tag": "tun-in",
            "address": ["172.19.0.1/30", "fdfe:dcba:9876::1/126"],
            "mtu": 9000,
            "auto_route": true,
            "stack": "system",
            "platform": {
                "http_proxy": {
                    "enabled": false
                }
            }
        }
    ],
    "outbounds": [
        {
            "type": "vless",
            "tag": "proxy",
            "server": "${SERVER_IP}",
            "server_port": ${XRAY_PORT},
            "uuid": "${CLIENT_UUID}",
            "flow": "xtls-rprx-vision",
            "network": "tcp",
            "packet_encoding": "xudp",
            "tls": {
                "enabled": true,
                "server_name": "${CAMOUFLAGE_DEST}",
                "utls": {
                    "enabled": true,
                    "fingerprint": "chrome"
                },
                "reality": {
                    "enabled": true,
                    "public_key": "${REALITY_PUBLIC_KEY}",
                    "short_id": "${SHORT_ID:-}"
                }
            }
        },
        {
            "type": "direct",
            "tag": "direct"
        }
    ],
    "endpoints": [
        {
            "type": "wireguard",
            "tag": "wg-out",
            "system": false,
            "mtu": 1280,
            "address": ["${CLIENT_IPV4}/32", "${CLIENT_IPV6}/128"],
            "private_key": "${CLIENT_WG_PRIVKEY}",
            "peers": [
                {
                    "address": "127.0.0.1",
                    "port": ${WG_PORT},
                    "public_key": "${SERVER_WG_PUBLIC_KEY}",
                    "allowed_ips": ["0.0.0.0/0", "::/0"],
                    "persistent_keepalive_interval": 25
                }
            ],
            "detour": "proxy"
        }
    ],
    "route": {
        "rules": [
            {
                "action": "sniff"
            },
            {
                "protocol": "dns",
                "action": "hijack-dns"
            },
            {
                "ip_is_private": true,
                "action": "route",
                "outbound": "direct"
            },
            {
                "inbound": "tun-in",
                "action": "route",
                "outbound": "wg-out"
            }
        ],
        "final": "wg-out",
        "auto_detect_interface": true
    }
}
SBEOF

# Regenerate the launcher script too, so existing clients pick up upstream
# fixes (auto-detect interface, multi-network cleanup, safety checks) without
# requiring a fresh `swizguard add`.
SCRIPT_BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
bash "$SCRIPT_BASE_DIR/_generate-launcher.sh"

# Defensive: ensure private.key is always 600 even if previously loosened.
if [ -f "$CLIENT_DIR/private.key" ]; then chmod 600 "$CLIENT_DIR/private.key"; fi
