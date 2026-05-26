# Installation Guide

This guide covers the WMI Dashboard on the current supported Raspberry Pi display paths:

- Raspberry Pi 3 / Zero 2 W / Pi 4 / Pi 5
- Raspberry Pi OS Bookworm
- 5 inch landscape capacitive touch display connected to the Raspberry Pi DSI ribbon connector
- 3.5 inch GPIO/SPI displays including 52Pi, generic blue-board `3.5inch RPi Display` / LCDWiki-style HAT, and Waveshare 3.5inch RPi LCD (G)
- ESP32-S3 or ESP32-C3 controller connected to the Pi over USB serial

The Pi runs the React touch dashboard in a full-screen Chromium kiosk. A Python bridge service passes telemetry and settings between the dashboard and the ESP32 controller.

---

## 1. Flash the ESP32 controller

The ESP32 reads the MAP sensor, calculates pump duty cycle, controls the pump, and sends telemetry to the Raspberry Pi.

### Arduino IDE prerequisites

1. Install Arduino IDE 2.x.
2. Open **File** → **Preferences**.
3. Add this URL to **Additional boards manager URLs**:
   ```text
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```
4. Open **Tools** → **Board** → **Boards Manager** and install `esp32` by Espressif Systems.
5. Open **Sketch** → **Include Library** → **Manage Libraries** and install `ArduinoJson` version 7.x or later.

### Flashing steps

1. Connect the ESP32 to your computer over USB.
2. Open `esp32/wmi_controller/wmi_controller.ino`.
3. Select the correct board, for example **ESP32S3 Dev Module** or **ESP32C3 Dev Module**.
4. Select the ESP32 serial port.
5. Set **USB CDC On Boot** to **Enabled** when using native USB serial.
6. Adjust `esp32/wmi_controller/config.h` if your pinout differs. Everyday MAP calibration can now be selected later from the Pi Sensor Setup screen.
7. Upload the sketch.
8. Open Serial Monitor at `115200` baud and confirm the controller emits newline-terminated JSON frames.
### Pi-side firmware updates after installation

Once the Pi is installed in the car, you do not need a desktop IDE to update the sensor module. Use the Pi over SSH:

```bash
cd ~/WMI-Dashand-controller
./sensor-module-firmware.sh flash --board esp32-c3 --remember-board
```

That command will:

- install `Arduino CLI` on the Pi if it is missing
- install the stable Espressif `esp32` Arduino core
- install the `ArduinoJson` dependency
- stop `wmi-bridge.service` so the USB serial port is free
- compile the sketch for the chosen board
- upload the firmware to the connected sensor module
- start `wmi-bridge.service` again

After the first successful run, later updates can usually be done with:

```bash
./sensor-module-firmware.sh flash
```

Supported board keys:

- `esp32`
- `esp32-c3`
- `esp32-s3`

Important:
- The boxed sensor module should only accept `0-5V` MAP sensor or ECU analog-output signals.
- Do not connect any signal above `+5.0V`, or the WMI system can be damaged.

---

## 2. Prepare the Raspberry Pi 3

### SD card image

Use Raspberry Pi Imager.

Recommended test image:

```text
Raspberry Pi OS Bookworm 64-bit with Desktop
```

Bookworm Lite can also be used. If Lite is selected in the installer, the script installs LightDM/Openbox/X11 so the kiosk can run.

Important: some Lite/CLI-focused images do not have `git` installed by default. Before cloning this repo over SSH, run:

```bash
sudo apt update
sudo apt install -y git
```

Set these in Imager before writing:

- Hostname, for example `wmidash`
- SSH enabled
- Username and password
- Wi-Fi credentials if not using Ethernet

### Optional Windows one-shot SD prep helper

If you are preparing a Pi 3 + Bookworm Lite + 5-inch DSI card from Windows, this repo also includes:

```powershell
.\prepare-pi3-dsi-bookworm-sd.cmd
```

That helper script downloads the official Raspberry Pi OS Bookworm Lite image, verifies the SHA256, bundles the current working tree into a payload archive, and stages a first-boot script that automatically runs `setup.sh` for the `Pi 3 / Lite / 5 inch DSI` path.

