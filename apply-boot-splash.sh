#!/usr/bin/env bash
# apply-boot-splash.sh - Enable the Mild Modz Plymouth boot splash on an
# already-installed Raspberry Pi system.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGO_SOURCE="$REPO_DIR/dashboard/public/logo.png"
THEME_DIR="/usr/share/plymouth/themes/mild-modz"

need_sudo() {
    if [ "${EUID}" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}

boot_config_path() {
    if [ -f /boot/firmware/config.txt ]; then
        echo /boot/firmware/config.txt
    else
        echo /boot/config.txt
    fi
}

boot_cmdline_path() {
    if [ -f /boot/firmware/cmdline.txt ]; then
        echo /boot/firmware/cmdline.txt
    else
        echo /boot/cmdline.txt
    fi
}

set_boot_config_value() {
    local boot_config="$1"
    local key="$2"
    local value="$3"

    grep -q "^${key}=" "$boot_config" \
        && need_sudo sed -i "s/^${key}=.*/${key}=${value}/" "$boot_config" \
        || printf '%s=%s\n' "$key" "$value" | need_sudo tee -a "$boot_config" >/dev/null
}

set_boot_cmdline_token() {
    local boot_cmdline="$1"
    local cmdline
    cmdline="$(need_sudo tr -d '\n' < "$boot_cmdline")"

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

    printf '%s\n' "$cmdline" | need_sudo tee "$boot_cmdline" >/dev/null
}

configure_plymouth_theme() {
    if [ ! -f "$LOGO_SOURCE" ]; then
        echo "Logo asset not found at $LOGO_SOURCE"
        exit 1
    fi

    need_sudo mkdir -p "$THEME_DIR"
    need_sudo cp "$LOGO_SOURCE" "$THEME_DIR/logo.png"
    printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAICAYAAAA4GpVBAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAQSURBVBhXYxCXUfnPQJgAAMroCrHpRHBSAAAAAElFTkSuQmCC' | base64 -d | need_sudo tee "$THEME_DIR/bar-bg.png" >/dev/null
    printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAAICAYAAAA4GpVBAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAQSURBVBhXY1j8n+E/A2ECAKSDFQmK/XW8AAAAAElFTkSuQmCC' | base64 -d | need_sudo tee "$THEME_DIR/bar-fg.png" >/dev/null

    need_sudo tee "$THEME_DIR/mild-modz.plymouth" >/dev/null <<'PLYMOUTHEOF'
[Plymouth Theme]
Name=Mild Modz
Description=Mild Modz kiosk boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/mild-modz
ScriptFile=/usr/share/plymouth/themes/mild-modz/mild-modz.script
PLYMOUTHEOF

    need_sudo tee "$THEME_DIR/mild-modz.script" >/dev/null <<'SCRIPTEOF'
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

    need_sudo plymouth-set-default-theme -R mild-modz || need_sudo update-alternatives --set default.plymouth "$THEME_DIR/mild-modz.plymouth" || true
    need_sudo update-initramfs -u || true
}

echo "Installing Plymouth packages if needed..."
need_sudo apt-get update -qq
need_sudo apt-get install -y --no-install-recommends plymouth plymouth-themes

BOOT_CONFIG="$(boot_config_path)"
BOOT_CMDLINE="$(boot_cmdline_path)"
STAMP="$(date +%Y%m%d-%H%M%S)"

need_sudo cp "$BOOT_CONFIG" "${BOOT_CONFIG}.wmi-backup.${STAMP}"
need_sudo cp "$BOOT_CMDLINE" "${BOOT_CMDLINE}.wmi-backup.${STAMP}"

echo "Configuring Mild Modz boot splash..."
set_boot_config_value "$BOOT_CONFIG" "disable_splash" "1"
set_boot_cmdline_token "$BOOT_CMDLINE"
configure_plymouth_theme

echo ""
echo "Mild Modz boot splash installed."
echo "Reboot to see the logo + progress bar:"
echo "  sudo reboot"
