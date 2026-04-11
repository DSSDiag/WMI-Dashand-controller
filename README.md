# H₂O CH₃OH Injection Control System

A touch-screen Water/Methanol Injection (WMI) controller for Performance engines, built around a **Raspberry Pi Zero 2 W** dashboard and an **ESP32-S3** sensor/relay controller.

---

## System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│  Raspberry Pi Zero 2 W  (3.5" GPIO Touch Screen)                 │
│                                                                    │
│  ┌─────────────────┐    WebSocket      ┌──────────────────────┐  │
│  │  Chromium Kiosk │◄─── localhost ───►│  serial_bridge.py    │  │
│  │  React Dashboard│     port 8765     │  (Python asyncio)    │  │
│  │  (nginx :80)    │                   └──────────┬───────────┘  │
│  └─────────────────┘                              │ USB Serial   │
└──────────────────────────────────────────────────┼───────────────┘
                                                    │ 115200 baud
                                       ┌────────────▼──────────────┐
                                       │  ESP32-S3                  │
                                       │  • Reads MAP sensor (ADC)  │
                                       │  • PWM pump/relay output   │
                                       │  • Tank level input        │
                                       │  • Armed LED indicator     │
                                       └───────────────────────────┘
                                              │          │
                                         MAP sensor   Pump/Solenoid
                                         (manifold)   (WMI nozzle)
```

### Data flow
1. **ESP32** samples the MAP sensor every 100 ms, computes pump duty, drives the MOSFET via PWM, and sends a compact JSON telemetry frame over USB serial to the Pi.
2. **`serial_bridge.py`** (Python asyncio) receives those frames, converts pressure to PSI, and broadcasts them to any connected WebSocket clients.
3. **Dashboard** (React, built with Vite + Tailwind, served by nginx) connects to the bridge WebSocket at `ws://localhost:8765`, displays live pressure, and sends settings changes back through the bridge to the ESP32.

---

## Repository Layout

```
WMI-Dashand-controller/
├── dashboard/                 ← React touch-screen UI
│   ├── src/
│   │   ├── App.jsx            ← Main dashboard component
│   │   ├── main.jsx
│   │   └── index.css
│   ├── public/
│   │   └── logo.svg           ← Replace with your brand logo
│   ├── package.json
│   ├── tailwind.config.js
│   └── vite.config.js
├── bridge/
│   ├── serial_bridge.py       ← Python asyncio WebSocket ↔ serial bridge
│   └── requirements.txt
├── esp32/
│   └── wmi_controller/
│       ├── wmi_controller.ino ← Arduino sketch (ESP32-S3)
│       └── config.h           ← Pin assignments & sensor calibration
├── simulation/
│   ├── simulator.py           ← Interactive Python simulator for local dev
│   └── README.md
├── setup.sh                   ← Interactive hardware setup script
├── INSTALL.md                 ← Detailed hardware wiring & installation guide
└── README.md
```

---

## Dashboard Features

| Screen | Navigation | Description |
|---|---|---|
| **Dashboard** | Default | Live manifold pressure (large readout), pump flow %, injector animation, telemetry sparkline, session peak hold, tank status |
| **Settings** | Tap `›` | Pressure units, gauge scaling, injection mapping mode, map curve |

### Pressure Display
- **Units:** PSI · PSI+inHg · Bar · kPa
- **Reference:** Gauge (PSIg) or Absolute (PSIa) — selectable per unit
- **Auto-switching:** Below 0 PSI the gauge automatically shows vacuum in **inHg**; above 0 it shows **PSI** (in `psi+inhg` mode)
- **Out-of-range** warning: readout turns red if pressure falls outside your configured Min/Max

### Injection Mapping Modes

| Mode | Behaviour |
|---|---|
| **Thresholds** | Ramp from 0 % at *Injection Start* to 100 % at *100% Flow* pressure |
| **Full Scale** | Ramp linearly from 0 % at gauge Min to 100 % at gauge Max |
| **Manual** | Fixed duty cycle regardless of pressure — useful for bench testing |

### Map Curves

| Curve | Effect |
|---|---|
| **Linear** | Duty tracks pressure change 1:1 |
| **Exponential** | Duty rises slowly at first, then aggressively at high boost (quadratic) |

### Hardware vs. Simulation
A small connection badge in the header shows whether the dashboard is receiving live data.
During development, if you do not have an ESP32 connected, you can run the interactive software simulator in the `simulation/` directory. Boost builds and decays as if you were driving, and you can interact with the system using terminal commands. See `simulation/README.md` for details.

---

## Hardware

### Required Components

