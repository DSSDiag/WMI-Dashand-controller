# H₂O CH₃OH Injection Control System

A touch-screen Water/Methanol Injection (WMI) controller for performance engines.

This branch adds support for the current bench-test hardware:

- **Raspberry Pi 3** dashboard computer
- **5 inch landscape capacitive touch display** connected by the Raspberry Pi **DSI ribbon connector**
- **ESP32-S3 / ESP32-C3** sensor and pump controller over USB serial

The older 3.5 inch GPIO/SPI screen path is still available from the interactive installer, but the new target is the Pi 3 + DSI ribbon display.

---

## System Architecture

```text
┌──────────────────────────────────────────────────────────────────┐
│  Raspberry Pi 3 + 5 inch DSI capacitive touch display             │
│                                                                    │
│  ┌─────────────────┐    WebSocket      ┌──────────────────────┐  │
│  │  Chromium Kiosk │◄─── localhost ───►│  serial_bridge.py    │  │
│  │  React Dashboard│     port 8765     │  Python asyncio      │  │
│  │  nginx :80      │                   └──────────┬───────────┘  │
│  └─────────────────┘                              │ USB Serial   │
└──────────────────────────────────────────────────┼───────────────┘
                                                    │ 115200 baud
                                       ┌────────────▼──────────────┐
                                       │  ESP32-S3 / ESP32-C3       │
                                       │  • Reads MAP sensor ADC    │
                                       │  • PWM pump/relay output   │
                                       │  • Tank level input        │
                                       │  • Armed LED indicator     │
                                       └───────────────────────────┘
                                              │          │
                                         MAP sensor   Pump/Solenoid
                                         manifold     WMI nozzle
```

### Data flow

1. The ESP32 samples the MAP sensor, computes pump duty, drives the pump/solenoid output, and sends JSON telemetry over USB serial.
2. `bridge/serial_bridge.py` receives those frames, converts pressure to PSI, and broadcasts them to dashboard clients over WebSocket.
3. The React dashboard connects to `ws://localhost:8765`, displays live pressure and pump state, and sends settings changes back to the ESP32 through the bridge.

---

## Repository Layout

```text
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
│       ├── wmi_controller.ino ← Arduino sketch
│       └── config.h           ← Pin assignments and sensor calibration
├── simulation/
│   ├── simulator.py           ← Interactive Python simulator for local dev
│   └── README.md
├── setup.sh                   ← Interactive hardware setup script
├── INSTALL.md                 ← Detailed install guide
└── README.md
```

---

## Dashboard Features

| Screen | Navigation | Description |
|---|---|---|
| **Dashboard** | Default | Live manifold pressure, pump flow %, injector animation, telemetry sparkline, peak hold, tank status |
| **Settings** | Tap `›` | Pressure units, gauge scaling, injection mapping mode, map curve |
| **Sensor Setup** | Tap `›` again from Settings | Choose a 1/2/3/4 bar preset or enter Custom / ECU calibration, with direct-connect `+5V max` guidance |

### Pressure Display

- **Units:** PSI, PSI+inHg, Bar, kPa
- **Reference:** Gauge or Absolute where applicable
- **Auto-switching:** `psi+inhg` shows vacuum below 0 PSI as inHg and boost above 0 as PSI
- **Out-of-range warning:** readout turns red when pressure falls outside configured Min/Max

### Injection Mapping Modes

| Mode | Behaviour |
|---|---|
| **Thresholds** | Ramp from 0% at Injection Start to 100% at 100% Flow pressure |
| **Full Scale** | Ramp linearly from gauge Min to gauge Max |
| **Manual** | Fixed duty cycle for bench testing |

### Map Curves

| Curve | Effect |
|---|---|
| **Linear** | Duty tracks pressure change 1:1 |
| **Exponential** | Duty rises slowly first, then harder at high boost |

---

## Hardware

### Required Components

