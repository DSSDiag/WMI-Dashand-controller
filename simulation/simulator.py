#!/usr/bin/env python3
"""
WMI Interactive Simulator
=========================
A standalone interactive WebSocket server that mimics the behavior of the
WMI hardware and Python serial bridge. It listens for settings from the
dashboard and broadcasts simulated telemetry data.

Interactive Controls:
  - Type 't' and press Enter to toggle the tank low sensor.
  - Type 'u' and press Enter to increase boost pressure manually.
  - Type 'd' and press Enter to decrease boost pressure manually.
  - Type 'a' and press Enter to toggle system arming.
"""

import asyncio
import json
import logging
import math
import sys
import threading
from typing import Set

import websockets
from websockets.server import WebSocketServerProtocol

# ── Configuration ──────────────────────────────────────────────────────────────
WS_HOST = "0.0.0.0"
WS_PORT = 8765

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("wmi-simulator")

# ── Simulation State ───────────────────────────────────────────────────────────
clients: Set[WebSocketServerProtocol] = set()

sim_state = {
    "pressure_psi": -14.7,  # Start at atmospheric vacuum
    "pump_duty": 0,
    "tank_low": False,
    "system_active": False,
    "trigger_mode": "thresholds",
    "start_psi": 5.0,
    "full_psi": 20.0,
    "manual_duty": 0,
    "curve": "linear"
}

# Add some state for dynamic boost simulation
boost_target = -14.7
boost_manual_control = False

# ── Simulation Logic ───────────────────────────────────────────────────────────
async def simulation_loop():
    """Periodically calculates pump duty and broadcasts telemetry."""
    global boost_target, boost_manual_control

    while True:
        # 1. Update boost pressure
        if not boost_manual_control:
            if sim_state["system_active"]:
                # Build boost when armed
                noise = (asyncio.get_event_loop().time() * 10) % 2 - 1
                boost_target = min(sim_state["full_psi"] + 5, sim_state["pressure_psi"] + 1.5 + noise)
            else:
                # Decay to vacuum when unarmed
                boost_target = -14.7

            # Smoothly approach target
            sim_state["pressure_psi"] += (boost_target - sim_state["pressure_psi"]) * 0.2

        # 2. Calculate pump duty
        calculated_duty = 0
        if sim_state["system_active"]:
            if sim_state["trigger_mode"] == "manual":
                calculated_duty = sim_state["manual_duty"]
            else:
                p = sim_state["pressure_psi"]
                start = sim_state["start_psi"]
                end = sim_state["full_psi"]

                if p > start:
                    range_val = max(0.1, end - start)
                    progress = max(0.0, min(1.0, (p - start) / range_val))

                    if sim_state["curve"] == "exponential":
                        progress = math.pow(progress, 2)

                    calculated_duty = progress * 100

        sim_state["pump_duty"] = calculated_duty

        # 3. Broadcast telemetry
        telemetry = {
            "type": "telemetry",
            "pressure_psi": round(sim_state["pressure_psi"], 2),
            "pump_duty": int(sim_state["pump_duty"]),
            "tank_low": sim_state["tank_low"],
            "pump_active": sim_state["pump_duty"] > 0
        }

        if clients:
            msg = json.dumps(telemetry)
            await asyncio.gather(
                *(ws.send(msg) for ws in clients),
                return_exceptions=True
            )

        await asyncio.sleep(0.1)  # 10Hz update rate, matching ESP32

# ── WebSocket Server ───────────────────────────────────────────────────────────
async def ws_handler(ws: WebSocketServerProtocol):
    clients.add(ws)
    log.info(f"Dashboard connected (total: {len(clients)})")

    try:
        async for message in ws:
            try:
                msg = json.loads(message)
                if msg.get("type") == "settings":
                    log.info(f"Received settings: {msg}")
                    sim_state["system_active"] = msg.get("system_active", sim_state["system_active"])
                    sim_state["trigger_mode"] = msg.get("trigger_mode", sim_state["trigger_mode"])
                    sim_state["start_psi"] = msg.get("start_psi", sim_state["start_psi"])
                    sim_state["full_psi"] = msg.get("full_psi", sim_state["full_psi"])
                    sim_state["manual_duty"] = msg.get("manual_duty", sim_state["manual_duty"])
                    sim_state["curve"] = msg.get("curve", sim_state["curve"])
                elif msg.get("type") == "prime":
                    log.info("Purge/prime triggered by dashboard")
                    # Force 100% duty for 2 seconds
                    old_active = sim_state["system_active"]
                    old_mode = sim_state["trigger_mode"]
                    old_manual = sim_state["manual_duty"]

                    sim_state["system_active"] = True
                    sim_state["trigger_mode"] = "manual"
                    sim_state["manual_duty"] = 100

                    await asyncio.sleep(2.0)

                    sim_state["system_active"] = old_active
                    sim_state["trigger_mode"] = old_mode
                    sim_state["manual_duty"] = old_manual

            except json.JSONDecodeError:
                pass
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        clients.discard(ws)
        log.info(f"Dashboard disconnected (total: {len(clients)})")

# ── Interactive CLI ────────────────────────────────────────────────────────────
def cli_thread():
    """Runs a simple CLI in a separate thread to accept interactive commands."""
    global boost_manual_control
    print("\n" + "="*40)
    print("WMI Interactive Simulator Started!")
    print("Commands:")
    print("  t : Toggle tank low sensor")
    print("  u : Manually increase boost by 5 PSI")
    print("  d : Manually decrease boost by 5 PSI")
    print("  a : Toggle system armed status")
    print("  q : Quit")
    print("="*40 + "\n")

    while True:
        try:
            cmd = input().strip().lower()
            if cmd == 't':
                sim_state["tank_low"] = not sim_state["tank_low"]
                print(f"--> Tank level sensor is now: {'LOW' if sim_state['tank_low'] else 'OK'}")
            elif cmd == 'u':
                boost_manual_control = True
                sim_state["pressure_psi"] += 5.0
                print(f"--> Boost increased to: {sim_state['pressure_psi']:.1f} PSI")
            elif cmd == 'd':
                boost_manual_control = True
                sim_state["pressure_psi"] -= 5.0
                print(f"--> Boost decreased to: {sim_state['pressure_psi']:.1f} PSI")
            elif cmd == 'a':
                sim_state["system_active"] = not sim_state["system_active"]
                print(f"--> System is now: {'ARMED' if sim_state['system_active'] else 'UNARMED'}")
            elif cmd == 'q':
                print("Exiting...")
                # Best effort exit since we're in a daemon thread
                import os
                os._exit(0)
        except EOFError:
            break

# ── Entry Point ────────────────────────────────────────────────────────────────
async def main():
    # Start the interactive CLI in a background thread
    t = threading.Thread(target=cli_thread, daemon=True)
    t.start()

    log.info(f"Simulator WebSocket server starting on ws://{WS_HOST}:{WS_PORT}")

    # Run the WebSocket server and the simulation loop concurrently
    async with websockets.serve(ws_handler, WS_HOST, WS_PORT):
        await simulation_loop()

if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        log.info("Simulator stopped by user")
