#!/usr/bin/env bash
# setup.sh - Interactive setup for WMI Dashboard

set -euo pipefail

echo "═══════════════════════════════════════════════════"
echo " WMI Dashboard — Interactive Hardware Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# 1. Prompt for Pi Version
echo "Which version of Raspberry Pi are you using?"
echo "  1) Pi Zero 2 W"
echo "  2) Pi 4 (all variants)"
echo "  3) Pi 5 (all variants)"
read -p "Enter choice [1-3]: " PI_CHOICE

# 2. Prompt for OS Type
echo ""
echo "Which operating system is installed?"
echo "  1) Raspberry Pi OS Lite (CLI only)"
echo "  2) Raspberry Pi OS Full (Desktop)"
read -p "Enter choice [1-2]: " OS_CHOICE

echo ""
echo "═══════════════════════════════════════════════════"
echo " Generating Configuration..."
echo "═══════════════════════════════════════════════════"

PI_VERSION=""
case $PI_CHOICE in
    1) PI_VERSION="zero2w" ;;
    2) PI_VERSION="pi4" ;;
    3) PI_VERSION="pi5" ;;
    *) echo "Invalid Pi choice."; exit 1 ;;
esac

OS_TYPE=""
case $OS_CHOICE in
    1) OS_TYPE="lite" ;;
    2) OS_TYPE="full" ;;
    *) echo "Invalid OS choice."; exit 1 ;;
esac

echo "Selected: Pi \$PI_VERSION, OS: \$OS_TYPE"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIST="$REPO_DIR/dashboard/dist"
BRIDGE_SCRIPT="$REPO_DIR/bridge/serial_bridge.py"

# --- Install System Packages ---
echo "[1/8] Installing system packages..."
sudo apt-get update -qq

BASE_PACKAGES="python3-pip python3-venv nginx chromium chromium-browser unclutter x11-xserver-utils xdotool git"
if [ "$OS_TYPE" == "lite" ]; then
    echo "Lite OS detected. Adding lightdm and openbox for GUI support..."
    BASE_PACKAGES="$BASE_PACKAGES lightdm openbox"
fi

sudo apt-get install -y --no-install-recommends $BASE_PACKAGES 2>/dev/null || true

# --- Setup Python Venv (Bridge) ---
echo "[2/8] Setting up Python virtual environment for bridge…"
VENV_DIR="$REPO_DIR/bridge/.venv"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
if [ -f "$VENV_DIR/bin/pip" ]; then
    "$VENV_DIR/bin/pip" install --quiet -r "$REPO_DIR/bridge/requirements.txt"
else
    echo "Warning: pip not found in bridge virtual environment. Skipping pip install."
fi

# --- Setup Python Venv (Simulation) ---
echo "[3/8] Setting up Python virtual environment for simulation…"
SIM_VENV_DIR="$REPO_DIR/simulation/.venv"
if [ ! -d "$SIM_VENV_DIR" ]; then
    python3 -m venv "$SIM_VENV_DIR"
fi
if [ -f "$SIM_VENV_DIR/bin/pip" ]; then
    "$SIM_VENV_DIR/bin/pip" install --quiet -r "$REPO_DIR/simulation/requirements.txt"
else
    echo "Warning: pip not found in simulation virtual environment. Skipping pip install."
fi

# --- Build Dashboard ---
echo "[4/8] Building dashboard…"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
cd "$REPO_DIR/dashboard" && npm install --silent && npm run build
cd "$REPO_DIR"

# --- Configure Nginx ---
echo "[5/8] Configuring nginx…"
sudo tee /etc/nginx/sites-available/wmi-dashboard > /dev/null << SERVEREOF
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
sudo nginx -t && sudo systemctl enable --now nginx

# --- GUI / Kiosk / Bridge Services ---
echo "[6/8] Configuring services and GUI..."

if [ "$OS_TYPE" == "lite" ]; then
    echo "Configuring lightdm auto-login and window manager for Lite OS…"
    sudo update-alternatives --set x-session-manager /usr/bin/openbox-session
    if dpkg -l lightdm 2>/dev/null | grep -q '^ii'; then
        sudo mkdir -p /etc/lightdm/lightdm.conf.d
        sudo tee /etc/lightdm/lightdm.conf.d/01-wmi-autologin.conf > /dev/null << AUTOLOGINEOF
[Seat:*]
autologin-user=$(whoami)
autologin-user-timeout=0
AUTOLOGINEOF
    fi
fi

# Serial Bridge Service
sudo tee /etc/systemd/system/wmi-bridge.service > /dev/null << BRIDGEEOF
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
BRIDGEEOF
sudo systemctl daemon-reload
sudo systemctl enable --now wmi-bridge

# Kiosk Service
CHROMIUM_BIN=""
for candidate in /usr/bin/chromium-browser /usr/bin/chromium; do
    [ -x "$candidate" ] && CHROMIUM_BIN="$candidate" && break
done
CHROMIUM_BIN="${CHROMIUM_BIN:-/usr/bin/chromium}"

sudo tee /etc/systemd/system/wmi-kiosk.service > /dev/null << KIOSKEOF
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
KIOSKEOF

sudo tee /etc/systemd/system/wmi-unclutter.service > /dev/null << UNCLUTTEREOF
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
UNCLUTTEREOF

sudo systemctl daemon-reload
sudo systemctl enable wmi-kiosk wmi-unclutter

echo "[7/8] Adding user to dialout group..."
sudo usermod -aG dialout "$(whoami)"

echo "[8/8] Installing 52Pi 3.5\" Display Driver..."
cd "$REPO_DIR"
if [ ! -d "LCD-show" ]; then
    git clone https://github.com/goodtft/LCD-show.git
fi
chmod -R 755 LCD-show

# On Raspberry Pi OS Bookworm the boot partition is mounted at /boot/firmware/.
# The goodtft LCD-show scripts write to /boot/config.txt which doesn't exist there.
# Create a symlink so MHS35-show writes to the right place automatically.
if [ ! -e "/boot/config.txt" ] && [ -f "/boot/firmware/config.txt" ]; then
    echo "Bookworm detected: creating /boot/config.txt → /boot/firmware/config.txt symlink for LCD-show..."
    sudo ln -s /boot/firmware/config.txt /boot/config.txt
fi

# Force GUI target before display driver reboot
sudo systemctl set-default graphical.target

echo "═══════════════════════════════════════════════════"
echo " Setup complete! The 52Pi driver installation will now"
echo " run and reboot your system automatically."
echo "═══════════════════════════════════════════════════"

cd LCD-show/
if [ "$PI_VERSION" == "pi5" ]; then
    echo "Warning: Pi 5 driver support in LCD-show may vary."
fi
sudo ./MHS35-show