| Part | Notes |
|---|---|
| Raspberry Pi Zero 2 W | Any Pi with USB-OTG or USB-A works |
| 3.5″ GPIO touch screen | 320x480 Waveshare ST7796S SPI Display (forced to landscape 480x320) |
| ESP32-S3 DevKit | Any variant with USB-CDC (native USB) |
| Automotive MAP sensor | 1-bar (e.g. GM 12569240) or 2-bar (e.g. GM 16040749) |
| N-channel MOSFET module **or** 5V relay module | For pump/solenoid control |
| Float switch (NC) | Tank level sensor, active-low |
| 10 kΩ + 10 kΩ resistors | Voltage divider if MAP sensor outputs 5 V |

### Raspberry Pi GPIO Screen Wiring

The Waveshare 3.5″ ST7796S display is designed as a GPIO HAT — plug it directly onto the Pi's 40-pin header and all connections are made automatically.  If you need to wire it manually (e.g. via ribbon cable or breadboard), use the table below.

**SPI bus — display (ST7796S driver)**

| Display pin | Raspberry Pi GPIO | 40-pin header | Function |
|---|---|---|---|
| VCC | 3.3 V | Pin 1 | Power |
| GND | GND | Pin 6 | Ground |
| MOSI | GPIO 10 | Pin 19 | SPI0 MOSI |
| MISO | GPIO 9 | Pin 21 | SPI0 MISO |
| CLK | GPIO 11 | Pin 23 | SPI0 SCLK |
| CS | GPIO 8 | Pin 24 | SPI0 CE0 |
| DC | GPIO 25 | Pin 22 | Data / Command select |
| RST | GPIO 27 | Pin 13 | Hardware reset |
| BL | GPIO 18 | Pin 12 | Backlight (PWM) |

**I2C bus — capacitive touch (FT6336U controller)**

| Touch pin | Raspberry Pi GPIO | 40-pin header | Function |
|---|---|---|---|
| SDA | GPIO 2 | Pin 3 | I2C1 SDA |
| SCL | GPIO 3 | Pin 5 | I2C1 SCL |
| INT | GPIO 4 | Pin 7 | Touch interrupt (active-low) |

```
Pi 40-pin header (top view, pin 1 top-left)
 1 [3V3 ]─── VCC            2 [ 5V ]
 3 [SDA ]─── Touch SDA      4 [ 5V ]
 5 [SCL ]─── Touch SCL      6 [GND ]─── GND
 7 [GP4 ]─── Touch INT      8 [TX  ]
 9 [GND ]                  10 [RX  ]
11 [GP17]                  12 [GP18]─── BL
13 [GP27]─── RST           14 [GND ]
15 [GP22]                  16 [GP23]
17 [3V3 ]                  18 [GP24]
19 [GP10]─── MOSI          20 [GND ]
21 [GP9 ]─── MISO          22 [GP25]─── DC
23 [GP11]─── CLK           24 [GP8 ]─── CS
25 [GND ]                  26 [GP7 ]
...
```

> **Note:** `./setup.sh` automatically handles dependencies, networking, and system services (including graphical support for Lite OS). It also automatically triggers the display driver installation.

### ESP32-S3 Wiring

```
MAP Sensor (5V output)          ESP32-S3
  GND ──────────────────────────  GND
  Vcc ──────── 5V rail            —
  Vout ──┬── 10kΩ ─── GPIO4 ──── ADC (PIN_MAP_SENSOR)
         └── 10kΩ ─── GND        (voltage divider → 2.5V max)

Tank Level Float Switch
  One terminal ─────────────────  GND
  Other terminal ───────────────  GPIO6 (INPUT_PULLUP) (PIN_TANK_LEVEL)

Pump/Solenoid MOSFET Gate ──────  GPIO5 (PWM) (PIN_PUMP_PWM)
Armed LED ──────────────────────  GPIO48 (onboard LED)
USB (data) ──────────────────── Pi USB port
```

> **Note:** If your MAP sensor runs on 3.3 V, omit the voltage divider and set `MAP_VCC_MV 3300`, `MAP_V_MIN_MV 330`, `MAP_V_MAX_MV 2970` in `config.h`.

### MAP Sensor Calibration

Edit `esp32/wmi_controller/config.h` to match your sensor:

```c
#define MAP_V_MIN_MV   165.0f   // Vout at engine-off vacuum (~10 kPa abs)
#define MAP_V_MAX_MV  2970.0f   // Vout at max boost (adjust for 2-bar sensor)
#define MAP_KPA_MIN    10.0f
#define MAP_KPA_MAX   105.0f    // 210 kPa for 2-bar sensor
```

---

## Serial Protocol (ESP32 ↔ Pi)

All frames are newline-terminated JSON.

**ESP32 → Pi (100 ms):**
```json
{"t":"d","p":120.5,"d":75,"l":0}
```
| Key | Meaning |
|---|---|
| `t` | Frame type (`"d"` = data) |
| `p` | Manifold pressure — **kPa absolute** |
| `d` | Pump duty cycle — 0…100 |
| `l` | Tank low flag — 0 or 1 |