| Part | Notes |
|---|---|
| Raspberry Pi 3 / Zero 2 W / Pi 4 / Pi 5 | Current installer targets |
| Display | Supported profiles include a 5 inch capacitive DSI ribbon display, 52Pi 3.5 inch SPI display, generic blue-board `3.5inch RPi Display` / LCDWiki-style HAT, and Waveshare 3.5inch RPi LCD (G) |
| ESP32-S3 or ESP32-C3 DevKit | Native USB serial recommended |
| Automotive MAP sensor or ECU analog output | Direct-connect only if the signal stays between `0V` and `+5V`; select the profile in Sensor Setup |
| N-channel MOSFET module or 5V relay module | Pump/solenoid output |
| Float switch, NC preferred | Tank level sensor, active-low |
| Sensor input conditioning inside the box | The boxed sensor module should scale the external `0-5V` signal safely down to the ESP32 ADC |

### Raspberry Pi display note

The integrated installer now supports these display profiles in `setup.sh`:

- `dsi5`: 5 inch capacitive DSI ribbon display, default `800x480` landscape
- `52pi-k0403`: 52Pi 3.5 inch GPIO/SPI display, `480x320` landscape via `MHS35-show`
- `generic-ili9486-hat`: generic blue-board `3.5inch RPi Display` / LCDWiki-style HAT, `480x320` landscape via `LCD35-show` + `fbcp`
- `waveshare-35g`: Waveshare 3.5inch RPi LCD (G), `320x480` portrait via Bookworm SPI overlays
- `preconfigured`: skips display driver changes and only installs the dashboard stack

For the Pi 3 / 5 inch capacitive panel, use the **DSI display connector**. This is the small flat-flex connector for displays at the end of the Pi board. It is not HDMI, not GPIO SPI, and not the camera CSI connector.

The installer’s DSI path does **not** install the old `LCD-show` / `MHS35-show` SPI driver. It also removes previous `waveshare35a` / `mhs35` overlay lines from `config.txt` if this SD card was used for earlier 3.5 inch display tests.

For the generic and Waveshare 3.5 inch profiles, the display is designed as a GPIO HAT and normally plugs directly onto the Pi 40-pin header with no separate ribbon or jumper wiring.

The generic `ILI9486/XPT2046` HAT profile now tags the kiosk URL with `?profile=generic-ili9486-hat`, which keeps the compact `480x320` layout changes isolated to that screen path. If you install with `setup-precomf.sh`, you can opt into the same layout with:

```bash
WMI_DASHBOARD_URL='http://localhost/?profile=generic-ili9486-hat' ./setup-precomf.sh
```

Default kiosk geometry:

```text
800x480 landscape
```

Override the geometry if your panel is different:

```bash
WMI_DISPLAY_WIDTH=1024 WMI_DISPLAY_HEIGHT=600 ./setup.sh
```

### Boot splash retrofit

`setup.sh` already applies the branded Mild Modz Plymouth boot splash during a fresh install. For an already-running Pi that missed that step, run:

```bash
./apply-boot-splash.sh
```

That installs the logo + progress bar theme, updates the Pi boot flags, and leaves timestamped backups of `config.txt` and `cmdline.txt` beside the originals.

### Sensor Module Wiring

```text
MAP Sensor / ECU analog output    Sensor module box
  GND ──────────────────────────── GND
  Signal ───────────────────────── boxed 0-5V analog input

Inside the box:
  analog input conditioning ───── GPIO4 ADC PIN_MAP_SENSOR
  never exceed +5.0V at the boxed analog input

Tank Level Float Switch
  One terminal ───────────────── GND
  Other terminal ─────────────── GPIO6 INPUT_PULLUP PIN_TANK_LEVEL

Pump/Solenoid MOSFET Gate ────── GPIO5 PWM PIN_PUMP_PWM
Armed LED ────────────────────── board-default armed LED pin
USB data ─────────────────────── Raspberry Pi USB port
```

