import { act, fireEvent, render, screen } from '@testing-library/react';
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
    vi.clearAllTimers();
    vi.useRealTimers();
  });

  it('shows bridge and hardware connection states separately', () => {
    render(<App />);

    const badge = screen.getByTestId('hardware-status');
    expect(badge).toHaveTextContent('OFF');
    expect(badge).toHaveAttribute('title', 'Bridge disconnected');

    const socket = MockWebSocket.instances[0];

    act(() => {
      socket.emitOpen();
    });

    expect(badge).toHaveTextContent('LINK');
    expect(badge).toHaveAttribute('title', 'Bridge online, waiting for controller');

    act(() => {
      socket.emitMessage({ type: 'status', serial_connected: true });
    });

    expect(badge).toHaveTextContent('HW');
    expect(badge).toHaveAttribute('title', 'Hardware connected');

    act(() => {
      socket.emitMessage({ type: 'status', serial_connected: false });
    });

    expect(badge).toHaveTextContent('LINK');

    act(() => {
      socket.emitClose();
    });

    expect(badge).toHaveTextContent('OFF');
  }, 15000);

  it('uses the compact layout on smaller displays', () => {
    setViewport(470, 320);

    render(<App />);

    expect(screen.getByTestId('dashboard-shell')).toHaveAttribute('data-compact', 'true');
    expect(screen.getByTestId('dashboard-header').className).toContain('p-2');
    expect(screen.getByTestId('dash-secondary-cards').className).toContain('grid-cols-1');
    expect(screen.getByTestId('dash-secondary-cards').className).toContain('grid-rows-2');

    fireEvent.click(screen.getByRole('button', { name: /open settings/i }));

    expect(screen.getByText(/system configuration/i).closest('.settings-page')?.className).toContain('compact-settings');
    expect(screen.getByTestId('trigger-inputs').className).toContain('min-h-[54px]');
    expect(screen.getByTestId('gauge-limit-min').className).toContain('grid-cols-2');
  }, 15000);

  it('can force the compact preview layout without a tiny browser window', () => {
    render(<App initialTab="settings" forceCompact embeddedPreview />);

    expect(screen.getByTestId('dashboard-shell')).toHaveAttribute('data-compact', 'true');
    expect(screen.getByText(/system configuration/i).closest('.settings-page')?.className).toContain('compact-settings');
    expect(screen.getByTestId('gauge-limit-min').className).toContain('grid-cols-2');
  }, 15000);
});
