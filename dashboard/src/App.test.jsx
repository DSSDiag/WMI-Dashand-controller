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

class MockVisualViewport {
  constructor() {
    this.listeners = new Map();
    this.addEventListener = vi.fn((eventName, callback) => {
      const callbacks = this.listeners.get(eventName) ?? new Set();
      callbacks.add(callback);
      this.listeners.set(eventName, callbacks);
    });
    this.removeEventListener = vi.fn((eventName, callback) => {
      const callbacks = this.listeners.get(eventName);
      callbacks?.delete(callback);
      if (callbacks?.size === 0) {
        this.listeners.delete(eventName);
      }
    });
  }

  emit(eventName) {
    const callbacks = this.listeners.get(eventName) ?? [];
    for (const callback of callbacks) {
      callback(new Event(eventName));
    }
  }
}

function setViewport(width, height, { dispatchEventName = 'resize' } = {}) {
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
  if (dispatchEventName) {
    window.dispatchEvent(new Event(dispatchEventName));
  }
}

function getDashboardScale() {
  const transform = screen.getByTestId('dashboard-shell').parentElement?.style.transform ?? '';
  const match = transform.match(/scale\(([^)]+)\)/);

  return match ? Number.parseFloat(match[1]) : NaN;
}

describe('App dashboard', () => {
  beforeEach(() => {
    vi.useFakeTimers();
    localStorage.clear();
    MockWebSocket.instances = [];
    window.WebSocket = MockWebSocket;
    globalThis.WebSocket = MockWebSocket;
    window.visualViewport = new MockVisualViewport();
    setViewport(800, 480);
  });

  afterEach(() => {
    cleanup();
    delete window.visualViewport;
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

    render(<App displayProfile="waveshare-35g" />);

    expect(screen.getByTestId('dashboard-shell')).toHaveAttribute('data-compact', 'true');
    expect(screen.getByTestId('dashboard-header').className).toContain('p-2');
    expect(screen.getByTestId('dashboard-actions').className).toContain('grid-cols-3');
    expect(screen.getByTestId('dash-secondary-cards').className).toContain('grid-cols-1');
    expect(screen.getByTestId('dash-secondary-cards').className).toContain('grid-rows-2');
    expect(screen.getByTestId('hardware-status').className).toContain('col-span-3');
    expect(screen.getByRole('button', { name: /prime system/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /prime system/i }).className).toContain('touch-manipulation');
    expect(screen.getByRole('button', { name: /arm system/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /arm system/i }).className).toContain('touch-manipulation');

    fireEvent.click(screen.getByRole('button', { name: /open settings/i }));

    expect(screen.getByText(/system configuration/i).closest('.settings-page')?.className).toContain('compact-settings');
    expect(screen.getByTestId('settings-header').className).toContain('space-y-1.5');
    expect(screen.getByText(/hw rev:/i).parentElement?.className).toContain('flex-wrap');
    expect(screen.getByTestId('settings-header-actions').className).toContain('w-full');
    expect(screen.getByRole('button', { name: /^return to dashboard$/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /^return to dashboard$/i }).className).toContain('touch-manipulation');
    expect(screen.getByRole('button', { name: /open map sensor mapping/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /open map sensor mapping/i }).className).toContain('touch-manipulation');
    expect(screen.getByRole('button', { name: /save settings and return to dashboard/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /save settings and return to dashboard/i }).className).toContain('touch-manipulation');
    expect(screen.getByRole('button', { name: /save settings and return to dashboard/i }).className).toContain('flex-1');
    expect(screen.getByTestId('trigger-inputs').className).toContain('min-h-[54px]');
    expect(screen.getByTestId('gauge-limit-min').className).toContain('grid-cols-2');
    expect(screen.getByTestId('gauge-limit-max').className).toContain('grid-cols-2');
  }, 15000);

  it('treats every supported 3.5-inch setup profile as a compact layout', () => {
    for (const profile of ['52pi-k0403', 'generic-ili9486-hat', 'waveshare-35g']) {
      const { unmount } = render(<App displayProfile={profile} />);

      expect(screen.getByTestId('dashboard-shell')).toHaveAttribute('data-compact', 'true');

      unmount();
    }
  }, 15000);

  it('can force the compact preview layout without a tiny browser window', () => {
    render(<App initialTab="settings" forceCompact embeddedPreview />);

    expect(screen.getByTestId('dashboard-shell')).toHaveAttribute('data-compact', 'true');
    expect(screen.getByTestId('dashboard-shell').className).toContain('touch-manipulation');
    expect(screen.getByTestId('dashboard-actions').className).toContain('grid-cols-3');
    expect(screen.getByRole('button', { name: /prime system/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /prime system/i }).className).toContain('touch-manipulation');
    expect(screen.getByRole('button', { name: /arm system/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /arm system/i }).className).toContain('touch-manipulation');
    expect(screen.getByText(/system configuration/i).closest('.settings-page')?.className).toContain('compact-settings');
    expect(screen.getByTestId('settings-header').className).toContain('space-y-1.5');
    expect(screen.getByTestId('gauge-limit-min').className).toContain('grid-cols-2');
    expect(screen.getByTestId('gauge-limit-max').className).toContain('grid-cols-2');
    expect(screen.getByRole('spinbutton', { name: /minimum gauge limit/i })).toHaveAttribute('inputmode', 'decimal');
    expect(screen.getByRole('spinbutton', { name: /maximum gauge limit/i })).toHaveAttribute('inputmode', 'decimal');
    expect(screen.getByRole('spinbutton', { name: /minimum gauge limit/i })).toHaveAttribute('enterkeyhint', 'done');
    expect(screen.getByRole('spinbutton', { name: /maximum gauge limit/i })).toHaveAttribute('enterkeyhint', 'done');
  }, 15000);

  it('rescales the compact layout on orientation and visual viewport changes', () => {
    render(<App displayProfile="generic-ili9486-hat" />);

    expect(getDashboardScale()).toBeCloseTo(480 / 356, 3);

    act(() => {
      setViewport(320, 470, { dispatchEventName: null });
      window.dispatchEvent(new Event('orientationchange'));
    });

    expect(getDashboardScale()).toBeCloseTo(320 / 520, 3);

    act(() => {
      setViewport(480, 320, { dispatchEventName: null });
      window.visualViewport.emit('resize');
    });

    expect(getDashboardScale()).toBeCloseTo(320 / 356, 3);
  }, 15000);

  it('upscales the DSI kiosk layout to better fill the 800x480 screen', () => {
    setViewport(800, 480, { dispatchEventName: null });

    render(<App displayProfile="dsi5" />);

    expect(getDashboardScale()).toBeCloseTo(1.5, 3);
  }, 15000);

  it('keeps embedded previews capped at 1x scale', () => {
    setViewport(800, 480, { dispatchEventName: null });

    render(<App embeddedPreview />);

    expect(getDashboardScale()).toBe(1);
  }, 15000);

  it('removes visual viewport listeners when the dashboard unmounts', () => {
    const viewport = window.visualViewport;
    const { unmount } = render(<App displayProfile="generic-ili9486-hat" />);

    expect(viewport.addEventListener).toHaveBeenCalledWith('resize', expect.any(Function));
    expect(viewport.addEventListener).toHaveBeenCalledWith('scroll', expect.any(Function));

    const resizeHandler = viewport.addEventListener.mock.calls.find(([eventName]) => eventName === 'resize')?.[1];
    const scrollHandler = viewport.addEventListener.mock.calls.find(([eventName]) => eventName === 'scroll')?.[1];

    unmount();

    expect(viewport.removeEventListener).toHaveBeenCalledWith('resize', resizeHandler);
    expect(viewport.removeEventListener).toHaveBeenCalledWith('scroll', scrollHandler);
  }, 15000);

  it('adds a dedicated MAP sensor mapping screen with direct-connect guidance for 5V signals', () => {
    render(<App displayProfile="generic-ili9486-hat" />);

    fireEvent.click(screen.getByRole('button', { name: /open settings/i }));
    fireEvent.click(screen.getByRole('button', { name: /open map sensor mapping/i }));

    expect(screen.getByText(/map sensor mapping/i)).toBeInTheDocument();
    expect(screen.getByText(/four verified presets plus a custom ecu \/ haltech 0-5v analog map/i)).toBeInTheDocument();
    expect(screen.getByText(/connect sensors or ecu analog outputs directly only if the signal stays at or below \+5.0v/i)).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /custom ecu \/ haltech/i })).toBeInTheDocument();
    expect(screen.getByTestId('sensor-header').className).toContain('space-y-1.5');
    expect(screen.getByText(/four verified presets plus a custom ecu \/ haltech 0-5v analog map/i).className).toContain('whitespace-normal');
    expect(screen.getByRole('button', { name: /return to settings/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /return to settings/i }).className).toContain('touch-manipulation');
    expect(screen.getByRole('button', { name: /save map sensor mapping and return to dashboard/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('button', { name: /save map sensor mapping and return to dashboard/i }).className).toContain('touch-manipulation');
    expect(screen.getByRole('button', { name: /save map sensor mapping and return to dashboard/i }).className).toContain('w-full');
    expect(screen.getByTestId('sensor-setup-grid').className).toContain('grid-cols-1');
    expect(screen.getByTestId('sensor-preset-grid').className).toContain('grid-cols-1');
    expect(screen.getByRole('button', { name: /gm \/ delphi 3 bar/i }).className).toContain('touch-manipulation');
    expect(screen.getByRole('button', { name: /custom ecu \/ haltech/i }).className).toContain('touch-manipulation');
    expect(screen.getByTestId('sensor-profile-name').className).toContain('text-[11px]');
    expect(screen.getByTestId('sensor-profile-name').className).toContain('whitespace-normal');
    expect(screen.getByTestId('sensor-profile-description').className).toContain('text-[8px]');
    expect(screen.getByTestId('sensor-profile-description').className).toContain('whitespace-normal');
    expect(screen.getByTestId('sensor-profile-summary-grid').className).toContain('grid-cols-1');
    expect(screen.getByTestId('sensor-boost-window-card').className).toContain('col-span-1');
    expect(screen.getByTestId('sensor-calibration-grid').className).toContain('grid-cols-1');
    expect(screen.getByRole('spinbutton', { name: /signal minimum voltage/i })).toHaveAttribute('inputmode', 'decimal');
    expect(screen.getByRole('spinbutton', { name: /signal maximum voltage/i })).toHaveAttribute('inputmode', 'decimal');
    expect(screen.getByRole('spinbutton', { name: /pressure minimum absolute/i })).toHaveAttribute('inputmode', 'numeric');
    expect(screen.getByRole('spinbutton', { name: /pressure maximum absolute/i })).toHaveAttribute('inputmode', 'numeric');
    expect(screen.getByRole('spinbutton', { name: /signal minimum voltage/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('spinbutton', { name: /signal maximum voltage/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('spinbutton', { name: /pressure minimum absolute/i }).className).toContain('min-h-[2.35rem]');
    expect(screen.getByRole('spinbutton', { name: /pressure maximum absolute/i }).className).toContain('min-h-[2.35rem]');
  }, 15000);

  it('loads preset calibration values and re-enables editing in custom mode', () => {
    render(<App displayProfile="generic-ili9486-hat" />);

    fireEvent.click(screen.getByRole('button', { name: /open settings/i }));
    fireEvent.click(screen.getByRole('button', { name: /open map sensor mapping/i }));
    fireEvent.click(screen.getByRole('button', { name: /gm \/ delphi 3 bar/i }));

    expect(screen.getByRole('spinbutton', { name: /signal minimum voltage/i })).toHaveValue(0.3);
    expect(screen.getByRole('spinbutton', { name: /signal maximum voltage/i })).toHaveValue(4.9);
    expect(screen.getByRole('spinbutton', { name: /pressure minimum absolute/i })).toHaveValue(20);
    expect(screen.getByRole('spinbutton', { name: /pressure maximum absolute/i })).toHaveValue(300);
    expect(screen.getByRole('button', { name: /gm \/ delphi 3 bar/i }).className).toContain('flex-col');
    expect(screen.getByRole('spinbutton', { name: /signal minimum voltage/i })).toBeDisabled();
    expect(screen.getByRole('spinbutton', { name: /pressure maximum absolute/i })).toBeDisabled();

    fireEvent.click(screen.getByRole('button', { name: /custom ecu \/ haltech/i }));

    expect(screen.getByRole('button', { name: /custom ecu \/ haltech/i }).className).toContain('flex-col');
    expect(screen.getByRole('spinbutton', { name: /signal minimum voltage/i })).not.toBeDisabled();
    expect(screen.getByRole('spinbutton', { name: /signal maximum voltage/i })).not.toBeDisabled();
    expect(screen.getByRole('spinbutton', { name: /pressure minimum absolute/i })).not.toBeDisabled();
    expect(screen.getByRole('spinbutton', { name: /pressure maximum absolute/i })).not.toBeDisabled();
  }, 15000);

  it('migrates legacy generic 3 bar settings into the named GM preset', () => {
    localStorage.setItem('wmi_settings', JSON.stringify({
      sensorProfile: 'map-3bar',
      sensorSignalMinMv: 500,
      sensorSignalMaxMv: 4500,
      sensorKpaMin: 10,
      sensorKpaMax: 315,
    }));

    render(<App initialTab="sensor" displayProfile="generic-ili9486-hat" />);

    expect(screen.getByRole('button', { name: /gm \/ delphi 3 bar/i })).toBeInTheDocument();
    expect(screen.getByRole('spinbutton', { name: /signal minimum voltage/i })).toHaveValue(0.3);
    expect(screen.getByRole('spinbutton', { name: /signal maximum voltage/i })).toHaveValue(4.9);
    expect(screen.getByRole('spinbutton', { name: /pressure minimum absolute/i })).toHaveValue(20);
    expect(screen.getByRole('spinbutton', { name: /pressure maximum absolute/i })).toHaveValue(300);
  }, 15000);
});
