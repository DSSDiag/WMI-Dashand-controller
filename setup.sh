#!/usr/bin/env bash
# setup.sh - Interactive setup for WMI Dashboard
# Target added on rpi3-5inch-dsi-install:
#   Raspberry Pi 3 + 5 inch landscape capacitive DSI ribbon display.

set -euo pipefail

echo "═══════════════════════════════════════════════════"
echo " WMI Dashboard — Interactive Hardware Setup"
echo "═══════════════════════════════════════════════════"
echo ""

# 1. Prompt for Pi Version
echo "Which version of Raspberry Pi are you using?"
echo "  1) Pi Zero 2 W"
echo "  2) Pi 3"
echo "  3) Pi 4 (all variants)"
echo "  4) Pi 5 (all variants)"
read -p "Enter choice [1-4]: " PI_CHOICE

# 2. Prompt for OS Type
echo ""
echo "Which operating system is installed?"
echo "  1) Raspberry Pi OS Lite (CLI only)"
echo "  2) Raspberry Pi OS Full/Desktop"
read -p "Enter choice [1-2]: " OS_CHOICE

echo ""
echo "Which display are you using?"
echo "  1) 5 inch capacitive DSI ribbon display, landscape, usually 800x480"
echo "  2) 3.5 inch 52Pi/GPIO/SPI display, 480x320 landscape"
read -p "Enter choice [1-2]: " DISPLAY_CHOICE

echo ""
echo "═══════════════════════════════════════════════════"
echo " Generating Configuration..."
echo "═══════════════════════════════════════════════════"

PI_VERSION=""
case $PI_CHOICE in
    1) PI_VERSION="zero2w" ;;
    2) PI_VERSION="pi3" ;;
    3) PI_VERSION="pi4" ;;
    4) PI_VERSION="pi5" ;;
    *) echo "Invalid Pi choice."; exit 1 ;;
esac

OS_TYPE=""
case $OS_CHOICE in
    1) OS_TYPE="lite" ;;
    2) OS_TYPE="full" ;;
    *) echo "Invalid OS choice."; exit 1 ;;
esac

DISPLAY_TYPE=""
DISPLAY_WIDTH="${WMI_DISPLAY_WIDTH:-800}"
DISPLAY_HEIGHT="${WMI_DISPLAY_HEIGHT:-480}"
INSTALL_SPI_DRIVER="false"
case $DISPLAY_CHOICE in
    1)
        DISPLAY_TYPE="dsi5"
        DISPLAY_WIDTH="${WMI_DISPLAY_WIDTH:-800}"
        DISPLAY_HEIGHT="${WMI_DISPLAY_HEIGHT:-480}"
        ;;
    2)
        DISPLAY_TYPE="gpio35"
        DISPLAY_WIDTH="480"
        DISPLAY_HEIGHT="320"
        INSTALL_SPI_DRIVER="true"
        ;;
    *) echo "Invalid display choice."; exit 1 ;;
esac

echo "Selected: Pi $PI_VERSION, OS: $OS_TYPE, Display: $DISPLAY_TYPE (${DISPLAY_WIDTH}x${DISPLAY_HEIGHT})"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_DIST="$REPO_DIR/dashboard/dist"
BRIDGE_SCRIPT="$REPO_DIR/bridge/serial_bridge.py"
RUN_USER="${SUDO_USER:-$(whoami)}"
RUN_HOME="$(getent passwd "$RUN_USER" | cut -d: -f6)"

# --- Install System Packages ---
echo "[1/9] Installing system packages..."
sudo apt-get update -qq

BASE_PACKAGES="ca-certificates curl git python3-pip python3-venv nginx chromium chromium-browser unclutter x11-xserver-utils xdotool libinput-tools"
if [ "$OS_TYPE" == "lite" ] || [ "$DISPLAY_TYPE" == "dsi5" ]; then
    echo "Adding GUI support packages..."
    BASE_PACKAGES="$BASE_PACKAGES lightdm openbox xserver-xorg xinit dbus-x11"
fi

sudo apt-get install -y --no-install-recommends $BASE_PACKAGES || true

ensure_nginx_installed() {
    if command -v nginx >/dev/null 2>&1; then
        return 0
    fi

    echo "nginx was not found after package installation. Installing nginx now..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends nginx
}

