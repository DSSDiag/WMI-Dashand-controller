#!/usr/bin/env bash
# setup-precomf.sh - Install WMI dashboard stack on a Pi that already has
# a working display / touch / desktop setup. This script does NOT install
# display drivers or touch boot config changes, which makes it a good fit for
# already-configured panels such as DSI screens, generic ILI9486/XPT2046 HATs,
# or other pre-wired factory display setups.

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
DASHBOARD_BUILD_DIR="$REPO_DIR/dashboard/dist"
NGINX_DASHBOARD_ROOT="/var/www/wmi-dashboard"
VENV_DIR="$REPO_DIR/bridge/.venv"
SIM_VENV_DIR="$REPO_DIR/simulation/.venv"
KIOSK_LAUNCHER="$REPO_DIR/bridge/kiosk-launch.sh"

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

ensure_nginx_installed() {
    if command -v nginx >/dev/null 2>&1; then
        return 0
    fi

    echo "nginx was not found after package installation. Installing nginx now..."
    sudo apt-get update -qq
    sudo apt-get install -y --no-install-recommends nginx
}

install_dashboard_dependencies() {
    local dashboard_dir="$1"

    if [ ! -d "$dashboard_dir" ]; then
        echo "Dashboard directory is missing: $dashboard_dir" >&2
        return 1
    fi

    if ! command -v npm >/dev/null 2>&1; then
        echo "npm is required to install dashboard dependencies. Please install Node.js first." >&2
        return 1
    fi

    if [ -f "$dashboard_dir/package-lock.json" ]; then
        if (
            cd "$dashboard_dir"
            npm ci --silent
        ); then
            return 0
        fi

        echo "npm ci failed for $dashboard_dir. Falling back to npm install..." >&2
    fi

    (
        cd "$dashboard_dir"
        npm install --silent
    )
}

resolve_chromium_bin() {
    local candidate

    for candidate in /usr/lib/chromium/chromium /usr/bin/chromium-browser /usr/bin/chromium; do
        if [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    echo "Chromium executable not found after package installation." >&2
    echo "Checked: /usr/lib/chromium/chromium, /usr/bin/chromium-browser, /usr/bin/chromium" >&2
    return 1
}

build_dashboard_url() {
    local base_url="${1:-http://localhost}"
    local display_profile="${2:-}"
    local separator='?'

    if [ -z "$display_profile" ]; then
        printf '%s\n' "$base_url"
        return 0
    fi

    if [[ "$base_url" == *[\?\&]profile=* ]]; then
        printf '%s\n' "$base_url"
        return 0
    fi

    if [[ "$base_url" == *\?* ]]; then
        separator='&'
    fi

    printf '%s%sprofile=%s\n' "$base_url" "$separator" "$display_profile"
}

resolve_path_or_empty() {
    local target="$1"

    if command -v realpath >/dev/null 2>&1; then
        realpath -m "$target"
        return 0
    fi

    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$target" 2>/dev/null || true
        return 0
    fi

    printf '%s\n' ""
}

deploy_dashboard_build() {
    local build_dir="$1"
    local target_root="$2"
    local staged_root
    local resolved_target
    staged_root="$(mktemp -d)"

    if [ ! -f "$build_dir/index.html" ]; then
        echo "Dashboard build output is missing: $build_dir/index.html" >&2
        rm -rf "$staged_root"
        return 1
    fi

    case "$target_root" in
        /var/www/wmi-dashboard) ;;
        *)
            echo "Refusing to deploy dashboard into unexpected target: $target_root" >&2
            rm -rf "$staged_root"
            return 1
            ;;
    esac

    if [ -L "$target_root" ]; then
        echo "Refusing to deploy dashboard through symlinked target: $target_root" >&2
        rm -rf "$staged_root"
        return 1
    fi

    if [ -e "$target_root" ] && [ ! -d "$target_root" ]; then
        echo "Refusing to deploy dashboard into non-directory target: $target_root" >&2
        rm -rf "$staged_root"
        return 1
    fi

    cp -a "$build_dir"/. "$staged_root"/
    sudo mkdir -p "$target_root"
    resolved_target="$(resolve_path_or_empty "$target_root")"
    if [ -n "$resolved_target" ] && [ "$resolved_target" != "/var/www/wmi-dashboard" ]; then
        echo "Refusing to deploy dashboard into redirected target: $resolved_target" >&2
        rm -rf "$staged_root"
        return 1
    fi
    sudo find "$target_root" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
    sudo cp -a "$staged_root"/. "$target_root"/
    rm -rf "$staged_root"
}

validate_kiosk_launcher_target() {
    local target="$1"

    case "$target" in
        "$REPO_DIR"/bridge/kiosk-launch.sh) ;;
        *)
            echo "Refusing to overwrite unexpected kiosk launcher target: $target" >&2
            return 1
            ;;
    esac

    if [ -L "$target" ]; then
        echo "Refusing to overwrite symlinked kiosk launcher target: $target" >&2
        return 1
    fi

    if [ -e "$target" ] && [ ! -f "$target" ]; then
        echo "Refusing to overwrite non-file kiosk launcher target: $target" >&2
        return 1
    fi
}

