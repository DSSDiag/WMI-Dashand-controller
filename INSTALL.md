# Installation Guide

This guide provides detailed, step-by-step instructions for loading the WMI Dashboard software onto the Raspberry Pi and the WMI Controller firmware onto the ESP32-S3 (or ESP32-C3).

---

## Hardware Wiring

### Display Overview
This setup targets the **Waveshare 3.5" Capacitive Touch LCD Module** (320x480 resolution, ST7796S driver, FT6336U touch controller).

Because standard dashboard designs are often landscape, this display is configured to run at **480x320 landscape** mode via the `/boot/config.txt` file and Chromium parameters.

### Pin Connections (Pi to Waveshare Display)

The display is designed as a GPIO HAT — simply press it onto the Pi's 40-pin header and all connections are made automatically. If you need to wire it manually (e.g. using a ribbon cable or jumper wires), the tables below list every connection.

#### SPI bus — display video (ST7796S driver)

| Display label | Raspberry Pi GPIO | 40-pin header pin | Function |
|---|---|---|---|
| VCC | 3.3 V | Pin 1 | Power |
| GND | GND | Pin 6 | Ground |
| MOSI | GPIO 10 | Pin 19 | SPI0 MOSI (data to display) |
| MISO | GPIO 9 | Pin 21 | SPI0 MISO (data from display) |
| CLK | GPIO 11 | Pin 23 | SPI0 SCLK (clock) |
| CS | GPIO 8 | Pin 24 | SPI0 CE0 (chip select) |
| DC | GPIO 25 | Pin 22 | Data / Command select |
| RST | GPIO 27 | Pin 13 | Hardware reset (active-low) |
| BL | GPIO 18 | Pin 12 | Backlight enable / PWM |

#### I2C bus — capacitive touch (FT6336U controller)

| Display label | Raspberry Pi GPIO | 40-pin header pin | Function |
|---|---|---|---|
| SDA | GPIO 2 | Pin 3 | I2C1 SDA |
| SCL | GPIO 3 | Pin 5 | I2C1 SCL |
| INT | GPIO 4 | Pin 7 | Touch interrupt (active-low) |

#### Quick-reference wiring diagram

```
Pi 40-pin header                      Waveshare 3.5" Display
(pin 1 = top-left)
                                       ┌──────────────┐
 Pin  1  [3V3 ] ─────────────────────► VCC            │
 Pin  6  [GND ] ─────────────────────► GND            │
 Pin 19  [GP10] ─────────────────────► MOSI  (SPI)   │
 Pin 21  [GP9 ] ─────────────────────► MISO  (SPI)   │
 Pin 23  [GP11] ─────────────────────► CLK   (SPI)   │
 Pin 24  [GP8 ] ─────────────────────► CS    (SPI)   │
 Pin 22  [GP25] ─────────────────────► DC             │
 Pin 13  [GP27] ─────────────────────► RST            │
 Pin 12  [GP18] ─────────────────────► BL             │
 Pin  3  [GP2 ] ─────────────────────► SDA   (I2C)   │
 Pin  5  [GP3 ] ─────────────────────► SCL   (I2C)   │
 Pin  7  [GP4 ] ─────────────────────► INT   (touch) │
                                       └──────────────┘
```

### Setup Script Actions
The `setup.sh` script automatically configures the following in `/boot/config.txt` (via LCD-show):
1. `dtparam=spi=on`
2. `dtparam=i2c_arm=on`
3. `dtoverlay=waveshare35a:rotate=90` (Configures the ST7796S SPI display overlay and forces the 320x480 portrait screen into 480x320 landscape)
4. `wmi-cap-touch.service` (systemd oneshot service that binds the FT6336U capacitive touch controller on I2C1 address 0x38 to the `edt_ft5x06` driver at each boot)

Chromium is started with `--window-size=480,320` and `--force-device-scale-factor=1` to perfectly fit the viewport.

If touch axis inversion occurs after the rotation (e.g. up is right, down is left), it may require an additional `dtoverlay` touch transformation in `config.txt` depending on your kernel version. If necessary, refer to the Waveshare documentation for axis swapping configurations (e.g., `dtoverlay=waveshare35a,r270`, or `swapxy=1`).

---

## 1. Setting up the ESP32 (Sensor & Pump Controller)

The ESP32 reads the MAP sensor, calculates pump duty cycle, controls the pump, and sends data to the Raspberry Pi.

