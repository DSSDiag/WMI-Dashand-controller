import sys
import os
import types

# Mock websockets before importing simulator, just like in test_validation.py
class MockServerConnection:
    pass

_websockets_pkg = types.ModuleType("websockets")
_asyncio_mod = types.ModuleType("websockets.asyncio")
_asyncio_server_mod = types.ModuleType("websockets.asyncio.server")
_asyncio_server_mod.ServerConnection = MockServerConnection
_asyncio_mod.server = _asyncio_server_mod
_websockets_pkg.asyncio = _asyncio_mod
_websockets_pkg.serve = lambda *args, **kwargs: None
_websockets_pkg.exceptions = types.SimpleNamespace(ConnectionClosed=Exception)

sys.modules['websockets'] = _websockets_pkg
sys.modules['websockets.asyncio'] = _asyncio_mod
sys.modules['websockets.asyncio.server'] = _asyncio_server_mod

import builtins
import io
import unittest
from unittest.mock import patch

import simulator
from simulator import cli_thread, sim_state

class TestCLIThread(unittest.TestCase):
    def setUp(self):
        # Reset sim_state to known values before each test
        self.original_sim_state = sim_state.copy()
        self.original_boost_manual_control = simulator.boost_manual_control

        sim_state["tank_low"] = False
        sim_state["pressure_psi"] = 0.0
        sim_state["system_active"] = False
        simulator.boost_manual_control = False

    def tearDown(self):
        # Restore sim_state
        for key, value in self.original_sim_state.items():
            sim_state[key] = value
        simulator.boost_manual_control = self.original_boost_manual_control

    def run_cli_with_inputs(self, inputs):
        """Helper to run cli_thread with mocked inputs (the loop exits on EOFError internally)."""
        def mock_input_generator():
            for i in inputs:
                yield i
            raise EOFError()

        generator = mock_input_generator()

        with patch('builtins.input', side_effect=generator), \
             patch('sys.stdout', new_callable=io.StringIO):
            cli_thread()

    def test_toggle_tank_low(self):
        self.run_cli_with_inputs(['t'])
        self.assertTrue(sim_state["tank_low"])

        self.run_cli_with_inputs(['t'])
        self.assertFalse(sim_state["tank_low"])

    def test_increase_boost(self):
        self.run_cli_with_inputs(['u'])
        self.assertEqual(sim_state["pressure_psi"], 5.0)
        self.assertTrue(simulator.boost_manual_control)

        self.run_cli_with_inputs(['u'])
        self.assertEqual(sim_state["pressure_psi"], 10.0)

    def test_decrease_boost(self):
        self.run_cli_with_inputs(['d'])
        self.assertEqual(sim_state["pressure_psi"], -5.0)
        self.assertTrue(simulator.boost_manual_control)

    def test_toggle_system_active(self):
        self.run_cli_with_inputs(['a'])
        self.assertTrue(sim_state["system_active"])

        self.run_cli_with_inputs(['a'])
        self.assertFalse(sim_state["system_active"])

    @patch('os._exit')
    def test_quit(self, mock_exit):
        # Prevent test suite from exiting
        def mock_input_generator():
            yield 'q'
            raise EOFError()

        generator = mock_input_generator()
        with patch('builtins.input', side_effect=generator), \
             patch('sys.stdout', new_callable=io.StringIO):
            cli_thread()
        mock_exit.assert_called_once_with(0)

    def test_invalid_input(self):
        # Test that invalid input is ignored and loops again
        self.run_cli_with_inputs(['x', 't'])
        self.assertTrue(sim_state["tank_low"])

if __name__ == '__main__':
    unittest.main()
