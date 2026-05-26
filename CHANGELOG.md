# Changelog

## 2026-05-22

- Added Pi-side sensor module flashing support and follow-up sensor configuration work, including the system-upgrade merge and MAP sensor mapping presets (`8dcc328`, `9b66a68`, `c489643`).
- Improved compact dashboard usability on small touch displays with stacked setup flows, larger touch targets, wrapped summaries and headers, touch-zoom prevention, and calibration/preset layout refinements (`3ad9925`, `08dc4ed`, `f3f53ee`, `e227a08`, `c717c20`, `aaa6de7`, `fbd7247`, `c9909be`, `0f7e116`, `50a0dcc`, `f727e20`, `31ed2e9`, `9301d58`, `306d9b2`, `ca19c7c`, `340b6f8`, `93ba138`).
- Hardened kiosk, installer, and deploy flows by tightening dashboard target resolution, launcher/profile handling, dependency install fallbacks, readiness checks, and the LCD-show checkout path (`f1542de`, `0856223`, `629e39e`, `645c643`, `dc52d41`, `0859fc0`, `5bb98eb`, `2d6a10f`, `88f6917`, `cf1708d`, `6cdefe7`).
- Strengthened runtime and verification coverage with the bridge event-loop fix, refreshed operator/flashing docs, and more stable compact layout test coverage (`c049a35`, `2f75f07`, `a37cae3`, `e1f2c18`).

### Key PRs

- No PR-numbered merges were recorded in repo history for this period.

## 2026-05-15

- Added Raspberry Pi installer support for the generic 3.5in `ILI9486/XPT2046` HAT and scoped the compact dashboard layout to that profile (`56c8394`, `d7d9889`, `54be8b8`).
- Improved small-display usability with compact settings, touch-layout hardening, dashboard fit refinements, and a fixed-resolution preview/test flow (`9d3567d`, `74d3833`, `77a2fdd`, `a074b6e`, `9d078c0`, `d448c21`).
- Tightened kiosk and setup behavior by preserving Openbox autostart and hardening installer write paths and service setup (`cc3a5b3`, `27f62ea`, `e1474ec`, `53528a3`, `5af6984`).
- Added branding polish with the Mild Modz logo asset and a branded Plymouth boot splash (`5b6dc1d`, `75b3142`).
- Strengthened security and maintenance with the XSS fix, localhost-only simulator binding, serial-bridge test coverage, and the patched PostCSS update ([#49](https://github.com/DSSDiag/WMI-Dashand-controller/pull/49), [#42](https://github.com/DSSDiag/WMI-Dashand-controller/pull/42), [#48](https://github.com/DSSDiag/WMI-Dashand-controller/pull/48), [#52](https://github.com/DSSDiag/WMI-Dashand-controller/pull/52)).

### Key PRs

- [#52](https://github.com/DSSDiag/WMI-Dashand-controller/pull/52) Bump `postcss` from `8.5.8` to `8.5.14` in `dashboard`
- [#49](https://github.com/DSSDiag/WMI-Dashand-controller/pull/49) Remove `dangerouslySetInnerHTML` to fix the dashboard XSS risk
- [#48](https://github.com/DSSDiag/WMI-Dashand-controller/pull/48) Add `find_esp32_port` unit tests and import-safety coverage
- [#47](https://github.com/DSSDiag/WMI-Dashand-controller/pull/47) Extract `preferred_keywords` constants in `benchmark.py`
- [#45](https://github.com/DSSDiag/WMI-Dashand-controller/pull/45) Remove the unused `functools` import from `serial_bridge.py`
- [#44](https://github.com/DSSDiag/WMI-Dashand-controller/pull/44) Remove the unused `sys` import from `simulation/simulator.py`
- [#43](https://github.com/DSSDiag/WMI-Dashand-controller/pull/43) Add the missing `start_psi` simulator edge-case test
- [#42](https://github.com/DSSDiag/WMI-Dashand-controller/pull/42) Bind the simulator WebSocket server to localhost
