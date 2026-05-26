#!/usr/bin/env bash

set -euo pipefail

PASS_COUNT=0
WARN_COUNT=0

pass() {
    printf '[PASS] %s\n' "$1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

warn() {
    printf '[WARN] %s\n' "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

check_systemd_active() {
    local service="$1"
    if systemctl is-active --quiet "$service"; then
        pass "$service is active"
    else
        warn "$service is not active"
        systemctl --no-pager --full status "$service" || true
    fi
}

printf 'WMI post-boot verification\n'
printf '==========================\n'

if command -v xrandr >/dev/null 2>&1; then
    XRANDR_OUTPUT="$(xrandr --query 2>/dev/null || true)"
    if printf '%s\n' "$XRANDR_OUTPUT" | grep -q ' connected'; then
        pass "Display output detected via xrandr"
        printf '%s\n' "$XRANDR_OUTPUT" | awk '/ connected/{print "  " $0}'
    else
        warn "No connected display reported by xrandr"
    fi
else
    warn "xrandr is not available"
fi

if command -v libinput >/dev/null 2>&1; then
    LIBINPUT_OUTPUT="$(libinput list-devices 2>/dev/null || true)"
    if [ -n "$LIBINPUT_OUTPUT" ]; then
        pass "Input devices detected via libinput"
        printf '%s\n' "$LIBINPUT_OUTPUT" | awk '/Device:/{print "  " $0}'
    else
        warn "libinput returned no devices"
    fi
else
    warn "libinput is not available"
fi

if curl -fsSI http://localhost >/dev/null 2>&1; then
    pass "nginx/dashboard responds on http://localhost"
else
    warn "http://localhost did not respond successfully"
fi

check_systemd_active nginx
check_systemd_active wmi-bridge
check_systemd_active wmi-kiosk

if ls /dev/ttyACM* /dev/ttyUSB* >/dev/null 2>&1; then
    pass "ESP32 serial device is present"
    ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | sed 's/^/  /'
else
    warn "No ESP32 serial device was found under /dev/ttyACM* or /dev/ttyUSB*"
fi

printf '\nSummary: %s pass, %s warning\n' "$PASS_COUNT" "$WARN_COUNT"

if [ "$WARN_COUNT" -gt 0 ]; then
    exit 1
fi
