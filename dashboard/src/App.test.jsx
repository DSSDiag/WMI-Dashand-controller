import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import App from './App';

class MockWebSocket {
  static OPEN = 1;
  static instances = [];

  constructor(url) {
    this.url = url;
    this.readyState = MockWebSocket.OPEN;
    this.onopen = null;
    this.onmessage = null;
    this.onclose = null;
    this.onerror = null;
    this.send = vi.fn();
    this.close = vi.fn(() => {
      this.readyState = 3;
      this.onclose?.();
    });
    MockWebSocket.instances.push(this);
  }

  emitOpen() {
    this.onopen?.();
  }

  emitMessage(payload) {
    this.onmessage?.({ data: JSON.stringify(payload) });
  }

  emitClose() {
    this.readyState = 3;
    this.onclose?.();
  }
}

function setViewport(width, height) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  });
  Object.defineProperty(window, 'innerHeight', {
    configurable: true,
    writable: true,
    value: height,
  });
  window.dispatchEvent(new Event('resize'));
}

describe('App dashboard', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    localStorage.clear();
    MockWebSocket.instances = [];
    window.WebSocket = MockWebSocket;
    globalThis.WebSocket = MockWebSocket;
    setViewport(800, 480);
  });

  afterEach(() => {
    cleanup();
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('shows bridge and hardware connection states separately', () => {
    render(<App />);

    const badge = screen.getByTestId('hardware-status');
    expect(badge).toHaveTextContent('OFF');
    expect(badge).toHaveAttribute('title', 'Sensor bridge disconnected');

    const socket = MockWebSocket.instances[0];

    act(() => {
      socket.emitOpen();
    });

    expect(badge).toHaveTextContent('WAIT');
    expect(badge).toHaveAttribute('title', 'Bridge online, waiting for sensor module');

    act(() => {
      socket.emitMessage({
        type: 'status',
        serial_connected: true,
        sensor_module_key: 'esp32-c3',
        sensor_module_label: 'ESP32-C3 Sensor Module',
      });
    });

    expect(badge).toHaveTextContent('C3');
    expect(badge).toHaveAttribute('title', 'ESP32-C3 Sensor Module connected');

    act(() => {
      socket.emitMessage({
        type: 'status',
        serial_connected: false,
        sensor_module_key: null,
        sensor_module_label: null,
      });
    });

    expect(badge).toHaveTextContent('WAIT');

    act(() => {
      socket.emitClose();
    });

    expect(badge).toHaveTextContent('OFF');
  }, 15000);

  it('shows the sensor-module boot overlay and can continue waiting', () => {
    render(<App />);

    const socket = MockWebSocket.instances[0];

    act(() => {
      socket.emitOpen();
      socket.emitMessage({
        type: 'status',
        serial_connected: false,
        sensor_module_key: null,
        sensor_module_label: null,
      });
      vi.advanceTimersByTime(3600);
    });

    expect(screen.getByTestId('sensor-module-overlay')).toBeInTheDocument();
    expect(screen.getByText(/sensor module not found, continue waiting or load simulation/i)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: /wait/i }));

    expect(screen.queryByTestId('sensor-module-overlay')).not.toBeInTheDocument();
    expect(screen.getByTestId('hardware-status')).toHaveTextContent('WAIT');
  }, 15000);

  it('can switch from the boot overlay into simulation until hardware appears', () => {
    render(<App />);

    const socket = MockWebSocket.instances[0];

    act(() => {
      socket.emitOpen();
      socket.emitMessage({
        type: 'status',
        serial_connected: false,
        sensor_module_key: null,
        sensor_module_label: null,
      });
      vi.advanceTimersByTime(3600);
    });

    fireEvent.click(screen.getByRole('button', { name: /simulation/i }));

    expect(screen.queryByTestId('sensor-module-overlay')).not.toBeInTheDocument();
    expect(screen.getByTestId('hardware-status')).toHaveTextContent('SIM');
    expect(screen.getByTestId('hardware-status')).toHaveAttribute('title', 'Simulation active');

    act(() => {
      socket.emitMessage({
        type: 'status',
        serial_connected: true,
        sensor_module_key: 'esp32-c3',
        sensor_module_label: 'ESP32-C3 Sensor Module',
      });
    });

    expect(screen.getByTestId('hardware-status')).toHaveTextContent('C3');
    expect(screen.getByTestId('hardware-status')).toHaveAttribute('title', 'ESP32-C3 Sensor Module connected');
  }, 15000);

  it('keeps the default layout on smaller displays unless the compact HAT profile is selected', () => {
    setViewport(470, 320);

    render(<App />);

    expect(screen.getByTestId('dashboard-shell')).toHaveAttribute('data-compact', 'false');
    expect(screen.getByTestId('dashboard-shell').className).toContain('touch-manipulation');

    cleanup();

    render(<App displayProfile="generic-ili9486-hat" />);

    expect(screen.getByTestId('dashboard-shell')).toHaveAttribute('data-compact', 'true');
    expect(screen.getByTestId('dashboard-header').className).toContain('p-2');
    expect(screen.getByTestId('dashboard-actions').className).toContain('grid-cols-3');
    expect(screen.getByTestId('dash-secondary-cards').className).toContain('grid-cols-1');
    expect(screen.getByTestId('dash-secondary-cards').className).toContain('grid-rows-2');
    expect(screen.getByTestId('hardware-status').className).toContain('col-span-3');

    fireEvent.click(screen.getByRole('button', { name: /open settings/i }));

    expect(screen.getByText(/system configuration/i).closest('.settings-page')?.className).toContain('compact-settings');
    expect(screen.getByTestId('trigger-inputs').className).toContain('min-h-[54px]');
    expect(screen.getByTestId('gauge-limit-min').className).toContain('grid-cols-2');
  }, 15000);

  it('can force the compact preview layout without a tiny browser window', () => {
    render(<App initialTab="settings" forceCompact embeddedPreview />);

    expect(screen.getByTestId('dashboard-shell')).toHaveAttribute('data-compact', 'true');
    expect(screen.getByTestId('dashboard-shell').className).toContain('touch-manipulation');
    expect(screen.getByTestId('dashboard-actions').className).toContain('grid-cols-3');
    expect(screen.getByText(/system configuration/i).closest('.settings-page')?.className).toContain('compact-settings');
    expect(screen.getByTestId('gauge-limit-min').className).toContain('grid-cols-2');
    expect(screen.getByRole('spinbutton', { name: /minimum gauge limit/i })).toHaveAttribute('inputmode', 'decimal');
    expect(screen.getByRole('spinbutton', { name: /maximum gauge limit/i })).toHaveAttribute('inputmode', 'decimal');
  }, 15000);

  it('adds a sensor setup screen with direct-connect guidance for 5V signals', () => {
    render(<App displayProfile="generic-ili9486-hat" />);

    fireEvent.click(screen.getByRole('button', { name: /open settings/i }));
    fireEvent.click(screen.getByRole('button', { name: /open sensor setup/i }));

    expect(screen.getByText(/sensor setup & calibration/i)).toBeInTheDocument();
    expect(screen.getByText(/select a preset or map a custom 0-5v sensor \/ ecu output/i)).toBeInTheDocument();
    expect(screen.getByText(/connect sensors or ecu analog outputs directly only if the signal stays at or below \+5.0v/i)).toBeInTheDocument();
    expect(screen.getByText(/custom \/ ecu/i)).toBeInTheDocument();
  }, 15000);
});
