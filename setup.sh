#!/usr/bin/env bash
# setup.sh - Interactive setup for WMI Dashboard
# Supports:
#   - Raspberry Pi 3 + 5 inch landscape capacitive DSI ribbon display
#   - 52Pi 3.5 inch GPIO/SPI display
#   - Generic blue-board 3.5 inch ILI9486/XPT2046 HAT
#   - Waveshare 3.5inch RPi LCD (G)

set -euo pipefail

if [ "${EUID}" -eq 0 ]; then
    if [ -n "${SUDO_USER:-}" ] && [ "${SUDO_USER}" != "root" ]; then
        RUN_USER="${SUDO_USER}"
    else
        echo "Please run this script as your normal user, not directly as root."
        echo "Example: ./setup.sh"
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
echo " WMI Dashboard — Interactive Hardware Setup"
echo "═══════════════════════════════════════════════════"
echo ""

echo "Which version of Raspberry Pi are you using?"
echo "  1) Pi Zero 2 W"
echo "  2) Pi 3"
echo "  3) Pi 4 (all variants)"
echo "  4) Pi 5 (all variants)"
read -p "Enter choice [1-4]: " PI_CHOICE

echo ""
echo "Which operating system is installed?"
echo "  1) Raspberry Pi OS Lite (CLI only)"
echo "  2) Raspberry Pi OS Full/Desktop"
read -p "Enter choice [1-2]: " OS_CHOICE

echo ""
echo "Which display are you using?"
echo "  1) 5 inch capacitive DSI ribbon display, landscape, usually 800x480"
echo "  2) 3.5 inch 52Pi/GPIO/SPI display, 480x320 landscape"
echo "  3) Generic 3.5inch RPi Display / LCDWiki-style HAT"
echo "  4) Waveshare 3.5inch RPi LCD (G) resistive touch"
echo "  5) Display already configured / skip display driver changes"
read -p "Enter choice [1-5]: " DISPLAY_CHOICE

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

DISPLAY_PROFILE=""
DISPLAY_WIDTH="${WMI_DISPLAY_WIDTH:-800}"
DISPLAY_HEIGHT="${WMI_DISPLAY_HEIGHT:-480}"
INSTALL_DRIVER="none"
case $DISPLAY_CHOICE in
    1)
        DISPLAY_PROFILE="dsi5"
        DISPLAY_WIDTH="${WMI_DISPLAY_WIDTH:-800}"
        DISPLAY_HEIGHT="${WMI_DISPLAY_HEIGHT:-480}"
        ;;
    2)
        DISPLAY_PROFILE="52pi-k0403"
        DISPLAY_WIDTH="480"
        DISPLAY_HEIGHT="320"
        INSTALL_DRIVER="mhs35"
        ;;
    3)
        DISPLAY_PROFILE="generic-ili9486-hat"
        DISPLAY_WIDTH="480"
        DISPLAY_HEIGHT="320"
        INSTALL_DRIVER="lcd35"
        ;;
    4)
        DISPLAY_PROFILE="waveshare-35g"
        DISPLAY_WIDTH="320"
        DISPLAY_HEIGHT="480"
        INSTALL_DRIVER="waveshare"
        ;;
    5)
        DISPLAY_PROFILE="preconfigured"
        ;;
    *)
        echo "Invalid display choice."
        exit 1
        ;;
esac

echo "Selected: Pi $PI_VERSION, OS: $OS_TYPE, Display: $DISPLAY_PROFILE (${DISPLAY_WIDTH}x${DISPLAY_HEIGHT})"

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARD_BUILD_DIR="$REPO_DIR/dashboard/dist"
NGINX_DASHBOARD_ROOT="/var/www/wmi-dashboard"
BRIDGE_MODULE="bridge.serial_bridge"
KIOSK_LAUNCHER="$REPO_DIR/bridge/kiosk-launch.sh"

need_cmd() {
    command -v "$1" >/dev/null 2>&1
}