write_kiosk_launcher() {
    local dashboard_ready_url="$DASHBOARD_URL"
    local launcher_tmp
    launcher_tmp="$(mktemp)"
    validate_kiosk_launcher_target "$KIOSK_LAUNCHER"
    cat > "$launcher_tmp" <<KIOSKSCRIPTEOF
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

if [ ! -x "$CHROMIUM_BIN" ]; then
    echo "Chromium executable is missing or not executable: $CHROMIUM_BIN" >&2
    exit 1
fi

for _ in \$(seq 1 60); do
    if curl -fsS "$dashboard_ready_url" >/dev/null 2>&1; then
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
rm -f "$RUN_HOME/.config/chromium/SingletonLock" \
      "$RUN_HOME/.config/chromium/SingletonSocket" \
      "$RUN_HOME/.config/chromium/SingletonCookie"

exec "$CHROMIUM_BIN" \
    --noerrdialogs \
    --disable-infobars \
    --kiosk \
    --start-fullscreen \
    --window-position=0,0 \
    --no-first-run \
    --disable-translate \
    --disable-features=TranslateUI \
    --overscroll-history-navigation=0 \
    --touch-events=enabled \
    --force-device-scale-factor=1 \
    --disable-gpu \
    --check-for-update-interval=31536000 \
    --simulate-outdated-no-au='Tue, 31 Dec 2099 23:59:59 GMT' \
    "$DASHBOARD_URL"
KIOSKSCRIPTEOF

    chmod +x "$launcher_tmp"
    if [ -f "$KIOSK_LAUNCHER" ]; then
        cp "$KIOSK_LAUNCHER" "$KIOSK_LAUNCHER.wmi-backup.$(date +%Y%m%d-%H%M%S)"
    fi
    mv "$launcher_tmp" "$KIOSK_LAUNCHER"
}

echo "[1/7] Installing system packages..."
sudo apt-get update -qq

PACKAGES=(
    ca-certificates
    python3-pip
    python3-venv
    nginx
    unclutter
    x11-xserver-utils
    xdotool
    git
    curl
)

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
install_dashboard_dependencies "$REPO_DIR/dashboard"
npm run build
cd "$REPO_DIR"

echo "[5/7] Configuring nginx..."
ensure_nginx_installed
deploy_dashboard_build "$DASHBOARD_BUILD_DIR" "$NGINX_DASHBOARD_ROOT"
sudo chown -R root:www-data "$NGINX_DASHBOARD_ROOT"
sudo find "$NGINX_DASHBOARD_ROOT" -type d -exec chmod 755 {} \;
sudo find "$NGINX_DASHBOARD_ROOT" -type f -exec chmod 644 {} \;
sudo mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
sudo tee /etc/nginx/sites-available/wmi-dashboard >/dev/null <<SERVEREOF
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
sudo nginx -t
sudo systemctl enable --now nginx

echo "[6/7] Installing bridge and kiosk services..."

sudo tee /etc/systemd/system/wmi-bridge.service >/dev/null <<BRIDGEEOF
[Unit]
Description=WMI Serial Bridge (ESP32 ↔ Dashboard)
After=network.target

[Service]
WorkingDirectory=$REPO_DIR
ExecStartPre=-/usr/bin/udevadm settle --timeout=10
ExecStart=$VENV_DIR/bin/python3 -m bridge.serial_bridge
Restart=on-failure
RestartSec=3
User=$RUN_USER
SupplementaryGroups=dialout
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=multi-user.target
BRIDGEEOF

CHROMIUM_BIN="$(resolve_chromium_bin)"
DASHBOARD_URL="$(build_dashboard_url "${WMI_DASHBOARD_URL:-http://localhost}" "${WMI_DISPLAY_PROFILE:-}")"

write_kiosk_launcher

sudo tee /etc/systemd/system/wmi-kiosk.service >/dev/null <<KIOSKEOF
[Unit]
Description=WMI Dashboard Kiosk (Chromium)
Wants=graphical.target display-manager.service network-online.target
After=graphical.target display-manager.service network-online.target nginx.service wmi-bridge.service

[Service]
WorkingDirectory=$REPO_DIR
Environment=HOME=$RUN_HOME
Environment=XAUTHORITY=$RUN_HOME/.Xauthority
ExecStartPre=/usr/bin/test -x $KIOSK_LAUNCHER
ExecStart=$KIOSK_LAUNCHER
Restart=on-failure
RestartSec=5
User=$RUN_USER

[Install]
WantedBy=graphical.target
KIOSKEOF

sudo tee /etc/systemd/system/wmi-unclutter.service >/dev/null <<UNCLUTTEREOF
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
