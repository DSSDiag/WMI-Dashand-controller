# --- FIXED serial_bridge.py ---

import asyncio
import json
import logging
import time
import functools
from typing import Optional, Set

import serial
import serial.tools.list_ports
import websockets
from websockets.asyncio.server import ServerConnection

from bridge.logic import parse_esp32_frame, build_settings_frame

WS_HOST = "0.0.0.0"
WS_PORT = 8765
SERIAL_BAUD = 115200
SERIAL_TIMEOUT = 1.0
RECONNECT_DELAY = 3.0
WATCHDOG_TIMEOUT = 5.0

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("wmi-bridge")

clients: Set[ServerConnection] = set()
latest_telemetry: dict = {}
pending_settings: Optional[dict] = None
pending_prime: bool = False

serial_connected = False

def find_esp32_port():
    ports = list(serial.tools.list_ports.comports())
    for p in ports:
        name = (p.device + (p.description or "")).lower()
        if any(x in name for x in ["usb", "acm", "ch340", "cp210"]):
            return p.device
    return None

async def broadcast(msg):
    if not clients:
        return
    data = json.dumps(msg)
    await asyncio.gather(*(c.send(data) for c in clients), return_exceptions=True)

async def send_status():
    await broadcast({
        "type": "status",
        "serial_connected": serial_connected
    })

async def ws_handler(ws: ServerConnection):
    global pending_settings, pending_prime
    clients.add(ws)

    await send_status()

    try:
        async for message in ws:
            msg = json.loads(message)

            if msg.get("type") == "settings":
                pending_settings = msg

            elif msg.get("type") == "prime":
                pending_prime = True

    finally:
        clients.remove(ws)

async def handle_serial(ser):
    global pending_settings, pending_prime, latest_telemetry, serial_connected

    serial_connected = True
    await send_status()

    last_data = time.monotonic()

    while True:
        if pending_prime:
            pending_prime = False
            ser.write(b'{"t":"prime"}\n')

        if pending_settings:
            ser.write(build_settings_frame(pending_settings))
            pending_settings = None

        line = ser.readline().decode(errors="ignore").strip()

        if not line:
            if time.monotonic() - last_data > WATCHDOG_TIMEOUT:
                raise Exception("timeout")
            continue

        data = parse_esp32_frame(line)
        if data:
            latest_telemetry = data
            last_data = time.monotonic()
            await broadcast(data)

async def serial_loop():
    global serial_connected

    while True:
        port = find_esp32_port()

        if not port:
            serial_connected = False
            await send_status()
            await asyncio.sleep(RECONNECT_DELAY)
            continue

        try:
            ser = serial.Serial(port, SERIAL_BAUD, timeout=SERIAL_TIMEOUT)
            log.info(f"Connected to {port}")
            await handle_serial(ser)

        except Exception as e:
            log.warning(f"Serial lost: {e}")
            serial_connected = False
            await send_status()

        await asyncio.sleep(RECONNECT_DELAY)

async def main():
    async with websockets.serve(ws_handler, WS_HOST, WS_PORT):
        await serial_loop()

if __name__ == '__main__':
    asyncio.run(main())
