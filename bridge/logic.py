import json
from typing import Optional

# Conversion constants
KPA_ABS_TO_PSI_GAUGE = 1 / 6.89476    # Conversion factor: kPa to PSI (atmospheric offset applied separately)
ATM_KPA              = 101.325

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
    except (KeyError, ValueError, TypeError, json.JSONDecodeError):
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
