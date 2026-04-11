#!/usr/bin/env bash
# setup-precomf.sh - Install WMI dashboard stack on a Pi that already has
# a working display / touch / desktop setup. This script does NOT install
# display drivers or touch boot config changes.

set -euo pipefail

if [ "${EUID}" -eq 0 ]; then
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        RUN_USER="${SUDO_USER}"
    else
        echo "Please run this script as your normal user, not directly as root."
        echo "Example: ./setup-precomf.sh"
        exit 1
    fi
else
    RUN_USER="$(whoami)"
fi

RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"
if [ -z "$RUN_HOME" ] || [ ! -d "$RUN_HOME" ]; then
    echo "Could not determine home directory for user: $RUN_USER"
    exit 1
fi

echo "═══════════════════════════════════════════════════"
echo " WMI Dashboard — Preconfigured Screen Install"
echo "═══════════════════════════════════════════════════"
echo ""
echo "This installer assumes your display, touch drivers, framebuffer,"
echo "and desktop / X session are already working."
echo "It will only install the dashboard software stack."
echo ""

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIST="$REPO_DIR/dashboard/dist"
BRIDGE_SCRIPT="$REPO_DIR/bridge/serial_bridge.py"
VENV_DIR="$REPO_DIR/bridge/.venv"
SIM_VENV_DIR="$REPO_DIR/simulation/.venv"

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

install_nodejs_if_missing() {
    if need_cmd node && need_cmd npm; then
        return 0
    fi

    echo "Node.js not found. Installing NodeSource Node 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
}

ensure_pkg() {
    local pkg="$1"
    dpkg -s "$pkg" >/dev/null 2>&1
}

echo "[1/7] Installing system packages..."
sudo apt-get update -qq

PACKAGES=(
    python3-pip
    python3-venv
    nginx
    unclutter
    x11-xserver-utils
    xdotool
    git
    curl
)

# Chromium package name differs across Pi OS / Debian variants.
if ensure_pkg chromium; then
    :
elif ensure_pkg chromium-browser; then
    :
else
    if apt-cache show chromium >/dev/null 2>&1; then
        PACKAGES+=(chromium)
    else
        PACKAGES+=(chromium-browser)
    fi
fi

sudo apt-get install -y --no-install-recommends "${PACKAGES[@]}"

echo "[2/7] Setting up Python virtual environment for bridge..."
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install --quiet --upgrade pip
"$VENV_DIR/bin/pip" install --quiet -r "$REPO_DIR/bridge/requirements.txt"

echo "[3/7] Setting up Python virtual environment for simulation..."
if [ ! -d "$SIM_VENV_DIR" ]; then
    python3 -m venv "$SIM_VENV_DIR"
fi
"$SIM_VENV_DIR/bin/pip" install --quiet --upgrade pip
"$SIM_VENV_DIR/bin/pip" install --quiet -r "$REPO_DIR/simulation/requirements.txt"

echo "[4/7] Building dashboard..."
install_nodejs_if_missing
cd "$REPO_DIR/dashboard"
npm install --silent
npm run build
cd "$REPO_DIR"

echo "[5/7] Configuring nginx..."
sudo tee /etc/nginx/sites-available/wmi-dashboard >/dev/null <<SERVEREOF
server {
    listen 80 default_server;
    root $DASHBOARD_DIST;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
SERVEREOF

sudo ln -sf /etc/nginx/sites-available/wmi-dashboard /etc/nginx/sites-enabled/wmi-dashboard
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl enable --now nginx

echo "[6/7] Installing bridge and kiosk services..."

sudo tee /etc/systemd/system/wmi-bridge.service >/dev/null <<BRIDGEEOF
[Unit]
Description=WMI Serial Bridge (ESP32 ↔ Dashboard)
After=network.target

[Service]
ExecStart=$VENV_DIR/bin/python3 $BRIDGE_SCRIPT
Restart=on-failure
RestartSec=3
User=$RUN_USER
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
BRIDGEEOF

CHROMIUM_BIN=""
for candidate in /usr/bin/chromium-browser /usr/bin/chromium; do
    if [ -x "$candidate" ]; then
        CHROMIUM_BIN="$candidate"
        break
    fi
done
CHROMIUM_BIN="${CHROMIUM_BIN:-/usr/bin/chromium}"

sudo tee /etc/systemd/system/wmi-kiosk.service >/dev/null <<KIOSKEOF
[Unit]
Description=WMI Dashboard Kiosk (Chromium)
Wants=graphical.target
After=graphical.target wmi-bridge.service

[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=$RUN_HOME/.Xauthority
ExecStartPre=/bin/sleep 3
ExecStart=$CHROMIUM_BIN \
    --noerrdialogs \
    --disable-infobars \
    --kiosk \
    --no-first-run \
    --disable-translate \
    --disable-features=TranslateUI \
    --overscroll-history-navigation=0 \
    --touch-events=enabled \
    --force-device-scale-factor=1 \
    --window-size=480,320 \
    --disable-gpu \
    http://localhost
Restart=on-failure
RestartSec=5
User=$RUN_USER

[Install]
WantedBy=graphical.target
KIOSKEOF

sudo tee /etc/systemd/system/wmi-unclutter.service >/dev/null <<UNCLUTTEREOF
[Unit]
Description=Unclutter (hide mouse cursor)
After=graphical.target

[Service]
Environment=DISPLAY=:0
ExecStart=/usr/bin/unclutter -idle 1
Restart=always
User=$RUN_USER

[Install]
WantedBy=graphical.target
UNCLUTTEREOF

sudo systemctl daemon-reload
sudo systemctl enable --now wmi-bridge
sudo systemctl enable wmi-kiosk wmi-unclutter

echo "[7/7] Adding $RUN_USER to dialout group..."
sudo usermod -aG dialout "$RUN_USER"

echo ""
echo "═══════════════════════════════════════════════════"
echo " Preconfigured install complete"
echo "═══════════════════════════════════════════════════"
echo "nginx is live on: http://localhost"
echo "wmi-bridge is enabled and started now."
echo "wmi-kiosk and wmi-unclutter are enabled."
echo ""
echo "This script intentionally did NOT:"
echo "  - install LCD-show"
echo "  - touch /boot/config.txt"
echo "  - change framebuffer / display driver setup"
echo "  - alter graphical target defaults"
echo ""
echo "Recommended next commands:"
echo "  sudo systemctl status wmi-bridge"
echo "  sudo systemctl status wmi-kiosk"
echo "  sudo reboot"
