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
echo "[1/8] Installing system packages…"
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
echo "[2/8] Setting up Python virtual environment…"
VENV_DIR="$REPO_DIR/bridge/.venv"
python3 -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --quiet -r "$REPO_DIR/bridge/requirements.txt"

# ── Build React dashboard (if not already built) ──────────────────────────────
echo "[3/8] Building dashboard…"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
cd "$REPO_DIR/dashboard" && npm install --silent && npm run build
cd "$REPO_DIR"

# ── nginx config ──────────────────────────────────────────────────────────────
echo "[4/8] Configuring nginx…"
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

# ── Display Configuration (Waveshare 3.5" GPIO) ──────────────────────────────
echo "[5/8] Configuring GPIO Display (/boot/config.txt)…"
if [ -f /boot/firmware/config.txt ]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    BOOT_CONFIG="/boot/config.txt"
else
    echo "Warning: could not find config.txt to configure display"
    BOOT_CONFIG=""
fi

if [ -n "$BOOT_CONFIG" ]; then
    # Enable SPI and I2C if not already enabled
    sudo sed -i 's/^#dtparam=spi=on/dtparam=spi=on/' "$BOOT_CONFIG"
    sudo sed -i 's/^#dtparam=i2c_arm=on/dtparam=i2c_arm=on/' "$BOOT_CONFIG"
    grep -q "^dtparam=spi=on" "$BOOT_CONFIG" || echo "dtparam=spi=on" | sudo tee -a "$BOOT_CONFIG" >/dev/null
    grep -q "^dtparam=i2c_arm=on" "$BOOT_CONFIG" || echo "dtparam=i2c_arm=on" | sudo tee -a "$BOOT_CONFIG" >/dev/null

    # Waveshare 3.5" capacitive touch display overlay (ST7796S SPI, 480x320 landscape)
    if ! grep -q "dtoverlay=waveshare35a" "$BOOT_CONFIG"; then
        sudo tee -a "$BOOT_CONFIG" > /dev/null << EOF

# --- Waveshare 3.5" Capacitive Touch Display Configuration ---
# Display: ST7796S via SPI | Touch: FT6336U via I2C1 (0x38, INT=GPIO4)
dtoverlay=waveshare35a:rotate=90
# -------------------------------------------------------------
EOF
    fi
fi

# ── X11 framebuffer configuration (route rendering to /dev/fb1, the SPI display)
# Without this X11 defaults to /dev/fb0 (HDMI) and nothing appears on the
# Waveshare display even though the backlight is on.
echo "[5b/8] Configuring X11 to render to SPI display (/dev/fb1)…"
sudo mkdir -p /etc/X11/xorg.conf.d
sudo tee /etc/X11/xorg.conf.d/99-waveshare35.conf > /dev/null << 'EOF'
# Route X11 to the Waveshare 3.5" SPI framebuffer (/dev/fb1).
# The SPI overlay registers as fb1; the default HDMI/virtual device is fb0.
Section "Device"
    Identifier  "Waveshare35"
    Driver      "fbdev"
    Option      "fbdev" "/dev/fb1"
EndSection

Section "Screen"
    Identifier  "Default Screen"
    Device      "Waveshare35"
EndSection
EOF

# ── Auto-login (lightdm) ──────────────────────────────────────────────────────
# Without auto-login the graphical.target never reaches the "started" state on a
# headless boot (no HDMI), so the kiosk service never fires.
echo "[5c/8] Configuring lightdm auto-login for $(whoami)…"
if dpkg -l lightdm 2>/dev/null | grep -q '^ii'; then
    sudo mkdir -p /etc/lightdm/lightdm.conf.d
    sudo tee /etc/lightdm/lightdm.conf.d/01-wmi-autologin.conf > /dev/null << EOF
[Seat:*]
autologin-user=$(whoami)
autologin-user-timeout=0
EOF
fi

# ── FT6336U Capacitive Touch Controller ──────────────────────────────────────
# The FT6336U communicates over I2C1 at address 0x38 with interrupt on GPIO4.
# The edt-ft5x06 kernel module handles the FT6336U (FocalTech FT6x36 family).
# There is no standard Raspberry Pi device-tree overlay for this chip, so the
# device is bound to its driver via a systemd oneshot service at each boot.
echo "[5d/8] Configuring FT6336U capacitive touch controller…"
grep -qx "edt_ft5x06" /etc/modules 2>/dev/null || echo "edt_ft5x06" | sudo tee -a /etc/modules > /dev/null

sudo tee /etc/systemd/system/wmi-cap-touch.service > /dev/null << 'EOF'
[Unit]
Description=Bind FT6336U Capacitive Touch Controller (I2C1 0x38)
After=systemd-modules-load.service
Before=display-manager.service wmi-kiosk.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'echo edt_ft5x06 0x38 > /sys/bus/i2c/devices/i2c-1/new_device 2>/dev/null || echo "wmi-cap-touch: FT6336U bind skipped (device may already be registered)" >&2'

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable wmi-cap-touch

# ── systemd service: serial bridge ────────────────────────────────────────────
echo "[6/8] Installing wmi-bridge systemd service…"
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
echo "[7/8] Installing wmi-kiosk systemd service…"

# Locate Chromium — Pi OS Bookworm ships it as 'chromium', older releases as
# 'chromium-browser'.  Fall back to 'chromium' if neither is found yet (apt
# may not have run in this shell's PATH cache).
CHROMIUM_BIN=""
for candidate in /usr/bin/chromium-browser /usr/bin/chromium; do
    [ -x "$candidate" ] && CHROMIUM_BIN="$candidate" && break
done
CHROMIUM_BIN="${CHROMIUM_BIN:-/usr/bin/chromium}"

sudo tee /etc/systemd/system/wmi-kiosk.service > /dev/null << EOF
[Unit]
Description=WMI Dashboard Kiosk (Chromium)
Wants=graphical.target
After=graphical.target wmi-bridge.service

[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=/home/$(whoami)/.Xauthority
ExecStartPre=/bin/sleep 3
ExecStart="$CHROMIUM_BIN" \\
    --noerrdialogs \\
    --disable-infobars \\
    --kiosk \\
    --no-first-run \\
    --disable-translate \\
    --disable-features=TranslateUI \\
    --overscroll-history-navigation=0 \\
    --touch-events=enabled \\
    --force-device-scale-factor=1 \\
    --window-size=480,320 \\
    --disable-gpu \\
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
echo "[8/8] Adding $(whoami) to dialout group (serial port access)…"
sudo usermod -aG dialout "$(whoami)"

echo ""
echo "═══════════════════════════════════════════════════"
echo " Setup complete! Please reboot to start the kiosk:"
echo "   sudo reboot"
echo "═══════════════════════════════════════════════════"
