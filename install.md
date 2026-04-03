# Hardware Installation & Setup

## Display Overview
This setup targets the **Waveshare 3.5" Capacitive Touch LCD Module** (320x480 resolution, ST7796S driver, FT6336U touch controller).

Because standard dashboard designs are often landscape, this display is configured to run at **480x320 landscape** mode via the `/boot/config.txt` file and Chromium parameters.

## Pin Connections (Pi to Waveshare Display)

The display is designed as a GPIO HAT — simply press it onto the Pi's 40-pin header and all connections are made automatically. If you need to wire it manually (e.g. using a ribbon cable or jumper wires), the tables below list every connection.

### SPI bus — display video (ST7796S driver)

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

### I2C bus — capacitive touch (FT6336U controller)

| Display label | Raspberry Pi GPIO | 40-pin header pin | Function |
|---|---|---|---|
| SDA | GPIO 2 | Pin 3 | I2C1 SDA |
| SCL | GPIO 3 | Pin 5 | I2C1 SCL |
| INT | GPIO 4 | Pin 7 | Touch interrupt (active-low) |

### Quick-reference wiring diagram

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

> **Note:** The `pi-setup.sh` script automatically enables `dtparam=spi=on`, `dtparam=i2c_arm=on`, and adds `dtoverlay=waveshare35a:rotate=90` to `/boot/config.txt` so the kernel drives the display with no extra manual configuration.

## Setup Script Actions
The `pi-setup.sh` script automatically configures the following in `/boot/config.txt`:
1. `dtparam=spi=on`
2. `dtparam=i2c_arm=on`
3. `dtoverlay=waveshare35a:rotate=90` (Configures the SPI device tree overlay and forces the 320x480 portrait screen into 480x320 landscape)

Chromium is started with `--window-size=480,320` and `--force-device-scale-factor=1` to perfectly fit the viewport.

If touch axis inversion occurs after the rotation (e.g. up is right, down is left), it may require an additional `dtoverlay` touch transformation in `config.txt` depending on your kernel version. If necessary, refer to the Waveshare documentation for axis swapping configurations (e.g., `dtoverlay=waveshare35a,r270`, or `swapxy=1`).