# --- Setup Python Venv (Bridge) ---
echo "[2/9] Setting up Python virtual environment for bridge…"
VENV_DIR="$REPO_DIR/bridge/.venv"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi
if [ -f "$VENV_DIR/bin/pip" ]; then
    "$VENV_DIR/bin/pip" install --quiet --upgrade pip
    "$VENV_DIR/bin/pip" install --quiet -r "$REPO_DIR/bridge/requirements.txt"
else
    echo "Warning: pip not found in bridge virtual environment. Skipping pip install."
fi

# --- Setup Python Venv (Simulation) ---
echo "[3/9] Setting up Python virtual environment for simulation…"
SIM_VENV_DIR="$REPO_DIR/simulation/.venv"
if [ ! -d "$SIM_VENV_DIR" ]; then
    python3 -m venv "$SIM_VENV_DIR"
fi
if [ -f "$SIM_VENV_DIR/bin/pip" ]; then
    "$SIM_VENV_DIR/bin/pip" install --quiet --upgrade pip
    "$SIM_VENV_DIR/bin/pip" install --quiet -r "$REPO_DIR/simulation/requirements.txt"
else
    echo "Warning: pip not found in simulation virtual environment. Skipping pip install."
fi

# --- Build Dashboard ---
echo "[4/9] Building dashboard…"
if ! command -v node &>/dev/null; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
cd "$REPO_DIR/dashboard" && npm install --silent && npm run build
cd "$REPO_DIR"

# --- Configure Nginx ---
echo "[5/9] Configuring nginx…"
ensure_nginx_installed
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
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

# --- Display / boot config ---
echo "[6/9] Configuring display..."
if [ -f /boot/firmware/config.txt ]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    BOOT_CONFIG="/boot/config.txt"
else
    BOOT_CONFIG=""
fi

if [ -n "$BOOT_CONFIG" ]; then
    sudo cp "$BOOT_CONFIG" "${BOOT_CONFIG}.wmi-backup.$(date +%Y%m%d-%H%M%S)"
fi

if [ "$DISPLAY_TYPE" == "dsi5" ]; then
    echo "Configuring for 5 inch DSI ribbon display. No SPI LCD overlay will be installed."
    if [ -n "$BOOT_CONFIG" ]; then
        # Remove old SPI LCD overlays if this SD card was previously used with the 3.5 inch display.
        sudo sed -i '/waveshare35a/d' "$BOOT_CONFIG"
        sudo sed -i '/dtoverlay=mhs35/d' "$BOOT_CONFIG"
        sudo sed -i '/MHS35/d' "$BOOT_CONFIG"
        sudo sed -i '/52Pi/d' "$BOOT_CONFIG"

        grep -q '^disable_fw_kms_setup=' "$BOOT_CONFIG" \
            && sudo sed -i 's/^disable_fw_kms_setup=.*/disable_fw_kms_setup=0/' "$BOOT_CONFIG" \
            || echo 'disable_fw_kms_setup=0' | sudo tee -a "$BOOT_CONFIG" >/dev/null

        grep -q '^max_framebuffers=' "$BOOT_CONFIG" \
            && sudo sed -i 's/^max_framebuffers=.*/max_framebuffers=2/' "$BOOT_CONFIG" \
            || echo 'max_framebuffers=2' | sudo tee -a "$BOOT_CONFIG" >/dev/null
    fi
else
    echo "Configuring legacy 3.5 inch GPIO/SPI display path."
fi

# --- GUI / Kiosk / Bridge Services ---
echo "[7/9] Configuring services and GUI..."

if [ "$OS_TYPE" == "lite" ] || [ "$DISPLAY_TYPE" == "dsi5" ]; then
    echo "Configuring lightdm auto-login and Openbox session…"
    sudo update-alternatives --set x-session-manager /usr/bin/openbox-session || true
    sudo mkdir -p /etc/lightdm/lightdm.conf.d
    sudo tee /etc/lightdm/lightdm.conf.d/01-wmi-autologin.conf > /dev/null << AUTOLOGINEOF
