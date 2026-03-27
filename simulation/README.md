# WMI Interactive Simulator

This directory contains an interactive Python simulator (`simulator.py`) for the Water/Methanol Injection (WMI) system.

It allows you to view and test the React dashboard without needing the actual ESP32 hardware or the main serial bridge running. It spins up a local WebSocket server on port `8765` and feeds simulated telemetry data (boost pressure, pump duty, tank status) to the dashboard.

## Requirements

The simulator requires `websockets`. You can install it using pip:

```bash
pip install websockets
```

## How to run

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
