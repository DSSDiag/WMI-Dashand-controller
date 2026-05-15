# H2O CH3OH Injection Control System

A touch-screen Water/Methanol Injection controller built around a Raspberry Pi dashboard and a USB-connected ESP32 sensor module.

The Pi runs the dashboard and local web stack. The ESP32 handles live sensor input, pump output, and serial telemetry.

---

## Branch Guide

| Branch | Use it for |
|---|---|
| `main` | Stable/default install path. Best starting point for fresh installs. |
| `codex/system-upgrade-pass` | Latest in-progress Pi, dashboard, and tooling work. Includes Pi-side sensor-module flashing with `sensor-module-firmware.sh`. |
| `codex/sensor-module-awareness` | Staging branch for sensor-module detection, calibration, and boot-time awareness work. |

If you are not testing a specific feature, start from `main`. If you want the newest Pi-side ESP update tooling and latest bench-test changes, use `codex/system-upgrade-pass`.

---

## System Layout

```text
Raspberry Pi
  -> nginx + Chromium kiosk dashboard
  -> Python serial bridge
  -> USB serial @ 115200
  -> ESP32 sensor module
       -> MAP sensor / ECU analog input
       -> tank level input
       -> pump / solenoid output
```

---

## Supported Hardware

- Raspberry Pi Zero 2 W, Pi 3, Pi 4, or Pi 5
- Supported display profiles in `setup.sh`:
  - `dsi5` for 5 inch capacitive DSI ribbon displays
  - `52pi-k0403` for the 52Pi 3.5 inch SPI display
  - `generic-ili9486-hat` for generic blue-board `3.5inch RPi Display` / LCDWiki-style HAT panels
  - `waveshare-35g` for Waveshare `3.5inch RPi LCD (G)`
  - `preconfigured` when the display is already working and you only want the dashboard stack
- ESP32, ESP32-C3, or ESP32-S3 used as the sensor module
- MAP sensor or ECU analog pressure output
- Float switch for tank level
- Pump / solenoid driver hardware

Important safety rule:

- Only connect `0V` to `+5.0V` analog sensor or ECU outputs to the boxed sensor input.
- Do not feed `12V` or raw automotive switched power/signals into the WMI analog input.
- The hardware inside the box must condition the external signal safely for the ESP32 ADC.

---

## Dashboard Screens

| Screen | What it does |
|---|---|
| `Dashboard` | Live pressure, duty, injector animation, tank state, and telemetry |
| `Settings` | Pressure units, gauge scaling, injection mapping, and curve setup |
| `Sensor Setup` | Available on the newer sensor-calibration branches. Lets the user choose a preset MAP sensor or enter custom / ECU scaling. |

---

## Install The Pi

Fresh install on the stable branch:

```bash
git clone https://github.com/DSSDiag/WMI-Dashand-controller.git
cd WMI-Dashand-controller
git checkout main
git pull --ff-only
chmod +x setup.sh
./setup.sh
```

If you are testing newer work, replace `main` with the branch you want, for example:

```bash
git checkout codex/system-upgrade-pass
```

If the display is already configured and working, you can usually use:

```bash
chmod +x setup-precomf.sh
./setup-precomf.sh
```

For the generic `ILI9486/XPT2046` HAT, the compact layout is enabled with:

```bash
WMI_DASHBOARD_URL='http://localhost/?profile=generic-ili9486-hat' ./setup-precomf.sh
```

After install:

```bash
sudo reboot
```

For full Pi setup detail, display-specific notes, and troubleshooting, see [INSTALL.md](INSTALL.md).

---

## Update An Existing Pi

Pull the latest code and rerun the installer from the Pi:

```bash
cd ~/WMI-Dashand-controller
git fetch origin
git checkout main
git pull --ff-only
chmod +x setup.sh setup-precomf.sh
./setup.sh
```

If the display side is already known-good and you only want to refresh the dashboard/services:

```bash
cd ~/WMI-Dashand-controller
git fetch origin
git checkout main
git pull --ff-only
chmod +x setup-precomf.sh
./setup-precomf.sh
```

When you are testing another branch, replace `main` with that branch name.

---

## Flash The Sensor Module

There are two supported ways to update the ESP32 sensor module.

