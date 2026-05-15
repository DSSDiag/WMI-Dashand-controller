import json
from typing import Optional

# Conversion constants
PSI_TO_KPA           = 6.89476        # Conversion factor: PSI to kPa
KPA_ABS_TO_PSI_GAUGE = 1 / PSI_TO_KPA # Conversion factor: kPa to PSI (atmospheric offset applied separately)
ATM_KPA              = 101.325
SENSOR_INPUT_MAX_MV  = 5000.0
ADC_INPUT_MAX_MV     = 3300.0
DEFAULT_SENSOR_SIGNAL_MIN_MV = 250.0
DEFAULT_SENSOR_SIGNAL_MAX_MV = 4500.0
DEFAULT_SENSOR_KPA_MIN = 10.0
DEFAULT_SENSOR_KPA_MAX = 105.0

def parse_esp32_frame(line: str) -> Optional[dict]:
    """Parse a compact JSON telemetry frame from the ESP32."""
    try:
        raw = json.loads(line)
        if raw.get("t") != "d":
            return None
        kpa_abs = float(raw["p"])
        psi_gauge = (kpa_abs - ATM_KPA) * KPA_ABS_TO_PSI_GAUGE
        telemetry = {
            "type": "telemetry",
            "pressure_kpa": round(kpa_abs, 2),
            "pressure_psi": round(psi_gauge, 2),
            "pump_duty": int(raw.get("d", 0)),
            "tank_low": bool(raw.get("l", 0)),
            "pump_active": int(raw.get("d", 0)) > 0,
        }
        if isinstance(raw.get("b"), str):
            telemetry["sensor_module_key"] = raw["b"]
        if isinstance(raw.get("m"), str):
            telemetry["sensor_module_label"] = raw["m"]
        return telemetry
    except (KeyError, ValueError, TypeError, json.JSONDecodeError):
        return None

def build_settings_frame(settings: dict) -> bytes:
    """Convert browser settings dict into compact JSON for the ESP32."""
    # Convert PSI gauge thresholds → kPa absolute for the ESP32
    def psi_to_kpa_abs(psi_gauge: float) -> float:
        return psi_gauge * PSI_TO_KPA + ATM_KPA

    def source_mv_to_adc_mv(source_mv: float) -> float:
        clamped = max(0.0, min(SENSOR_INPUT_MAX_MV, source_mv))
        return (clamped / SENSOR_INPUT_MAX_MV) * ADC_INPUT_MAX_MV

    signal_min_mv = float(settings.get("sensor_signal_min_mv", DEFAULT_SENSOR_SIGNAL_MIN_MV))
    signal_max_mv = float(settings.get("sensor_signal_max_mv", DEFAULT_SENSOR_SIGNAL_MAX_MV))
    if signal_min_mv > signal_max_mv:
        signal_min_mv, signal_max_mv = signal_max_mv, signal_min_mv
    signal_min_mv = min(signal_min_mv, SENSOR_INPUT_MAX_MV - 1)
    signal_max_mv = max(signal_max_mv, signal_min_mv + 1)

    kpa_min = float(settings.get("sensor_kpa_min", DEFAULT_SENSOR_KPA_MIN))
    kpa_max = float(settings.get("sensor_kpa_max", DEFAULT_SENSOR_KPA_MAX))
    if kpa_min > kpa_max:
        kpa_min, kpa_max = kpa_max, kpa_min
    kpa_max = max(kpa_max, kpa_min + 1)

    mode_map = {"thresholds": 0, "full_scale": 1, "manual": 2}
    frame = {
        "t": "s",
        "tm": mode_map.get(settings.get("trigger_mode", "thresholds"), 0),
        "sp": round(psi_to_kpa_abs(float(settings.get("start_psi", 5))), 1),
        "fp": round(psi_to_kpa_abs(float(settings.get("full_psi", 20))), 1),
        "md": int(settings.get("manual_duty", 0)),
        "c":  1 if settings.get("curve") == "exponential" else 0,
        "a":  1 if settings.get("system_active", False) else 0,
        "vmn": round(source_mv_to_adc_mv(signal_min_mv), 1),
        "vmx": round(source_mv_to_adc_mv(signal_max_mv), 1),
        "kmn": round(kpa_min, 1),
        "kmx": round(kpa_max, 1),
    }
    return (json.dumps(frame, separators=(",", ":")) + "\n").encode()