Requirements:

- Raspberry Pi Imager installed on Windows
- an SD card reader attached to the Windows machine
- Internet access on the Pi during first boot so `apt`, `npm`, and setup dependencies can finish

If you only want to prepare the cached image, payload archive, and first-boot script without writing an SD card yet, run:

```powershell
.\prepare-pi3-dsi-bookworm-sd.ps1 -StageOnly
```

### Display connection

Power the Pi off before connecting the display.

Connect the 5 inch capacitive screen to the Raspberry Pi **DSI display connector** using the ribbon cable. This is the small flat-flex display connector near the end of the Pi board. It is not HDMI, not GPIO SPI, and not the camera CSI connector.

The integrated `setup.sh` script now includes these display choices:

- `1) 5 inch capacitive DSI ribbon display, landscape, usually 800x480`
- `2) 3.5 inch 52Pi/GPIO/SPI display, 480x320 landscape`
- `3) Generic 3.5inch RPi Display / LCDWiki-style HAT`
- `4) Waveshare 3.5inch RPi LCD (G) resistive touch`
- `5) Display already configured / skip display driver changes`

For the DSI choice, the installer does **not** install the old `LCD-show` / `MHS35-show` SPI display driver.

For the generic and Waveshare 3.5 inch choices, the panel is normally a GPIO HAT that plugs directly onto the Pi 40-pin header.

Default kiosk geometry:

```text
800x480 landscape
```

If your 5 inch DSI display uses another resolution, run the setup with overrides:

```bash
WMI_DISPLAY_WIDTH=1024 WMI_DISPLAY_HEIGHT=600 ./setup.sh
```

---

## 3. Install the Pi dashboard

SSH into the Pi, then run:

If `git --version` reports that `git` is missing, install it first:

```bash
sudo apt update
sudo apt install -y git
```

```bash
git clone https://github.com/DSSDiag/WMI-Dashand-controller.git
cd WMI-Dashand-controller
git checkout main
git pull --ff-only
chmod +x setup.sh
./setup.sh
```

When prompted, choose:

```text
Pi version: 2) Pi 3
OS type:    choose Lite or Full/Desktop to match your SD image
Display:    1) 5 inch capacitive DSI ribbon display, landscape, usually 800x480
```

For the generic 3.5 inch HAT path that was validated on the Pi Zero 2, choose:

```text
Pi version: 1) Pi Zero 2 W
OS type:    choose Lite or Full/Desktop to match your SD image
Display:    3) Generic 3.5inch RPi Display / LCDWiki-style HAT
```

Then reboot:

```bash
sudo reboot
```

The installer does the following:

- Installs system packages for X11, LightDM, Openbox, Chromium, nginx, Python, Node, and touch diagnostics.
- Creates Python virtual environments for the bridge and simulator.
- Builds the React dashboard.
- Serves the dashboard through nginx on port `80`.
- Configures graphical autologin where needed.
- Starts Chromium in full-screen kiosk mode at `http://localhost`.
- For the supported 3.5 inch SPI display profiles, the kiosk URL is tagged with the selected `?profile=...` value so the compact `480x320` layout and touch-optimized controls apply consistently on `52pi-k0403`, `generic-ili9486-hat`, and `waveshare-35g`.
- Installs `wmi-bridge.service` for ESP32 serial communication.
- Installs `wmi-kiosk.service` for the dashboard browser.
- Installs `wmi-unclutter.service` to hide the cursor.
- Adds the current user to the `dialout` group for serial access.

Fresh `setup.sh` installs also apply the branded Mild Modz Plymouth boot splash with the dashboard logo and a progress bar.

If you need to add that boot screen to an existing Pi later, run:

```bash
./apply-boot-splash.sh
```

---

## 4. What the DSI path changes

For the 5 inch DSI display, the installer:

