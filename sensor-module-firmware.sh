#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKETCH_DIR="$REPO_DIR/esp32/wmi_controller"
BUILD_ROOT="$REPO_DIR/esp32/build"
CONFIG_FILE="${WMI_SENSOR_MODULE_CONFIG:-$HOME/.config/wmi-sensor-module.conf}"
ARDUINO_CLI_BIN="${ARDUINO_CLI_BIN:-$HOME/.local/bin/arduino-cli}"
ESP32_PACKAGE_URL="${ESP32_PACKAGE_URL:-https://espressif.github.io/arduino-esp32/package_esp32_index.json}"
BRIDGE_SERVICE="${WMI_SENSOR_MODULE_BRIDGE_SERVICE:-wmi-bridge.service}"
BRIDGE_VENV_PY="$REPO_DIR/bridge/.venv/bin/python3"

usage() {
    cat <<'EOF'
Usage:
  ./sensor-module-firmware.sh install-tools
  ./sensor-module-firmware.sh status [--board <esp32|esp32-c3|esp32-s3>] [--port <device>]
  ./sensor-module-firmware.sh build  [--board <esp32|esp32-c3|esp32-s3>] [--remember-board]
  ./sensor-module-firmware.sh flash  [--board <esp32|esp32-c3|esp32-s3>] [--port <device>] [--remember-board]
  ./sensor-module-firmware.sh list-boards

Notes:
  - This tool is designed for running directly on the Raspberry Pi over SSH.
  - It uses Arduino CLI rather than the full Arduino IDE.
  - The first run installs Arduino CLI, the ESP32 core, and ArduinoJson.
  - Flashing temporarily stops wmi-bridge.service so the serial port is free.
EOF
}

die() {
    echo "Error: $*" >&2
    exit 1
}

normalize_board_key() {
    local raw="${1:-}"
    case "${raw,,}" in
        esp32|esp32-devkit|basic) echo "esp32" ;;
        c3|esp32-c3|esp32c3|supermini|esp32-c3-supermini|esp32c3-supermini) echo "esp32-c3" ;;
        s3|esp32-s3|esp32s3) echo "esp32-s3" ;;
        *) return 1 ;;
    esac
}

fqbn_for_board() {
    case "$1" in
        esp32) echo "esp32:esp32:esp32" ;;
        esp32-c3) echo "esp32:esp32:esp32c3" ;;
        esp32-s3) echo "esp32:esp32:esp32s3" ;;
        *) return 1 ;;
    esac
}

load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # shellcheck disable=SC1090
        source "$CONFIG_FILE"
    fi
}

save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat > "$CONFIG_FILE" <<EOF
BOARD_KEY=$BOARD_KEY
EOF
}

arduino_cli() {
    if [ -x "$ARDUINO_CLI_BIN" ]; then
        "$ARDUINO_CLI_BIN" "$@"
        return
    fi
    command -v arduino-cli >/dev/null 2>&1 || die "arduino-cli is not installed"
    arduino-cli "$@"
}

ensure_arduino_cli() {
    if [ -x "$ARDUINO_CLI_BIN" ]; then
        return
    fi
    if command -v arduino-cli >/dev/null 2>&1; then
        ARDUINO_CLI_BIN="$(command -v arduino-cli)"
        return
    fi

    mkdir -p "$(dirname "$ARDUINO_CLI_BIN")"
    echo "Installing Arduino CLI into $(dirname "$ARDUINO_CLI_BIN")..."
    curl -fsSL https://raw.githubusercontent.com/arduino/arduino-cli/master/install.sh | BINDIR="$(dirname "$ARDUINO_CLI_BIN")" sh
}

ensure_esp32_toolchain() {
    ensure_arduino_cli

    echo "Refreshing Arduino board indexes..."
    arduino_cli core update-index --additional-urls "$ESP32_PACKAGE_URL"

    if ! arduino_cli core list | grep -q '^esp32:esp32'; then
        echo "Installing Espressif Arduino core..."
        arduino_cli core install esp32:esp32 --additional-urls "$ESP32_PACKAGE_URL"
    fi

    if ! arduino_cli lib list | grep -qi '^ArduinoJson'; then
        echo "Installing ArduinoJson library..."
        arduino_cli lib install ArduinoJson
    fi
}

detect_port() {
    if [ -n "${PORT:-}" ]; then
        echo "$PORT"
        return
    fi

    if [ -x "$BRIDGE_VENV_PY" ]; then
        local detected
        detected="$(cd "$REPO_DIR" && "$BRIDGE_VENV_PY" - <<'PY'
from bridge.serial_bridge import find_esp32_port
print(find_esp32_port() or "")
PY
)"
        if [ -n "$detected" ]; then
            echo "$detected"
            return
        fi
    fi

    local candidate
    for candidate in /dev/ttyACM* /dev/ttyUSB*; do
        if [ -e "$candidate" ]; then
            echo "$candidate"
            return
        fi
    done
}

