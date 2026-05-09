# WMI Interactive Simulator

This directory contains an interactive Python simulator (`simulator.py`) for the Water/Methanol Injection (WMI) system.

It allows you to view and test the React dashboard without needing the actual ESP32 hardware or the main serial bridge running. It spins up a local-only WebSocket server on `127.0.0.1:8765` and feeds simulated telemetry data (boost pressure, pump duty, tank status) to the dashboard.

## Requirements

The simulator requires `websockets`. On Raspberry Pi OS Bookworm (and other modern Debian-based systems), bare `pip install` is blocked by [PEP 668](https://peps.python.org/pep-0668/). There are two ways to install the dependency:

**Option A — Use the venv created by `setup.sh` (recommended on Pi):**

`setup.sh` automatically creates a virtual environment at `simulation/.venv` and installs `websockets` there. Activate it before running the simulator:

```bash
source simulation/.venv/bin/activate
python3 simulation/simulator.py
```

**Option B — Manual install with `--break-system-packages` (dev/desktop only):**

```bash
pip install websockets --break-system-packages
```

> ⚠️ Option B modifies system Python packages. Prefer Option A when in doubt.

## How to run

> **Important:** This is a Python script. Always run it with `python3`, not `bash`:
> ```bash
> python3 simulator.py   ✓ correct
> bash simulator.py      ✗ wrong — will produce import errors
> ```
> Alternatively, because the script has a `#!/usr/bin/env python3` shebang, you can
> run it directly after making it executable: `chmod +x simulator.py && ./simulator.py`

1. **Start the Dashboard:**
   In one terminal, start the React dashboard development server:
   ```bash
   cd dashboard
   npm install
   npm run dev
   ```

2. **Start the Simulator:**
   In a second terminal, start the interactive simulator:
   ```bash
   cd simulation
   python3 simulator.py
   ```

3. **Open the Dashboard:**
   Open `http://localhost:5173` in your browser. The connection badge in the top right should turn green, indicating it successfully connected to the simulated hardware.
   *Note: Because this branch targets the 3.5" GPIO display in landscape mode, the optimal viewing window size on your desktop is `480x320`.*

## Interactive Controls

The simulator runs an interactive CLI in the terminal window where it was started. You can type the following commands and press `Enter` to dynamically manipulate the data being sent to the dashboard:

| Command | Action |
|---|---|
| `t` | Toggle the tank fluid level sensor between OK and LOW. |
| `u` | Manually increase the manifold boost pressure by 5 PSI. |
| `d` | Manually decrease the manifold boost pressure by 5 PSI. |
| `a` | Toggle the system arming state (arms/disarms the pump). |
| `q` | Quit the simulator. |

When the system is armed (via the CLI or the dashboard), the simulator will automatically generate fluctuating boost pressure to mimic real-world engine behavior. You can override this behavior at any time using the `u` and `d` commands.
