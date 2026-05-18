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
FIRST_FRAME_TIMEOUT = 12.0
PORT_STABILIZE_DELAY = 2.5

logging.basicConfig(level=logging.INFO)
log = logging.getLogger("wmi-bridge")

clients: Set[ServerConnection] = set()
latest_telemetry: dict = {}
pending_settings: Optional[dict] = None
pending_prime: bool = False

serial_connected = False
sensor_module_key: Optional[str] = None
sensor_module_label: Optional[str] = None


async def serial_write(ser, payload: bytes) -> None:
    await asyncio.to_thread(ser.write, payload)


async def serial_readline(ser) -> str:
    raw = await asyncio.to_thread(ser.readline)
    return raw.decode(errors="ignore").strip()


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
    first_frame_deadline = time.monotonic() + FIRST_FRAME_TIMEOUT
    received_frame = False

    while True:
        if pending_prime:
            pending_prime = False
            await serial_write(ser, b'{"t":"prime"}\n')

        if pending_settings:
            await serial_write(ser, build_settings_frame(pending_settings))
            pending_settings = None

        line = await serial_readline(ser)
        if not line:
            if not received_frame and time.monotonic() > first_frame_deadline:
                raise TimeoutError("serial first-frame timeout")
            if received_frame and time.monotonic() - last_data > WATCHDOG_TIMEOUT:
                raise TimeoutError("serial watchdog timeout")
            await asyncio.sleep(0.05)
            continue

        data = parse_esp32_frame(line)
        if data:
            received_frame = True
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

        await asyncio.sleep(0)


async def serial_loop():
    global serial_connected, sensor_module_key, sensor_module_label
    current_port: Optional[str] = None
    port_seen_at: Optional[float] = None

    while True:
        port = find_esp32_port()
        if not port:
            current_port = None
            port_seen_at = None
            if serial_connected:
                serial_connected = False
                sensor_module_key = None
                sensor_module_label = None
                await send_status()
            await asyncio.sleep(RECONNECT_DELAY)
            continue

        if port != current_port:
            current_port = port
            port_seen_at = time.monotonic()
            log.info("Detected sensor module serial port %s, waiting for it to stabilise", port)
            await asyncio.sleep(RECONNECT_DELAY)
            continue

        if port_seen_at is not None and (time.monotonic() - port_seen_at) < PORT_STABILIZE_DELAY:
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
            current_port = None
            port_seen_at = None
            await send_status()

        await asyncio.sleep(RECONNECT_DELAY)


async def main():
    async with websockets.serve(ws_handler, WS_HOST, WS_PORT):
        await serial_loop()


if __name__ == "__main__":
    asyncio.run(main())
