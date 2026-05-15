import asyncio
import json
import logging
import time
from typing import Optional, Set

import serial
import serial.tools.list_ports
import websockets
from websockets.asyncio.server import ServerConnection

try:
    from bridge.logic import parse_esp32_frame, build_settings_frame
except ModuleNotFoundError:
    from logic import parse_esp32_frame, build_settings_frame

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
sensor_module_key: Optional[str] = None
sensor_module_label: Optional[str] = None


def find_esp32_port():
    ports = list(serial.tools.list_ports.comports())
    for port in ports:
        if getattr(port, "vid", None) == 0x303A:
            return port.device
        name = (port.device + (port.description or "")).lower()
        if any(token in name for token in ("usb", "acm", "ch340", "cp210", "usb jtag")):
            return port.device
    return None


async def broadcast(msg: dict) -> None:
    if not clients:
        return
    data = json.dumps(msg)
    await asyncio.gather(*(client.send(data) for client in clients), return_exceptions=True)


async def send_status() -> None:
    await broadcast({
        "type": "status",
        "serial_connected": serial_connected,
        "sensor_module_key": sensor_module_key,
        "sensor_module_label": sensor_module_label,
    })


async def ws_handler(ws: ServerConnection):
    global pending_settings, pending_prime

    clients.add(ws)
    await send_status()
    if latest_telemetry:
        await ws.send(json.dumps(latest_telemetry))

    try:
        async for message in ws:
            msg = json.loads(message)
            if msg.get("type") == "settings":
                pending_settings = msg
            elif msg.get("type") == "prime":
                pending_prime = True
    finally:
        clients.discard(ws)


async def handle_serial(ser):
    global pending_settings, pending_prime, latest_telemetry, serial_connected, sensor_module_key, sensor_module_label

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
                raise TimeoutError("serial watchdog timeout")
            continue

        data = parse_esp32_frame(line)
        if data:
            new_sensor_module_key = data.get("sensor_module_key")
            new_sensor_module_label = data.get("sensor_module_label")
            if (
                new_sensor_module_key != sensor_module_key
                or new_sensor_module_label != sensor_module_label
            ):
                sensor_module_key = new_sensor_module_key
                sensor_module_label = new_sensor_module_label
                log.info("Sensor module identified as %s", sensor_module_label or sensor_module_key)
                await send_status()
            latest_telemetry = data
            last_data = time.monotonic()
            await broadcast(data)


async def serial_loop():
    global serial_connected, sensor_module_key, sensor_module_label

    while True:
        port = find_esp32_port()
        if not port:
            if serial_connected:
                serial_connected = False
                sensor_module_key = None
                sensor_module_label = None
                await send_status()
            await asyncio.sleep(RECONNECT_DELAY)
            continue

        try:
            with serial.Serial(port, SERIAL_BAUD, timeout=SERIAL_TIMEOUT) as ser:
                log.info("Connected to %s", port)
                await handle_serial(ser)
        except Exception as exc:
            log.warning("Serial lost: %s", exc)
            serial_connected = False
            sensor_module_key = None
            sensor_module_label = None
            await send_status()

        await asyncio.sleep(RECONNECT_DELAY)


async def main():
    async with websockets.serve(ws_handler, WS_HOST, WS_PORT):
        await serial_loop()


if __name__ == "__main__":
    asyncio.run(main())
