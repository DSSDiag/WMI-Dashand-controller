import json
import pytest
from bridge.logic import parse_esp32_frame, ATM_KPA, KPA_ABS_TO_PSI_GAUGE

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