**Pi → ESP32 (on settings change):**
```json
{"t":"s","tm":0,"sp":137.9,"fp":275.8,"md":0,"c":0,"a":1}
```
| Key | Meaning |
|---|---|
| `tm` | Trigger mode: 0=thresholds 1=full_scale 2=manual |
| `sp` | Injection start — **kPa absolute** |
| `fp` | 100% flow — **kPa absolute** |
| `md` | Manual duty 0–100 |
| `c` | Curve: 0=linear 1=exponential |
| `a` | Armed: 0=off 1=armed |

**Pi → ESP32 (purge button):**
```json
{"t":"prime"}
```
Runs pump at 100 % for 2 seconds to purge air from lines.

---

## Installation

> For detailed step-by-step instructions including hardware wiring diagrams, see **[INSTALL.md](INSTALL.md)**.

### 1 — Flash the ESP32

1. Open `esp32/wmi_controller/wmi_controller.ino` in **Arduino IDE 2.x**
2. Install **ArduinoJson** (≥ 7.x) via Library Manager
3. Select board: **ESP32S3 Dev Module** (or your specific board)
4. Select `USB CDC On Boot: Enabled`
5. Edit `config.h` pin assignments if needed
6. Flash and verify serial output at 115200 baud

### 2 — Set up the Raspberry Pi

Flash Raspberry Pi OS (Bookworm, 64-bit) to your SD card.  
Enable SSH, connect to Wi-Fi, and boot.  
Clone this repo and run the setup script:

```bash
git clone https://github.com/DSSDiag/WMI-Dashand-controller.git
cd WMI-Dashand-controller
chmod +x setup.sh
./setup.sh
# The script will prompt for Pi version and OS type, and reboot automatically when display driver installs.
```

The script will:
- Install **nginx** and serve the built React app on port 80
- Install the **wmi-bridge** systemd service (auto-starts serial bridge)
- Install the **wmi-kiosk** systemd service (Chromium in kiosk mode, full screen)
- Install **unclutter** to hide the mouse cursor
- Add your user to the `dialout` group for serial port access

### 3 — Manual Development (laptop/desktop)

```bash
cd dashboard
npm install
npm run dev          # Vite dev server at http://localhost:5173
```

To view a live demo without serial hardware, start the interactive simulator in a separate terminal:
```bash
cd simulation
python3 simulator.py # See simulation/README.md for interactive commands
```

To test the bridge with a real ESP32:
```bash
cd bridge
pip install -r requirements.txt
python3 serial_bridge.py
```

---

## Systemd Services (Pi)

| Service | Description |
|---|---|
| `wmi-bridge.service` | Python serial bridge (auto-reconnects to ESP32) |
| `wmi-cap-touch.service` | Binds FT6336U capacitive touch controller (I2C1 0x38) to `edt_ft5x06` driver |
| `wmi-kiosk.service` | Chromium full-screen kiosk on `:0` |
| `wmi-unclutter.service` | Hides mouse cursor after 1 second |
| `nginx` | Serves built React dashboard on port 80 |

Useful commands:
```bash
sudo systemctl status wmi-bridge   # Check bridge logs
sudo journalctl -u wmi-bridge -f   # Follow bridge logs live
sudo systemctl restart wmi-kiosk   # Restart the browser
```

---

## Troubleshooting

| Symptom | Check |
|---|---|
| **Display shows backlight only (blank screen)** | X11 is rendering to HDMI (`/dev/fb0`) instead of the SPI display (`/dev/fb1`). Re-run `./setup.sh` and select the appropriate options. Verify with `cat /proc/fb` — you should see entry `1 FBTFT` |
| **Display blank — kiosk never starts** | Check `sudo systemctl status wmi-kiosk`. If it shows "can't open display :0", the graphical session hasn't started. Confirm lightdm is running (`sudo systemctl status lightdm`) and auto-login is configured (`/etc/lightdm/lightdm.conf.d/01-wmi-autologin.conf`) |
| Dashboard shows **OFF** badge | Bridge not running or no ESP32 detected — run `sudo systemctl status wmi-bridge` |
| Pressure reads ~−14.7 PSI at idle | Normal! That is atmospheric vacuum. Engine off = ~0 inHg on vacuum gauge |
| Pressure reads nonsense values | Re-calibrate `MAP_V_MIN_MV` / `MAP_V_MAX_MV` in `config.h` |
| Pump doesn't run | Check `settings.armed` — you must tap **ARM** on the dashboard first |
| Pump runs at wrong duty | Verify trigger mode and start/full thresholds in Settings |
| Serial port not found | Run `ls /dev/ttyUSB* /dev/ttyACM*` on the Pi; check `dialout` group membership |

---

## Logo

Replace `dashboard/public/logo.svg` with your own brand logo (SVG or PNG). Then rebuild:
```bash
cd dashboard && npm run build
```

---

## License

MIT — see [LICENSE](LICENSE).
