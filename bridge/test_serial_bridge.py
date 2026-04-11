import json
import pytest
from bridge.logic import parse_esp32_frame, ATM_KPA, KPA_ABS_TO_PSI_GAUGE, build_settings_frame

def test_parse_esp32_frame_happy_path():
    """Test with valid telemetry data."""
    line = '{"t":"d", "p":120.5, "d":75, "l":0}'
    result = parse_esp32_frame(line)

    assert result is not None
    assert result["type"] == "telemetry"
    assert result["pressure_kpa"] == 120.5

    expected_psi = round((120.5 - ATM_KPA) * KPA_ABS_TO_PSI_GAUGE, 2)
    assert result["pressure_psi"] == expected_psi
    assert result["pump_duty"] == 75
    assert result["tank_low"] is False
    assert result["pump_active"] is True

def test_parse_esp32_frame_invalid_type():
    """Test with non-data frame types."""
    line = '{"t":"v", "v":"1.0.0"}'
    assert parse_esp32_frame(line) is None

def test_parse_esp32_frame_malformed_json():
    """Test with malformed JSON strings."""
    line = '{"t":"d", "p":120.5, "d":75, "l":0' # Missing closing brace
    assert parse_esp32_frame(line) is None

    line = "not a json"
    assert parse_esp32_frame(line) is None

def test_parse_esp32_frame_missing_pressure():
    """Test with missing pressure field 'p'."""
    line = '{"t":"d", "d":75, "l":0}'
    assert parse_esp32_frame(line) is None

def test_parse_esp32_frame_invalid_data_types():
    """Test with invalid data types in fields."""
    line = '{"t":"d", "p":"high", "d":75, "l":0}'
    assert parse_esp32_frame(line) is None

    line = '{"t":"d", "p":120.5, "d":"none", "l":0}'
    assert parse_esp32_frame(line) is None

def test_parse_esp32_frame_default_values():
    """Test that default values are used when optional fields are missing."""
    line = '{"t":"d", "p":101.325}' # ATM_KPA
    result = parse_esp32_frame(line)

    assert result is not None
    assert result["pressure_kpa"] == round(101.325, 2)
    assert result["pressure_psi"] == 0.0
    assert result["pump_duty"] == 0
    assert result["tank_low"] is False
    assert result["pump_active"] is False

def test_parse_esp32_frame_tank_low():
    """Test tank_low flag parsing."""
    line = '{"t":"d", "p":100.0, "d":0, "l":1}'
    result = parse_esp32_frame(line)
    assert result["tank_low"] is True

    line = '{"t":"d", "p":100.0, "d":0, "l":0}'
    result = parse_esp32_frame(line)
    assert result["tank_low"] is False

def test_parse_esp32_frame_pump_active():
    """Test pump_active logic."""
    line = '{"t":"d", "p":100.0, "d":1, "l":0}'
    result = parse_esp32_frame(line)
    assert result["pump_active"] is True

    line = '{"t":"d", "p":100.0, "d":0, "l":0}'
    result = parse_esp32_frame(line)
    assert result["pump_active"] is False

def test_build_settings_frame_defaults():
    """Test build_settings_frame with an empty dictionary (default values)."""
    settings = {}
    result = build_settings_frame(settings)
    decoded = json.loads(result.decode().strip())

    assert decoded["t"] == "s"
    assert decoded["tm"] == 0
    # default start_psi=5 -> 5*6.89476 + 101.325 = 135.7988 -> round(..., 1) -> 135.8
    assert decoded["sp"] == 135.8
    # default full_psi=20 -> 20*6.89476 + 101.325 = 239.2202 -> round(..., 1) -> 239.2
    assert decoded["fp"] == 239.2
    assert decoded["md"] == 0
    assert decoded["c"] == 0
    assert decoded["a"] == 0

    # Ensure it ends with a newline
    assert result.endswith(b"\n")

def test_build_settings_frame_custom_values():
    """Test build_settings_frame with custom dictionary values."""
    settings = {
        "trigger_mode": "full_scale",
        "start_psi": 10,
        "full_psi": 30,
        "manual_duty": 50,
        "curve": "exponential",
        "system_active": True
    }
    result = build_settings_frame(settings)
    decoded = json.loads(result.decode().strip())

    assert decoded["t"] == "s"
    assert decoded["tm"] == 1
    # start_psi=10 -> 10*6.89476 + 101.325 = 170.2726 -> round(..., 1) -> 170.3
    assert decoded["sp"] == 170.3
    # full_psi=30 -> 30*6.89476 + 101.325 = 308.1678 -> round(..., 1) -> 308.2
    assert decoded["fp"] == 308.2
    assert decoded["md"] == 50
    assert decoded["c"] == 1
    assert decoded["a"] == 1

    # Ensure it ends with a newline
    assert result.endswith(b"\n")

def test_build_settings_frame_invalid_types():
    """Test build_settings_frame raises ValueError on invalid types."""
    settings = {"start_psi": "invalid"}
    with pytest.raises(ValueError):
        build_settings_frame(settings)