The Pi dashboard now exposes a Sensor Setup screen with 1/2/3/4 bar presets plus Custom / ECU calibration. The compile-time values in `config.h` remain as safe defaults if the Pi has not yet pushed a live calibration profile:

```c
#define MAP_VCC_MV    3300.0f
#define MAP_V_MIN_MV   330.0f
#define MAP_V_MAX_MV  2970.0f
```

---

## Serial Protocol

All frames are newline-terminated JSON.

ESP32 to Pi:

```json
{"t":"d","p":120.5,"d":75,"l":0}
```

| Key | Meaning |
|---|---|
| `t` | Frame type, `"d"` = data |
| `p` | Manifold pressure in kPa absolute |
| `d` | Pump duty cycle, 0 to 100 |
| `l` | Tank low flag, 0 or 1 |

Pi to ESP32 settings frame:

```json
{"t":"s","tm":0,"sp":137.9,"fp":275.8,"md":0,"c":0,"a":1,"vmn":165.0,"vmx":2970.0,"kmn":10.0,"kmx":315.0}
```

| Key | Meaning |
|---|---|
| `tm` | Trigger mode: 0 thresholds, 1 full_scale, 2 manual |
| `sp` | Injection start in kPa absolute |
| `fp` | 100% flow in kPa absolute |
| `md` | Manual duty, 0 to 100 |
| `c` | Curve: 0 linear, 1 exponential |
| `a` | Armed: 0 off, 1 armed |
| `vmn` / `vmx` | Calibrated ADC-side millivolt span for the selected sensor profile |
| `kmn` / `kmx` | Calibrated pressure span in kPa absolute |

Pi to ESP32 purge frame:

```json
{"t":"prime"}
```

---

## Installation

Detailed steps are in [INSTALL.md](INSTALL.md).

Quick branch install on the Pi:

```bash
git clone https://github.com/DSSDiag/WMI-Dashand-controller.git
cd WMI-Dashand-controller
git fetch origin
git checkout rpi3-5inch-dsi-install
chmod +x setup.sh
./setup.sh
```

When prompted, choose:

```text
Pi:       2) Pi 3
OS:       your installed OS type
Display:  1) 5 inch capacitive DSI ribbon display
```

Then reboot when the script finishes:

```bash
sudo reboot
```

The script installs nginx, Chromium kiosk mode, LightDM/Openbox autologin, the Python bridge service, cursor hiding, and serial permissions.

---

## Systemd Services

| Service | Description |
|---|---|
| `wmi-bridge.service` | Python serial bridge between ESP32 and dashboard |
| `wmi-kiosk.service` | Chromium full-screen kiosk on display `:0` |
| `wmi-unclutter.service` | Hides mouse cursor after 1 second |
| `nginx` | Serves built dashboard on port 80 |

Useful commands:

```bash
sudo systemctl status wmi-bridge
sudo journalctl -u wmi-bridge -f
sudo systemctl restart wmi-kiosk
```

---

## Troubleshooting

| Symptom | Check |
|---|---|
| Display/backlight works but no dashboard | `sudo systemctl status lightdm wmi-kiosk` |
| Touch not working | `libinput list-devices` |
| Dashboard shows `OFF` badge | `sudo systemctl status wmi-bridge` and `ls /dev/ttyUSB* /dev/ttyACM*` |
| Pressure reads nonsense values | Re-calibrate `MAP_V_MIN_MV` / `MAP_V_MAX_MV` in `config.h` |
| Pump does not run | Dashboard must be armed, and pump output wiring must match `config.h` |
| Serial port not found | Check ESP32 USB cable, board mode, and `/dev/ttyUSB*` / `/dev/ttyACM*` |

---

## Logo

Replace `dashboard/public/logo.svg`, then rebuild:

```bash
cd dashboard
npm run build
```

---

## License

MIT — see [LICENSE](LICENSE).
