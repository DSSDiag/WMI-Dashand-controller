# Installation Guide

This guide provides detailed, step-by-step instructions for loading the WMI Dashboard software onto the Raspberry Pi and the WMI Controller firmware onto the ESP32-S3 (or ESP32-C3).

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
   chmod +x pi-setup.sh
   ```
6. Run the automated setup script. This script installs necessary packages (nginx, Python venv, Chromium), builds the React dashboard in `dashboard/`, and creates systemd services to run the Python bridge (`bridge/serial_bridge.py`) and the Chromium kiosk automatically on boot.
   ```bash
   ./pi-setup.sh
   ```
7. Once the script finishes successfully, reboot the Pi:
   ```bash
   sudo reboot
   ```
8. On boot, the Pi should launch straight into the WMI Dashboard and automatically connect to the ESP32 to display live data.
