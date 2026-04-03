# Hardware Installation & Setup

## Display Overview
This setup targets the **Waveshare 3.5" Capacitive Touch LCD Module** (320x480 resolution, ST7796S driver, FT6336U touch controller).

Because standard dashboard designs are often landscape, this display is configured to run at **480x320 landscape** mode via the `/boot/config.txt` file and Chromium parameters.

## Pin Connections (Pi to Waveshare Display)
Since the 3.5" display uses the SPI bus for video and I2C for capacitive touch, it requires multiple GPIO pins.

If you attach it directly to the Pi's GPIO header as a HAT, the pins are matched automatically.
If you are wiring manually using the FPC or 15-pin connector:
- **SPI0** (MOSI, MISO, SCLK, CE0/CE1) -> Video Data
- **I2C1** (SDA, SCL) -> Touch Data
- **3V3, 5V, GND** -> Power lines

## Setup Script Actions
The `pi-setup.sh` script automatically configures the following in `/boot/config.txt`:
1. `dtparam=spi=on`
2. `dtparam=i2c_arm=on`
3. `dtoverlay=waveshare35a:rotate=90` (Configures the SPI device tree overlay and forces the 320x480 portrait screen into 480x320 landscape)

Chromium is started with `--window-size=480,320` and `--force-device-scale-factor=1` to perfectly fit the viewport.

If touch axis inversion occurs after the rotation (e.g. up is right, down is left), it may require an additional `dtoverlay` touch transformation in `config.txt` depending on your kernel version. If necessary, refer to the Waveshare documentation for axis swapping configurations (e.g., `dtoverlay=waveshare35a,r270`, or `swapxy=1`).
