import sys
import os
import logging

# Set up logging to see warnings
logging.basicConfig(level=logging.INFO)

# Import the simulator module
# We need to mock things since websockets is not installed
class MockWebsockets:
    class server:
        @staticmethod
        def WebSocketServerProtocol():
            pass

sys.modules['websockets'] = MockWebsockets()
sys.modules['websockets.server'] = MockWebsockets.server()

from simulator import update_sim_settings, sim_state

def test_validation():
    print("Running validation tests...")

    # Initial state
    initial_state = sim_state.copy()
    print(f"Initial state: {initial_state}")

    # Test valid updates
    valid_msg = {
        "system_active": True,
        "trigger_mode": "manual",
        "start_psi": 10.5,
        "full_psi": 30.0,
        "manual_duty": 50,
        "curve": "exponential"
    }
    update_sim_settings(valid_msg)

    assert sim_state["system_active"] == True
    assert sim_state["trigger_mode"] == "manual"
    assert sim_state["start_psi"] == 10.5
    assert sim_state["full_psi"] == 30.0
    assert sim_state["manual_duty"] == 50.0
    assert sim_state["curve"] == "exponential"
    print("✓ Valid updates passed")

    # Test invalid types
    invalid_msg = {
        "system_active": "yes",  # Should be bool
        "start_psi": "invalid",  # Should be float/int
        "manual_duty": [10, 20]  # Should be float/int
    }
    update_sim_settings(invalid_msg)

    # Values should remain from previous valid update
    assert sim_state["system_active"] == True
    assert sim_state["start_psi"] == 10.5
    assert sim_state["manual_duty"] == 50.0
    print("✓ Invalid types ignored as expected")

    # Test invalid values (out of range)
    out_of_range_msg = {
        "start_psi": 150.0,  # Range 0-100
        "full_psi": -10.0,   # Range 0-100
        "trigger_mode": "invalid_mode",
        "curve": "invalid_curve"
    }
    update_sim_settings(out_of_range_msg)

    # Values should remain from previous valid update
    assert sim_state["start_psi"] == 10.5
    assert sim_state["full_psi"] == 30.0
    assert sim_state["trigger_mode"] == "manual"
    assert sim_state["curve"] == "exponential"
    print("✓ Out of range values ignored as expected")

    # Test mixed valid and invalid
    mixed_msg = {
        "system_active": False,
        "start_psi": "bad",
        "manual_duty": 75.0
    }
    update_sim_settings(mixed_msg)

    assert sim_state["system_active"] == False
    assert sim_state["start_psi"] == 10.5  # Unchanged
    assert sim_state["manual_duty"] == 75.0 # Changed
    print("✓ Mixed valid/invalid handled correctly")

    print("\nAll validation tests passed successfully!")

if __name__ == "__main__":
    test_validation()