ensure_pkg() {
    local pkg="$1"
    dpkg -s "$pkg" >/dev/null 2>&1
}

ensure_nginx_installed() {
    if command -v nginx >/dev/null 2>&1; then
        return 0
    fi

    echo "nginx was not found after package installation. Installing nginx now..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends nginx
}

prepare_bookworm_lcd_show_symlink() {
    if [ ! -e "/boot/config.txt" ] && [ -f "/boot/firmware/config.txt" ]; then
        echo "Bookworm detected: creating /boot/config.txt → /boot/firmware/config.txt symlink for LCD-show..."
        sudo ln -s /boot/firmware/config.txt /boot/config.txt
    fi
}

configure_tty1_startx_kiosk() {
    cat > "$RUN_HOME/.bash_profile" <<'EOF'
export FRAMEBUFFER=/dev/fb1

if [ -z "${DISPLAY:-}" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
EOF

    cat > "$RUN_HOME/.xinitrc" <<EOF
#!/bin/sh
set -eu

xset s off
xset -dpms
xset s noblank

openbox-session &
exec "$KIOSK_LAUNCHER"
EOF

    chmod 644 "$RUN_HOME/.bash_profile"
    chmod 755 "$RUN_HOME/.xinitrc"
}

boot_config_path() {
    if [ -f /boot/firmware/config.txt ]; then
        echo /boot/firmware/config.txt
    else
        echo /boot/config.txt
    fi
}

install_waveshare_35g_bookworm() {
    local boot_config
    boot_config="$(boot_config_path)"

    echo "Installing Waveshare ST7796S firmware blob..."
    local tmp_dir
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' RETURN
    (
        cd "$tmp_dir"
        wget -q https://files.waveshare.com/wiki/common/St7796s.zip
        unzip -oq St7796s.zip
        sudo cp st7796s.bin /lib/firmware/
    )

    echo "Writing Waveshare 3.5inch RPi LCD (G) display overlay config to $boot_config..."
    sudo python3 - "$boot_config" <<'PY'
from pathlib import Path
import sys

config_path = Path(sys.argv[1])
start = "# >>> WMI Waveshare 3.5inch RPi LCD (G) >>>"
end = "# <<< WMI Waveshare 3.5inch RPi LCD (G) <<<"
block = """# >>> WMI Waveshare 3.5inch RPi LCD (G) >>>
dtparam=spi=on
dtoverlay=mipi-dbi-spi,speed=48000000
dtparam=compatible=st7796s\\0panel-mipi-dbi-spi
dtparam=width=320,height=480,width-mm=49,height-mm=79
dtparam=reset-gpio=27,dc-gpio=22,backlight-gpio=18
dtoverlay=ads7846,speed=2000000,penirq=17,xmin=300,ymin=300,xmax=3900,ymax=3800,pmin=0,pmax=65535,xohms=400
extra_transpose_buffer=2
# <<< WMI Waveshare 3.5inch RPi LCD (G) <<<
"""

text = config_path.read_text()
while start in text and end in text:
    start_idx = text.index(start)
    end_idx = text.index(end, start_idx) + len(end)
    while end_idx < len(text) and text[end_idx] in "\r\n":
        end_idx += 1
    text = text[:start_idx].rstrip() + "\n" + text[end_idx:].lstrip("\r\n")

if "[all]" in text:
    anchor = text.rfind("[all]")
    insert_at = text.find("\n", anchor)
    if insert_at == -1:
        text = text + "\n\n" + block
    else:
        tail = text[insert_at + 1 :].lstrip("\r\n")
        text = text[: insert_at + 1] + "\n" + tail.rstrip() + "\n\n" + block
else:
    text = text.rstrip() + "\n\n[all]\n\n" + block

config_path.write_text(text)
PY
}

configure_kiosk_launcher() {
    local chromium_bin="$1"

    cat > "$KIOSK_LAUNCHER" <<EOF
#!/usr/bin/env bash
set -euo pipefail

export DISPLAY=:0
export XAUTHORITY="$RUN_HOME/.Xauthority"

for _ in \$(seq 1 45); do
    if [ -S /tmp/.X11-unix/X0 ] && [ -f "\$XAUTHORITY" ] && xset q >/dev/null 2>&1; then
        break
    fi
    sleep 2
done

if ! xset q >/dev/null 2>&1; then
    echo "X session on :0 never became ready" >&2
    exit 1
fi

for _ in \$(seq 1 60); do
    if curl -fsS http://localhost >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

xset s off
xset -dpms
xset s noblank

XRANDR_OUTPUT=\$(xrandr --query | awk '/ connected/{print \$1; exit}')
XRANDR_MODE=\$(xrandr --query | awk '/\*/{print \$1; exit}')
if [ -n "\${XRANDR_OUTPUT:-}" ]; then
    if [ -n "\${XRANDR_MODE:-}" ]; then
        xrandr --output "\$XRANDR_OUTPUT" --mode "\$XRANDR_MODE" --primary >/dev/null 2>&1 || true
    else
        xrandr --output "\$XRANDR_OUTPUT" --primary >/dev/null 2>&1 || true
    fi
fi

mkdir -p "$RUN_HOME/.config/chromium"
rm -f "$RUN_HOME/.config/chromium/SingletonLock" \\
      "$RUN_HOME/.config/chromium/SingletonSocket" \\
      "$RUN_HOME/.config/chromium/SingletonCookie"

exec "$chromium_bin" \\
    --noerrdialogs \\
    --disable-infobars \\
    --kiosk \\
    --start-fullscreen \\
    --window-position=0,0 \\
    --no-first-run \\
    --disable-translate \\
    --disable-features=TranslateUI \\
    --overscroll-history-navigation=0 \\
    --touch-events=enabled \\
    --force-device-scale-factor=1 \\
    --disable-gpu \\
    --check-for-update-interval=31536000 \\
    --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT' \\
    http://localhost
EOF
    chmod +x "$KIOSK_LAUNCHER"
}

set_boot_config_value() {
    local key="$1"
    local value="$2"
    if [ -z "${BOOT_CONFIG:-}" ]; then
        return 0
    fi

    grep -q "^${key}=" "$BOOT_CONFIG" \
        && sudo sed -i "s/^${key}=.*/${key}=${value}/" "$BOOT_CONFIG" \
        || echo "${key}=${value}" | sudo tee -a "$BOOT_CONFIG" >/dev/null
}

set_boot_cmdline_token() {
    if [ -z "${BOOT_CMDLINE:-}" ]; then
        return 0
    fi

    local cmdline
    cmdline="$(sudo tr -d '\n' < "$BOOT_CMDLINE")"

    for token in console=tty1 nosplash plymouth.enable=0; do
        cmdline=" $cmdline "
        cmdline="${cmdline// $token / }"
        cmdline="${cmdline#"${cmdline%%[![:space:]]*}"}"
        cmdline="${cmdline%"${cmdline##*[![:space:]]}"}"
    done

    for token in quiet splash loglevel=0 logo.nologo vt.global_cursor_default=0 systemd.show_status=false rd.udev.log_level=3 plymouth.ignore-serial-consoles; do
        if [[ " $cmdline " != *" $token "* ]]; then
            cmdline="$cmdline $token"
        fi
    done

    printf '%s\n' "$cmdline" | sudo tee "$BOOT_CMDLINE" >/dev/null
}

configure_plymouth_theme() {
    local theme_dir="/usr/share/plymouth/themes/mild-modz"
    local logo_source="$REPO_DIR/dashboard/public/logo.png"

    if [ ! -f "$logo_source" ]; then
        echo "Warning: logo asset not found at $logo_source. Skipping branded boot splash."
        return 0
    fi

    sudo mkdir -p "$theme_dir"
    sudo cp "$logo_source" "$theme_dir/logo.png"
    printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAICAYAAAA4GpVBAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAQSURBVBhXYxCXUfnPQJgAAMroCrHpRHBSAAAAAElFTkSuQmCC' | base64 -d | sudo tee "$theme_dir/bar-bg.png" >/dev/null
    printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAICAYAAAA4GpVBAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAQSURBVBhXY1j8n+E/A2ECAKSDFQmK/XW8AAAAAElFTkSuQmCC' | base64 -d | sudo tee "$theme_dir/bar-fg.png" >/dev/null
    sudo tee "$theme_dir/mild-modz.plymouth" >/dev/null << 'PLYMOUTHEOF'
[Plymouth Theme]
Name=Mild Modz
Description=Mild Modz kiosk boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/mild-modz
ScriptFile=/usr/share/plymouth/themes/mild-modz/mild-modz.script
PLYMOUTHEOF
    sudo tee "$theme_dir/mild-modz.script" >/dev/null << 'SCRIPTEOF'
Window.SetBackgroundTopColor(0.0, 0.0, 0.0);
Window.SetBackgroundBottomColor(0.0, 0.0, 0.0);

screen_width = Window.GetWidth();
screen_height = Window.GetHeight();

logo = Image("logo.png");
logo_scale = Math.Min((screen_width * 0.52) / logo.GetWidth(), (screen_height * 0.60) / logo.GetHeight());
logo = logo.Scale(Math.Int(logo.GetWidth() * logo_scale), Math.Int(logo.GetHeight() * logo_scale));
logo_sprite = Sprite(logo);
logo_sprite.SetX((screen_width - logo.GetWidth()) / 2);
logo_sprite.SetY((screen_height - logo.GetHeight()) / 2 - 22);
logo_sprite.SetZ(10);

bar_width = screen_width * 0.48;
if (bar_width > 380) bar_width = 380;
bar_height = 8;
bar_x = (screen_width - bar_width) / 2;
bar_y = (screen_height + logo.GetHeight()) / 2 + 10;

bar_bg = Image("bar-bg.png").Scale(bar_width, bar_height);
bar_bg_sprite = Sprite(bar_bg);
bar_bg_sprite.SetX(bar_x);
bar_bg_sprite.SetY(bar_y);
bar_bg_sprite.SetZ(11);

bar_fg_sprite = Sprite();
bar_fg_sprite.SetX(bar_x);
bar_fg_sprite.SetY(bar_y);
bar_fg_sprite.SetZ(12);

fun progress_callback(duration, progress) {
    fill_width = Math.Int(bar_width * progress);
    if (fill_width < 1) fill_width = 1;
    bar_fg = Image("bar-fg.png").Scale(fill_width, bar_height);
    bar_fg_sprite.SetImage(bar_fg);
}

Plymouth.SetBootProgressFunction(progress_callback);
SCRIPTEOF

    sudo plymouth-set-default-theme -R mild-modz || sudo update-alternatives --set default.plymouth "$theme_dir/mild-modz.plymouth" || true
    sudo update-initramfs -u || true
}

echo "[1/9] Installing system packages..."
sudo apt-get update -qq

BASE_PACKAGES=(
    ca-certificates
    curl
    git
    python3-pip
    python3-venv
    nginx
    unclutter
    x11-xserver-utils
    xdotool
    libinput-tools
    plymouth
    plymouth-themes
    unzip
    wget
)

if ensure_pkg chromium; then
    :
elif ensure_pkg chromium-browser; then
    :
else
    if apt-cache show chromium >/dev/null 2>&1; then
        BASE_PACKAGES+=(chromium)
    else
        BASE_PACKAGES+=(chromium-browser)
    fi
fi

if [ "$OS_TYPE" == "lite" ] || [ "$DISPLAY_PROFILE" == "dsi5" ]; then
    BASE_PACKAGES+=(lightdm openbox xserver-xorg xinit dbus-x11)
fi
if [ "$DISPLAY_PROFILE" == "generic-ili9486-hat" ]; then
    BASE_PACKAGES+=(openbox xserver-xorg xinit dbus-x11)
fi

sudo apt-get install -y --no-install-recommends "${BASE_PACKAGES[@]}" || true

echo "[2/9] Setting up Python virtual environment for bridge..."
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

echo "[3/9] Setting up Python virtual environment for simulation..."
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

echo "[4/9] Building dashboard..."
if ! need_cmd node; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt-get install -y nodejs
fi
cd "$REPO_DIR/dashboard" && npm install --silent && npm run build
cd "$REPO_DIR"

echo "[5/9] Configuring nginx..."
ensure_nginx_installed
sudo rm -rf "$NGINX_DASHBOARD_ROOT"
sudo mkdir -p "$NGINX_DASHBOARD_ROOT"
sudo cp -a "$DASHBOARD_BUILD_DIR"/. "$NGINX_DASHBOARD_ROOT"/
sudo chown -R root:www-data "$NGINX_DASHBOARD_ROOT"
sudo find "$NGINX_DASHBOARD_ROOT" -type d -exec chmod 755 {} \;
sudo find "$NGINX_DASHBOARD_ROOT" -type f -exec chmod 644 {} \;
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
sudo tee /etc/nginx/sites-available/wmi-dashboard > /dev/null << SERVEREOF
server {
    listen 80 default_server;
    root $NGINX_DASHBOARD_ROOT;
    index index.html;
    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
SERVEREOF
sudo ln -sf /etc/nginx/sites-available/wmi-dashboard /etc/nginx/sites-enabled/wmi-dashboard
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl enable --now nginx

echo "[6/9] Configuring display..."
if [ -f /boot/firmware/config.txt ]; then
    BOOT_CONFIG="/boot/firmware/config.txt"
elif [ -f /boot/config.txt ]; then
    BOOT_CONFIG="/boot/config.txt"
else
    BOOT_CONFIG=""
fi
if [ -f /boot/firmware/cmdline.txt ]; then
    BOOT_CMDLINE="/boot/firmware/cmdline.txt"
elif [ -f /boot/cmdline.txt ]; then
    BOOT_CMDLINE="/boot/cmdline.txt"
else
    BOOT_CMDLINE=""
fi

if [ -n "$BOOT_CONFIG" ]; then
    sudo cp "$BOOT_CONFIG" "${BOOT_CONFIG}.wmi-backup.$(date +%Y%m%d-%H%M%S)"
fi
if [ -n "$BOOT_CMDLINE" ]; then
    sudo cp "$BOOT_CMDLINE" "${BOOT_CMDLINE}.wmi-backup.$(date +%Y%m%d-%H%M%S)"
fi

echo "Configuring branded Mild Modz boot splash and hiding boot text..."
set_boot_config_value "disable_splash" "1"
set_boot_cmdline_token
configure_plymouth_theme

if [ "$DISPLAY_PROFILE" == "dsi5" ]; then
    echo "Configuring for 5 inch DSI ribbon display. No SPI LCD overlay will be installed."
    if [ -n "$BOOT_CONFIG" ]; then
        sudo sed -i '/waveshare35a/d' "$BOOT_CONFIG"
        sudo sed -i '/dtoverlay=mhs35/d' "$BOOT_CONFIG"
        sudo sed -i '/dtoverlay=tft35a/d' "$BOOT_CONFIG"
        sudo sed -i '/MHS35/d' "$BOOT_CONFIG"
        sudo sed -i '/52Pi/d' "$BOOT_CONFIG"

        set_boot_config_value "disable_fw_kms_setup" "0"
        set_boot_config_value "max_framebuffers" "2"
    fi
else
    echo "Configuring non-DSI display path."
fi

echo "[7/9] Configuring services and GUI..."
if [ "$OS_TYPE" == "lite" ] || [ "$DISPLAY_PROFILE" == "dsi5" ]; then
    echo "Configuring lightdm auto-login and Openbox session..."
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

sudo tee /etc/systemd/system/wmi-bridge.service > /dev/null << BRIDGEEOF
[Unit]
Description=WMI Serial Bridge (ESP32 ↔ Dashboard)
After=network.target

[Service]
WorkingDirectory=$REPO_DIR
ExecStart=$VENV_DIR/bin/python3 -m $BRIDGE_MODULE
Restart=on-failure
RestartSec=3
User=$RUN_USER
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
BRIDGEEOF

CHROMIUM_BIN=""
for candidate in /usr/lib/chromium/chromium /usr/bin/chromium-browser /usr/bin/chromium; do
    if [ -x "$candidate" ]; then
        CHROMIUM_BIN="$candidate"
        break
    fi
done
CHROMIUM_BIN="${CHROMIUM_BIN:-/usr/lib/chromium/chromium}"
configure_kiosk_launcher "$CHROMIUM_BIN"

sudo tee /etc/systemd/system/wmi-kiosk.service > /dev/null << KIOSKEOF
[Unit]
Description=WMI Dashboard Kiosk (Chromium)
Wants=graphical.target display-manager.service network-online.target
After=graphical.target display-manager.service network-online.target nginx.service wmi-bridge.service

[Service]
ExecStart=$KIOSK_LAUNCHER
Restart=on-failure
RestartSec=5
User=$RUN_USER

[Install]
WantedBy=graphical.target
KIOSKEOF

sudo tee /etc/systemd/system/wmi-unclutter.service > /dev/null << UNCLUTTEREOF
[Unit]
Description=Unclutter (hide mouse cursor)
After=graphical.target display-manager.service

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
sudo systemctl enable --now wmi-bridge
sudo systemctl enable wmi-kiosk wmi-unclutter

echo "[8/9] Adding user to dialout group..."
sudo usermod -aG dialout "$RUN_USER"

echo "[9/9] Final display driver step..."
case "$DISPLAY_PROFILE" in
    "dsi5")
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
        ;;
    "52pi-k0403")
        cd "$REPO_DIR"
        if [ ! -d "LCD-show" ]; then
            git clone https://github.com/goodtft/LCD-show.git
        fi
        chmod -R 755 LCD-show
        prepare_bookworm_lcd_show_symlink
        sudo systemctl set-default graphical.target
        echo "Installing 52Pi 3.5 inch GPIO/SPI display driver. This may reboot automatically."
        cd LCD-show/
        if [ "$PI_VERSION" == "pi5" ]; then
            echo "Warning: Pi 5 driver support in LCD-show may vary."
        fi
        sudo ./MHS35-show
        ;;
    "generic-ili9486-hat")
        cd "$REPO_DIR"
        if [ ! -d "LCD-show" ]; then
            git clone https://github.com/goodtft/LCD-show.git
        fi
        chmod -R 755 LCD-show
        prepare_bookworm_lcd_show_symlink
        configure_tty1_startx_kiosk
        sudo systemctl disable wmi-kiosk wmi-unclutter || true
        sudo systemctl set-default multi-user.target
        echo "═══════════════════════════════════════════════════"
        echo " Setup complete! The generic 3.5-inch ILI9486/XPT2046"
        echo " LCD-show driver installation will now run and reboot"
        echo " the system automatically."
        echo "═══════════════════════════════════════════════════"
        cd LCD-show/
        if [ "$PI_VERSION" == "pi5" ]; then
            echo "Warning: Pi 5 driver support in LCD-show may vary."
        fi
        sudo ./LCD35-show
        ;;
    "waveshare-35g")
        sudo systemctl set-default graphical.target
        install_waveshare_35g_bookworm
        echo "═══════════════════════════════════════════════════"
        echo " Setup complete! Waveshare 3.5inch RPi LCD (G)"
        echo " support has been configured and the system will"
        echo " reboot now."
        echo "═══════════════════════════════════════════════════"
        sudo reboot
        ;;
    "preconfigured")
        sudo systemctl set-default graphical.target
        echo "═══════════════════════════════════════════════════"
        echo " Setup complete! Display driver changes were skipped."
        echo " Your existing display configuration is preserved."
        echo "═══════════════════════════════════════════════════"
        ;;
esac