### Option A: Flash From A Desktop IDE

This works on every branch.

1. Install Arduino IDE 2.x.
2. Add the Espressif boards URL in Arduino preferences:

   ```text
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```

3. Install the `esp32` platform in Boards Manager.
4. Install `ArduinoJson` in Library Manager.
5. Open `esp32/wmi_controller/wmi_controller.ino`.
6. Select the correct board:
   - `ESP32 Dev Module`
   - `ESP32C3 Dev Module`
   - `ESP32S3 Dev Module`
7. Select the correct serial port.
8. Enable `USB CDC On Boot` when using a native-USB board.
9. Upload the sketch.
10. Verify newline-terminated JSON appears at `115200` baud.

### Option B: Flash From The Pi Over SSH

On branches that include `sensor-module-firmware.sh` such as `codex/system-upgrade-pass`, the Pi can compile and flash the sensor module itself.

For an `ESP32-C3 SuperMini`, first run:

```bash
cd ~/WMI-Dashand-controller
./sensor-module-firmware.sh status --board esp32-c3
./sensor-module-firmware.sh flash --board esp32-c3 --remember-board
```

After the board choice has been saved, later updates are just:

```bash
cd ~/WMI-Dashand-controller
./sensor-module-firmware.sh flash
```

Useful helper commands:

```bash
./sensor-module-firmware.sh list-boards
./sensor-module-firmware.sh status --board esp32-c3
./sensor-module-firmware.sh build --board esp32-s3
./sensor-module-firmware.sh flash --board esp32-c3 --port /dev/ttyACM0
```

What the Pi-side updater does:

- installs `arduino-cli` if needed
- installs the Espressif `esp32` core
- installs `ArduinoJson`
- stops `wmi-bridge.service` so the USB serial port is free
- compiles the sketch
- uploads the firmware
- starts `wmi-bridge.service` again

Supported board keys:

- `esp32`
- `esp32-c3`
- `esp32-s3`

---

## Sensor Module Wiring Overview

```text
External MAP sensor or ECU analog output
  GND    -> sensor module GND
  Signal -> boxed analog input (0-5V max)

Tank level float switch
  one side -> GND
  other    -> tank-level input

Pump / solenoid driver
  control input <- ESP32 pump output

USB
  ESP32 sensor module <-> Raspberry Pi
```

Board-specific pins and default calibration live in `esp32/wmi_controller/config.h`.

---

## Useful Commands

Check the bridge:

```bash
sudo systemctl status wmi-bridge
sudo journalctl -u wmi-bridge -f
```

Check dashboard serving:

```bash
curl -I http://localhost
```

Check for the sensor module serial port:

```bash
ls /dev/ttyACM* /dev/ttyUSB* 2>/dev/null
```

Restart services:

```bash
sudo systemctl restart wmi-bridge
sudo systemctl restart wmi-kiosk
sudo systemctl restart nginx
```

---

## Troubleshooting

| Symptom | What to check |
|---|---|
| Dashboard shows hardware disconnected | `sudo systemctl status wmi-bridge` and `ls /dev/ttyACM* /dev/ttyUSB*` |
| ESP only comes online after unplug/replug | Review `sudo journalctl -u wmi-bridge -b` and confirm the USB cable/port is stable on boot |
| Pi-side flash says port not detected | Recheck the USB connection, then run `./sensor-module-firmware.sh status --board esp32-c3` |
| Display works but no dashboard shows | Check `nginx`, `wmi-kiosk`, or the `tty1/startx` session depending on the selected display profile |
| Pressure reading is wrong | Confirm the correct MAP preset or custom calibration is selected, or review `config.h` defaults |
| Pump never ramps | Confirm the system is armed, tank level is not low, and the selected pressure calibration matches the real sensor |

---

## Repository Layout

```text
dashboard/                  React kiosk UI
bridge/                     Python serial/WebSocket bridge
esp32/wmi_controller/       Sensor-module firmware
simulation/                 Local simulator tools
setup.sh                    Interactive Pi installer
setup-precomf.sh            Installer for already-configured displays
INSTALL.md                  Full installation guide
README.md                   Quick operator/developer guide
```

---

## License

MIT. See [LICENSE](LICENSE).