### Prerequisites
1. Download and install [Arduino IDE 2.x](https://www.arduino.cc/en/software).
2. Open Arduino IDE, go to **File** -> **Preferences**.
3. In the "Additional boards manager URLs" field, add:
   `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
4. Go to **Tools** -> **Board** -> **Boards Manager**, search for `esp32` by Espressif Systems, and click **Install**.
5. Go to **Sketch** -> **Include Library** -> **Manage Libraries**, search for `ArduinoJson` (by Benoit Blanchon, version 7.x or later), and click **Install**.

### Flashing the Firmware
1. **Connect** your ESP32 board to your computer via USB.
2. In Arduino IDE, go to **File** -> **Open** and navigate to the repository directory.
3. Open the file `esp32/wmi_controller/wmi_controller.ino`.
4. In the top dropdown (or under **Tools** -> **Board**), select your specific ESP32 board (e.g., **ESP32S3 Dev Module** or **ESP32C3 Dev Module** depending on your hardware).
5. Under **Tools** -> **Port**, select the COM port (Windows) or `/dev/tty.*` port (macOS/Linux) corresponding to your ESP32.
6. Under **Tools** -> **USB CDC On Boot**, ensure it is set to **Enabled** (this is critical for the native USB serial communication with the Pi).
7. (Optional) Open the `config.h` file (the tab next to `wmi_controller.ino` in the IDE) to adjust pin assignments or MAP sensor calibration (e.g., `MAP_V_MIN_MV` and `MAP_V_MAX_MV`) if needed.
8. Click the **Upload** button (the right-pointing arrow at the top left). The IDE will compile and flash the firmware.
9. You can open the **Serial Monitor** (set to 115200 baud) to verify the ESP32 is outputting JSON data frames.

---

## 2. Setting up the Raspberry Pi (Touch Dashboard)

The Raspberry Pi runs the React-based touch dashboard in a full-screen Chromium kiosk and runs a Python bridge service to communicate with the ESP32.

> **Hardware wiring:** Before powering on, make sure the Waveshare 3.5″ display is attached to the Pi's 40-pin GPIO header. For full GPIO pin assignments (SPI display + I2C capacitive touch), see **[Hardware Wiring — Pin Connections](#pin-connections-pi-to-waveshare-display)** or the **[README Hardware section](README.md#raspberry-pi-gpio-screen-wiring)**.

### Prerequisites
1. You will need a Raspberry Pi Zero 2 W (or any Pi with USB-OTG/USB-A).
2. Download and install [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
3. Insert a micro SD card into your computer.
4. Open Raspberry Pi Imager.
   - Choose **Device**: Raspberry Pi Zero 2 W.
   - Choose **OS**: Raspberry Pi OS (Legacy, 64-bit) or standard Raspberry Pi OS (Bookworm, 64-bit) with Desktop.
   - Choose **Storage**: Select your SD card.
5. Click **Next** -> **Edit Settings**.
   - Set a hostname (e.g., `wmidash`).
   - Enable SSH (Use password authentication).
   - Set username (`pi`) and a secure password.
   - Configure your Wi-Fi settings (SSID and password).
6. Click **Save** and then **Write**. Wait for the process to complete, then insert the SD card into the Pi and power it on.

### Installation via Setup Script
1. Connect your ESP32 to the Raspberry Pi via USB.
2. Find the IP address of your Raspberry Pi on your network (e.g., via your router's admin page).
3. SSH into the Pi from your computer:
   ```bash
   ssh pi@<YOUR_PI_IP_ADDRESS>
   ```
4. Clone this repository to the Pi:
   ```bash
   git clone https://github.com/DSSDiag/WMI-Dashand-controller.git
   cd WMI-Dashand-controller
   ```
5. Make the setup script executable:
   ```bash
   chmod +x setup.sh
   ```
6. Run the automated setup script. This script prompts for your Pi version and OS type. It installs necessary packages (nginx, Python venv, Chromium), builds the React dashboard in `dashboard/`, and creates systemd services to run the Python bridge (`bridge/serial_bridge.py`) and the Chromium kiosk automatically on boot. Finally, it installs the 52Pi display driver and auto-reboots.
   ```bash
   ./setup.sh
   ```
7. Once the display driver installation finishes successfully, the Pi will reboot automatically.
8. On boot, the Pi should launch straight into the WMI Dashboard and automatically connect to the ESP32 to display live data.