[Seat:*]
autologin-user=$RUN_USER
autologin-user-timeout=0
user-session=openbox
xserver-command=X -s 0 -dpms
AUTOLOGINEOF

    mkdir -p "$RUN_HOME/.config/openbox"
    cat > "$RUN_HOME/.config/openbox/autostart" << AUTOEOF
#!/usr/bin/env bash
xset s off
xset -dpms
xset s noblank
OUTPUT="\$(xrandr --query | awk '/ connected/{print \$1; exit}')"
if [ -n "\$OUTPUT" ]; then
    xrandr --output "\$OUTPUT" --mode ${DISPLAY_WIDTH}x${DISPLAY_HEIGHT} 2>/dev/null || true
fi
AUTOEOF
    chmod +x "$RUN_HOME/.config/openbox/autostart"
    sudo chown -R "$RUN_USER:$RUN_USER" "$RUN_HOME/.config"
fi

# Serial Bridge Service
sudo tee /etc/systemd/system/wmi-bridge.service > /dev/null << BRIDGEEOF
[Unit]
Description=WMI Serial Bridge (ESP32 ↔ Dashboard)
After=network.target

[Service]
WorkingDirectory=$REPO_DIR
ExecStart=$VENV_DIR/bin/python3 -m bridge.serial_bridge
Restart=on-failure
RestartSec=3
User=$RUN_USER
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
After=graphical.target lightdm.service nginx.service wmi-bridge.service

[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=$RUN_HOME/.Xauthority
ExecStartPre=/bin/sleep 5
ExecStart=$CHROMIUM_BIN \\
    --noerrdialogs \\
    --disable-infobars \\
    --kiosk \\
    --no-first-run \\
    --disable-translate \\
    --disable-features=TranslateUI \\
    --overscroll-history-navigation=0 \\
    --touch-events=enabled \\
    --force-device-scale-factor=1 \\
    --window-position=0,0 \\
    --window-size=${DISPLAY_WIDTH},${DISPLAY_HEIGHT} \\
    --disable-gpu \\
    http://localhost
Restart=on-failure
RestartSec=5
User=$RUN_USER

[Install]
WantedBy=graphical.target
KIOSKEOF

sudo tee /etc/systemd/system/wmi-unclutter.service > /dev/null << UNCLUTTEREOF
[Unit]
Description=Unclutter (hide mouse cursor)
After=graphical.target lightdm.service

[Service]
Environment=DISPLAY=:0
Environment=XAUTHORITY=$RUN_HOME/.Xauthority
ExecStart=/usr/bin/unclutter -idle 1
Restart=always
User=$RUN_USER

[Install]
WantedBy=graphical.target
UNCLUTTEREOF

sudo systemctl daemon-reload
sudo systemctl enable wmi-kiosk wmi-unclutter

# --- Permissions ---
echo "[8/9] Adding user to dialout group..."
sudo usermod -aG dialout "$RUN_USER"

# --- Optional legacy 3.5 inch driver install ---
echo "[9/9] Final display driver step..."
if [ "$INSTALL_SPI_DRIVER" == "true" ]; then
    echo "Installing 52Pi 3.5 inch GPIO/SPI display driver. This may reboot automatically."
    cd "$REPO_DIR"
    if [ ! -d "LCD-show" ]; then
        git clone https://github.com/goodtft/LCD-show.git
    fi
    chmod -R 755 LCD-show

    if [ ! -e "/boot/config.txt" ] && [ -f "/boot/firmware/config.txt" ]; then
        echo "Bookworm detected: creating /boot/config.txt → /boot/firmware/config.txt symlink for LCD-show..."
        sudo ln -s /boot/firmware/config.txt /boot/config.txt
    fi

    sudo systemctl set-default graphical.target
    cd LCD-show/
    sudo ./MHS35-show
else
    sudo systemctl set-default graphical.target
    echo "DSI display selected. No third-party LCD-show driver installed."
    echo ""
    echo "═══════════════════════════════════════════════════"
    echo " Setup complete. Reboot to start the kiosk:"
    echo "   sudo reboot"
    echo ""
    echo " After reboot, useful checks:"
    echo "   xrandr --query"
    echo "   libinput list-devices"
    echo "   sudo systemctl status wmi-kiosk"
    echo "   sudo journalctl -u wmi-bridge -f"
    echo "═══════════════════════════════════════════════════"
fi
