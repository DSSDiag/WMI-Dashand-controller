#!/usr/bin/env bash
# pi-setup.sh — One-shot setup for Raspberry Pi Zero 2 W
# ========================================================
# Run as the default 'pi' user (sudo is called internally where needed).
# Installs:
#   • nginx (serves the built React dashboard)
#   • Python serial bridge as a systemd service
#   • Chromium in kiosk mode as a systemd service
#   • Unclutter (hides mouse cursor after inactivity)
#
# Usage:
#   chmod +x pi-setup.sh && ./pi-setup.sh

set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIST="$REPO_DIR/dashboard/dist"
BRIDGE_SCRIPT="$REPO_DIR/bridge/serial_bridge.py"

echo "═══════════════════════════════════════════════════"
echo " WMI Dashboard — Raspberry Pi Setup"
echo " Repo: $REPO_DIR"
echo "═══════════════════════════════════════════════════"

# ── System packages ────────────────────────────────────────────────────────────
echo "[1/7] Installing system packages…"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    python3-pip python3-venv \
    nginx \
    chromium-browser \
    unclutter \
    x11-xserver-utils \
    xdotool \
    2>/dev/null || true

# ── Python virtual environment for the bridge ─────────────────────────────────
echo "[2/7] Setting up Python virtual environment…"
VENV_DIR="$REPO_DIR/bridge/.venv"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --quiet -r "$REPO_DIR/bridge/requirements.txt"

# ── Build React dashboard (if not already built) ──────────────────────────────
echo "[3/7] Building dashboard…"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
cd "$REPO_DIR/dashboard" && npm install --silent && npm run build
cd "$REPO_DIR"

# ── nginx config ──────────────────────────────────────────────────────────────
echo "[4/7] Configuring nginx…"
sudo tee /etc/nginx/sites-available/wmi-dashboard > /dev/null << EOF
server {
    listen 80 default_server;
    root $DASHBOARD_DIST;
    index index.html;
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
sudo ln -sf /etc/nginx/sites-available/wmi-dashboard /etc/nginx/sites-enabled/wmi-dashboard
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl enable --now nginx

# ── systemd service: serial bridge ────────────────────────────────────────────
echo "[5/7] Installing wmi-bridge systemd service…"
sudo tee /etc/systemd/system/wmi-bridge.service > /dev/null << EOF
[Unit]
Description=WMI Serial Bridge (ESP32 ↔ Dashboard)
After=network.target

[Service]
ExecStart=$VENV_DIR/bin/python3 $BRIDGE_SCRIPT
Restart=on-failure
RestartSec=3
User=$(whoami)
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now wmi-bridge

# ── systemd service: Chromium kiosk ───────────────────────────────────────────
echo "[6/7] Installing wmi-kiosk systemd service…"
sudo tee /etc/systemd/system/wmi-kiosk.service > /dev/null << EOF
[Unit]
Description=WMI Dashboard Kiosk (Chromium)
Wants=graphical.target
After=graphical.target wmi-bridge.service

[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/$(whoami)/.Xauthority
ExecStartPre=/bin/sleep 3
ExecStart=/usr/bin/chromium-browser \\
    --noerrdialogs \\
    --disable-infobars \\
    --kiosk \\
    --no-first-run \\
    --disable-translate \\
    --disable-features=TranslateUI \\
    --overscroll-history-navigation=0 \\
    --touch-events=enabled \\
    http://localhost
Restart=on-failure
RestartSec=5
User=$(whoami)

[Install]
WantedBy=graphical.target
EOF

# Hide the mouse cursor after 1 second of inactivity
sudo tee /etc/systemd/system/wmi-unclutter.service > /dev/null << EOF
[Unit]
Description=Unclutter (hide mouse cursor)
After=graphical.target

[Service]
Environment=DISPLAY=:0
ExecStart=/usr/bin/unclutter -idle 1
Restart=always
User=$(whoami)

[Install]
WantedBy=graphical.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable wmi-kiosk wmi-unclutter

# ── User serial port permission ────────────────────────────────────────────────
echo "[7/7] Adding $(whoami) to dialout group (serial port access)…"
sudo usermod -aG dialout "$(whoami)"

echo ""
echo "═══════════════════════════════════════════════════"
echo " Setup complete! Please reboot to start the kiosk:"
echo "   sudo reboot"
echo "═══════════════════════════════════════════════════"