print_status() {
    local fqbn=""
    [ -n "${BOARD_KEY:-}" ] && fqbn="$(fqbn_for_board "$BOARD_KEY")"
    local port=""
    port="$(detect_port || true)"

    echo "Repo:    $REPO_DIR"
    echo "Sketch:  $SKETCH_DIR"
    echo "CLI:     ${ARDUINO_CLI_BIN}"
    echo "Board:   ${BOARD_KEY:-unset}"
    echo "FQBN:    ${fqbn:-unset}"
    echo "Port:    ${port:-not detected}"
    echo "Config:  $CONFIG_FILE"
}

BRIDGE_WAS_ACTIVE=0

stop_bridge_if_needed() {
    if ! command -v systemctl >/dev/null 2>&1; then
        return
    fi
    if systemctl is-active --quiet "$BRIDGE_SERVICE"; then
        BRIDGE_WAS_ACTIVE=1
        echo "Stopping $BRIDGE_SERVICE so the sensor module port is free..."
        sudo systemctl stop "$BRIDGE_SERVICE"
    fi
}

restart_bridge_if_needed() {
    if [ "$BRIDGE_WAS_ACTIVE" -eq 1 ] && command -v systemctl >/dev/null 2>&1; then
        echo "Restarting $BRIDGE_SERVICE..."
        sudo systemctl start "$BRIDGE_SERVICE"
    fi
}

compile_firmware() {
    local fqbn="$1"
    BUILD_PATH="$BUILD_ROOT/$BOARD_KEY"
    mkdir -p "$BUILD_PATH"
    echo "Compiling sensor module firmware for $BOARD_KEY ($fqbn)..."
    arduino_cli compile \
        --fqbn "$fqbn" \
        --additional-urls "$ESP32_PACKAGE_URL" \
        --build-path "$BUILD_PATH" \
        "$SKETCH_DIR"
}

flash_firmware() {
    local fqbn="$1"
    local detected_port
    detected_port="$(detect_port || true)"
    [ -n "$detected_port" ] || die "No ESP32 sensor module serial port detected. Try --port /dev/ttyACM0"

    stop_bridge_if_needed
    trap restart_bridge_if_needed EXIT

    compile_firmware "$fqbn"

    echo "Uploading to $detected_port..."
    arduino_cli upload \
        --fqbn "$fqbn" \
        --additional-urls "$ESP32_PACKAGE_URL" \
        --input-dir "$BUILD_PATH" \
        --port "$detected_port" \
        "$SKETCH_DIR"

    echo "Sensor module flash complete."
}

COMMAND="${1:-flash}"
if [ "$#" -gt 0 ]; then
    shift
fi

load_config

BOARD_KEY="${WMI_SENSOR_MODULE_BOARD:-${BOARD_KEY:-}}"
PORT="${WMI_SENSOR_MODULE_PORT:-}"
REMEMBER_BOARD=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --board)
            [ "$#" -ge 2 ] || die "--board requires a value"
            BOARD_KEY="$(normalize_board_key "$2")" || die "Unsupported board: $2"
            shift 2
            ;;
        --port)
            [ "$#" -ge 2 ] || die "--port requires a value"
            PORT="$2"
            shift 2
            ;;
        --remember-board)
            REMEMBER_BOARD=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown option: $1"
            ;;
    esac
done

if [ -n "$BOARD_KEY" ]; then
    BOARD_KEY="$(normalize_board_key "$BOARD_KEY")" || die "Unsupported board: $BOARD_KEY"
fi

case "$COMMAND" in
    list-boards)
        cat <<'EOF'
esp32      -> esp32:esp32:esp32
esp32-c3   -> esp32:esp32:esp32c3
esp32-s3   -> esp32:esp32:esp32s3
EOF
        ;;
    install-tools)
        ensure_esp32_toolchain
        echo "Sensor module firmware toolchain is ready."
        ;;
    status)
        ensure_arduino_cli || true
        print_status
        ;;
    build|flash)
        [ -n "$BOARD_KEY" ] || die "No board selected. Pass --board esp32-c3 (or esp32 / esp32-s3)."
        FQBN="$(fqbn_for_board "$BOARD_KEY")" || die "Could not map board key to FQBN"
        ensure_esp32_toolchain
        if [ "$REMEMBER_BOARD" -eq 1 ]; then
            save_config
            echo "Saved default board selection: $BOARD_KEY"
        fi
        if [ "$COMMAND" = "build" ]; then
            compile_firmware "$FQBN"
            echo "Sensor module build complete."
        else
            flash_firmware "$FQBN"
        fi
        ;;
    *)
        usage
        die "Unknown command: $COMMAND"
        ;;
esac
