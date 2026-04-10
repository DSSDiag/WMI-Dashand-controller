#!/usr/bin/env python3
"""
WMI Serial Bridge — Raspberry Pi Zero 2 W
==========================================
Sits between the ESP32-S3 (USB serial) and the dashboard browser (WebSocket).

  ESP32-S3  ──USB──►  [serial_bridge.py]  ──WS──►  Chromium (dashboard)
                                          ◄──WS──   (settings changes)

JSON frames the ESP32 sends (newline-terminated):
  {"t":"d","p":120.5,"d":75,"l":0}
    t = frame type ("d" = data, "e" = error, "v" = version)
    p = manifold pressure in kPa absolute
    d = pump duty cycle 0-100
    l = tank level (0 = OK, 1 = LOW)

JSON frames the bridge sends to the ESP32:
  {"t":"s","tm":0,"sp":137.9,"fp":275.8,"md":0,"c":0,"a":1}
    t  = "s" (settings)
    tm = trigger_mode: 0=thresholds, 1=full_scale, 2=manual
    sp = injection start pressure kPa absolute
    fp = full-flow pressure kPa absolute
    md = manual duty 0-100
    c  = curve: 0=linear, 1=exponential
    a  = system armed: 0/1

WebSocket frames (browser ↔ bridge):
  Inbound  (browser→bridge): {"type":"settings", ...}  {"type":"prime"}
  Outbound (bridge→browser): {"type":"telemetry","pressure_psi":float,"pump_duty":int,"tank_low":bool,"pressure_kpa":float}
"""

import asyncio
import json
import logging
import os
import sys
import time
import functools
from typing import Optional, Set

import serial
import serial.tools.list_ports
import websockets
from websockets.asyncio.server import ServerConnection

from bridge.logic import parse_esp32_frame, build_settings_frame

# ── Configuration ──────────────────────────────────────────────────────────────
WS_HOST          = "0.0.0.0"
WS_PORT          = 8765
SERIAL_BAUD      = 115200
SERIAL_TIMEOUT   = 1.0
RECONNECT_DELAY  = 3.0   # seconds between ESP32 reconnect attempts
WATCHDOG_TIMEOUT = 5.0   # seconds without data before marking disconnected

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("wmi-bridge")

# ── Shared state ───────────────────────────────────────────────────────────────
clients: Set[ServerConnection] = set()
latest_telemetry: dict = {}
pending_settings: Optional[dict] = None   # set by WebSocket handler, consumed by serial loop
pending_prime: bool = False


def find_esp32_port() -> Optional[str]:
    """Scan serial ports and return the most likely ESP32 port."""
    preferred_keywords = [
        "cp210", "ch340", "ch9102", "ftdi", "usb serial",
        "usb-serial", "ttyusb", "ttyacm",
    ]
    ports = list(serial.tools.list_ports.comports())
    for port in ports:
        desc_lower = f"{port.description or ''} {port.hwid or ''}".lower()
        dev_lower = port.device.lower()
        if any(kw in desc_lower or kw in dev_lower for kw in preferred_keywords):
            return port.device
    # Fallback: first available port
    return ports[0].device if ports else None


# ── WebSocket server ───────────────────────────────────────────────────────────
async def ws_handler(ws: ServerConnection):
    global pending_settings, pending_prime
    clients.add(ws)
    log.info("Browser connected  (total: %d)", len(clients))

    # Send latest telemetry immediately so UI doesn't wait for next serial frame
    if latest_telemetry:
        await ws.send(json.dumps(latest_telemetry))

    try:
        async for message in ws:
            try:
                msg = json.loads(message)
                if msg.get("type") == "settings":
                    pending_settings = msg
                    log.debug("Settings queued: %s", msg)
                elif msg.get("type") == "prime":
                    pending_prime = True
                    log.info("Purge/prime triggered by UI")
            except json.JSONDecodeError:
                pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        clients.discard(ws)
        log.info("Browser disconnected (total: %d)", len(clients))


async def broadcast(payload: dict):
    """Send telemetry to all connected browsers."""
    if not clients:
        return
    msg = json.dumps(payload)
    await asyncio.gather(
        *(ws.send(msg) for ws in list(clients)),
        return_exceptions=True,
    )


# ── Serial loop ────────────────────────────────────────────────────────────────
async def handle_serial_connection(ser: serial.Serial):
    global pending_settings, pending_prime, latest_telemetry

    last_data = time.monotonic()
    ser.reset_input_buffer()
    while True:
        # ── Flush outgoing messages ──
        if pending_prime:
            pending_prime = False
            await asyncio.get_running_loop().run_in_executor(
                None, ser.write, b'{"t":"prime"}\n'
            )
            log.info("Prime pulse sent to ESP32")

        if pending_settings:
            frame = build_settings_frame(pending_settings)
            pending_settings = None
            await asyncio.get_running_loop().run_in_executor(
                None, ser.write, frame
            )
            log.debug("Settings sent: %s", frame)

        # ── Read incoming ──
        line = await asyncio.get_event_loop().run_in_executor(
            None, ser.readline
        )
        line = line.decode("utf-8", errors="replace").strip()
        if not line:
            # Check watchdog
            if time.monotonic() - last_data > WATCHDOG_TIMEOUT:
                log.warning("No data from ESP32 for %.0fs — reconnecting", WATCHDOG_TIMEOUT)
                break
            continue

        telemetry = parse_esp32_frame(line)
        if telemetry:
            latest_telemetry = telemetry
            last_data = time.monotonic()
            await broadcast(telemetry)
        else:
            log.debug("Unhandled ESP32 frame: %s", line)


async def serial_loop():
    while True:
        port = find_esp32_port()

        # In a real environment, find_esp32_port() returns None if no port is found.
        # But in docker/sandbox, it might return /dev/ttyS0 which we can't open anyway.
        # To handle both, we should check if we can actually open it, or if it's the expected USB port
        is_real_port = port and ("usb" in port.lower() or "acm" in port.lower() or "ch340" in port.lower() or "cp210" in port.lower() or "ttyUSB" in port or "ttyACM" in port)
        if not port or not is_real_port:
            print("Transferring to simulation")
            await asyncio.sleep(3)

            # Use os.execv to replace the current process with the simulator
            simulator_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "simulation", "simulator.py")
            os.execv(sys.executable, [sys.executable, simulator_path])
            return

        log.info("Opening serial port %s @ %d", port, SERIAL_BAUD)
        try:
            loop = asyncio.get_running_loop()
            ser = await loop.run_in_executor(
                None, functools.partial(serial.Serial, port, SERIAL_BAUD, timeout=SERIAL_TIMEOUT)
            )
        except serial.SerialException as exc:
            log.error("Failed to open %s: %s", port, exc)

            # If we fail to open the port, also transfer to simulation
            print("Transferring to simulation")
            await asyncio.sleep(3)
            simulator_path = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "simulation", "simulator.py")
            os.execv(sys.executable, [sys.executable, simulator_path])
            return

        try:
            await handle_serial_connection(ser)
        except serial.SerialException as exc:
            log.error("Serial error: %s — reconnecting", exc)
        finally:
            try:
                ser.close()
            except Exception:
                pass

        await asyncio.sleep(RECONNECT_DELAY)


# ── Entry point ────────────────────────────────────────────────────────────────
async def main():
    log.info("WMI Serial Bridge starting on ws://%s:%d", WS_HOST, WS_PORT)
    async with websockets.serve(ws_handler, WS_HOST, WS_PORT):
        await serial_loop()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Bridge stopped by user")
