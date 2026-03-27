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
from typing import Optional, Set

import serial
import serial.tools.list_ports
import websockets
from websockets.server import WebSocketServerProtocol

# ── Configuration ──────────────────────────────────────────────────────────────
WS_HOST          = "0.0.0.0"
WS_PORT          = 8765
SERIAL_BAUD      = 115200
SERIAL_TIMEOUT   = 1.0
RECONNECT_DELAY  = 3.0   # seconds between ESP32 reconnect attempts
WATCHDOG_TIMEOUT = 5.0   # seconds without data before marking disconnected

# Conversion constants
KPA_ABS_TO_PSI_GAUGE = 1 / 6.89476    # Conversion factor: kPa to PSI (atmospheric offset applied separately)
ATM_KPA              = 101.325

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("wmi-bridge")

# ── Shared state ───────────────────────────────────────────────────────────────
clients: Set[WebSocketServerProtocol] = set()
latest_telemetry: dict = {}
pending_settings: Optional[dict] = None   # set by WebSocket handler, consumed by serial loop
pending_prime: bool = False


def find_esp32_port() -> Optional[str]:
    """Scan serial ports and return the most likely ESP32 port."""
    preferred_keywords = [
        "CP210", "CH340", "CH9102", "FTDI", "USB Serial",
        "USB-SERIAL", "ttyUSB", "ttyACM",
    ]
    ports = list(serial.tools.list_ports.comports())
    for port in ports:
        desc = f"{port.description or ''} {port.hwid or ''}"
        for kw in preferred_keywords:
            if kw.lower() in desc.lower() or kw.lower() in port.device.lower():
                return port.device
    # Fallback: first available port
    return ports[0].device if ports else None


def parse_esp32_frame(line: str) -> Optional[dict]:
    """Parse a compact JSON telemetry frame from the ESP32."""
    try:
        raw = json.loads(line)
        if raw.get("t") != "d":
            return None
        kpa_abs = float(raw["p"])
        psi_gauge = (kpa_abs - ATM_KPA) * KPA_ABS_TO_PSI_GAUGE
        return {
            "type": "telemetry",
            "pressure_kpa": round(kpa_abs, 2),
            "pressure_psi": round(psi_gauge, 2),
            "pump_duty": int(raw.get("d", 0)),
            "tank_low": bool(raw.get("l", 0)),
            "pump_active": int(raw.get("d", 0)) > 0,
        }
    except (KeyError, ValueError, TypeError):
        return None


def build_settings_frame(settings: dict) -> bytes:
    """Convert browser settings dict into compact JSON for the ESP32."""
    # Convert PSI gauge thresholds → kPa absolute for the ESP32
    def psi_to_kpa_abs(psi_gauge: float) -> float:
        return psi_gauge * 6.89476 + ATM_KPA

    mode_map = {"thresholds": 0, "full_scale": 1, "manual": 2}
    frame = {
        "t": "s",
        "tm": mode_map.get(settings.get("trigger_mode", "thresholds"), 0),
        "sp": round(psi_to_kpa_abs(float(settings.get("start_psi", 5))), 1),
        "fp": round(psi_to_kpa_abs(float(settings.get("full_psi", 20))), 1),
        "md": int(settings.get("manual_duty", 0)),
        "c":  1 if settings.get("curve") == "exponential" else 0,
        "a":  1 if settings.get("system_active", False) else 0,
    }
    return (json.dumps(frame, separators=(",", ":")) + "\n").encode()


# ── WebSocket server ───────────────────────────────────────────────────────────
async def ws_handler(ws: WebSocketServerProtocol):
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
        *[ws.send(msg) for ws in list(clients)],
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
            ser.write(b'{"t":"prime"}\n')
            log.info("Prime pulse sent to ESP32")

        if pending_settings:
            frame = build_settings_frame(pending_settings)
            ser.write(frame)
            log.debug("Settings sent: %s", frame)
            pending_settings = None

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
        if not port:
            log.warning("No ESP32 found — retrying in %.0fs", RECONNECT_DELAY)
            await asyncio.sleep(RECONNECT_DELAY)
            continue

        log.info("Opening serial port %s @ %d", port, SERIAL_BAUD)
        try:
            ser = serial.Serial(port, SERIAL_BAUD, timeout=SERIAL_TIMEOUT)
        except serial.SerialException as exc:
            log.error("Failed to open %s: %s", port, exc)
            await asyncio.sleep(RECONNECT_DELAY)
            continue

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