- Removes old `waveshare35a` and `mhs35` overlay lines from `config.txt` if found.
- Leaves SPI display overlays alone unless the legacy 3.5 inch display option is selected.
- Sets `disable_fw_kms_setup=0`.
- Sets `max_framebuffers=2`.
- Forces the kiosk window to the selected geometry, default `800x480`.
- Adds an Openbox autostart command that attempts to set the connected display output to the selected mode with `xrandr` where the driver permits it.

For the 52Pi 3.5 inch GPIO/SPI display option, the script still runs the `LCD-show` / `MHS35-show` path.

For the generic blue-board 3.5 inch HAT, the installer:

- Runs `LCD35-show`
- Uses `dtoverlay=tft35a:rotate=90`
- Leaves the system on `multi-user.target`
- Auto-logs in on `tty1`
- Starts X with `startx`
- Launches Chromium from `.xinitrc` on the SPI panel through `fbcp`
- Opens the dashboard with the selected 3.5 inch display profile enabled so the small-screen layout matches that panel path

If your display is already configured and you use `setup-precomf.sh`, you can opt into the same compact layout with:

```bash
WMI_DASHBOARD_URL='http://localhost/?profile=generic-ili9486-hat' ./setup-precomf.sh
```

Replace `generic-ili9486-hat` with `52pi-k0403` or `waveshare-35g` when those match your panel.

---

## 5. After reboot checks

Run these from SSH after the Pi reboots.

### Check display output

```bash
xrandr --query
```

Expected result: one connected display, usually reporting `800x480` or your panel's native resolution.

### Check touch input

```bash
libinput list-devices
```

Expected result: a touch device appears. Capacitive DSI panels usually expose touch through the display stack or I2C/USB depending on the panel board.

### Check kiosk

```bash
sudo systemctl status wmi-kiosk
```

Restart it if needed:

```bash
sudo systemctl restart wmi-kiosk
```

### Check bridge

```bash
sudo systemctl status wmi-bridge
sudo journalctl -u wmi-bridge -f
```

### Check ESP32 serial device

```bash
ls /dev/ttyUSB* /dev/ttyACM* 2>/dev/null
```

### Run the quick post-boot health check

From the repo root on the Pi:

```bash
chmod +x verify-postboot.sh
./verify-postboot.sh
```

That helper checks:

- whether `xrandr` sees a connected display
- whether `libinput` sees input devices
- whether `http://localhost` responds
- whether `nginx`, `wmi-bridge`, and `wmi-kiosk` are active
- whether the ESP32 serial device is present under `/dev/ttyACM*` or `/dev/ttyUSB*`

---

## 6. Useful service commands

```bash
sudo systemctl restart wmi-bridge
sudo systemctl restart wmi-kiosk
sudo systemctl restart nginx
```

Follow bridge logs live:

```bash
sudo journalctl -u wmi-bridge -f
```

Follow kiosk logs live:

```bash
sudo journalctl -u wmi-kiosk -f
```

---

## 7. Troubleshooting

| Symptom | Likely cause | Check / fix |
|---|---|---|
| Backlight on, no dashboard | Kiosk or graphical session failed | `sudo systemctl status lightdm wmi-kiosk` |
| Desktop appears but no dashboard | Chromium kiosk failed | `sudo journalctl -u wmi-kiosk -n 80 --no-pager` |
| Dashboard appears but touch does nothing | Touch device not detected | `libinput list-devices` |
| Touch works but coordinates are rotated/wrong | Panel orientation mismatch | Check `xrandr --query`; confirm panel native landscape mode |
| Dashboard shows `OFF` badge | Bridge disconnected or no ESP32 serial device | `sudo systemctl status wmi-bridge`; `ls /dev/ttyUSB* /dev/ttyACM*` |
| Serial permission denied | User not in `dialout` until after reboot | Reboot, then retry |
| Old 3.5 inch SPI screen behaviour persists | Previous config still has a SPI display overlay | Re-run `./setup.sh`, choose the DSI display option, then reboot |

---

## 8. Manual development

Dashboard only:

```bash
cd dashboard
npm install
npm run dev
```

Bridge only:

```bash
cd bridge
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
python3 serial_bridge.py
```

Simulator:

```bash
cd simulation
python3 simulator.py
```
