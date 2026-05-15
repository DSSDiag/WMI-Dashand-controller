// Water Meth PERFECTION
// Dashboard + Controller UI for Raspberry Pi Zero 2 W / 5" touch screen.
// Connects to Python serial bridge (bridge/serial_bridge.py) via WebSocket when
// running on hardware.

import React, { useState, useEffect, useRef, useCallback } from 'react';
import { formatBoost as formatBoostUtil, ATM_PSI, PSI_TO_BAR, PSI_TO_KPA, PSI_TO_INHG } from './utils';
import {
  Droplet,
  AlertTriangle,
  Power,
  Gauge,
  RefreshCw,
  ChevronRight,
  ChevronLeft,
  Save,
  Zap,
  Sliders,
  TrendingUp,
  Minus,
  Plus,
  Wifi,
  WifiOff,
} from 'lucide-react';

// ---------------------------------------------------------------------------
// WebSocket hook — connects to the Python serial bridge on the Pi.
// Provides live telemetry and forwards settings changes to the ESP32.
// Falls back silently if the bridge is not running (simulation mode active).
// ---------------------------------------------------------------------------
const WS_URL = 'ws://localhost:8765';
const WS_RECONNECT_MS = 3000;

// Hardware revision label — update to match your PCB version
const HW_REVISION = 'MMWMI02B+';

// Default minimum boost (atmospheric vacuum ~30 inHg = -14.73 PSIg)
const DEFAULT_MIN_BOOST_PSI = -14.73;
const DASHBOARD_WIDTH = 480;
const DASHBOARD_HEIGHT = 320;
const DEFAULT_DASHBOARD_FIT_WIDTH = 500;
const DEFAULT_DASHBOARD_FIT_HEIGHT = 340;
const COMPACT_DASHBOARD_FIT_WIDTH = 520;
const COMPACT_DASHBOARD_FIT_HEIGHT = 356;

function getViewportScale(fitWidth, fitHeight) {
  if (typeof window === 'undefined') return 1;
  return Math.min(
    1,
    window.innerWidth / fitWidth,
    window.innerHeight / fitHeight,
  );
}

// ---------------------------------------------------------------------------
// Settings Persistence — localStorage key and helpers
// systemActive is intentionally excluded: the system always starts disarmed
// after a reboot for safety.
// ---------------------------------------------------------------------------
const SETTINGS_KEY = 'wmi_settings';

const DEFAULT_SETTINGS = {
  units: 'psi_inhg',
  pressureRef: 'gauge',
  minBoost: DEFAULT_MIN_BOOST_PSI,
  maxBoost: 20,
  triggerMode: 'thresholds',
  curve: 'linear',
  startInjectionAt: 5,
  fullInjectionAt: 25,
  manualDuty: 0,
};

function loadSettings() {
  try {
    const raw = localStorage.getItem(SETTINGS_KEY);
    if (raw) return { ...DEFAULT_SETTINGS, ...JSON.parse(raw) };
  } catch { /* ignore parse errors */ }
  return DEFAULT_SETTINGS;
}

function useSerialBridge({ onTelemetry, onStatus }) {
  const [connected, setConnected] = useState(false);
  const wsRef = useRef(null);
  const reconnectTimer = useRef(null);

  const connect = useCallback(function _connect() {
    if (wsRef.current) return;
    const ws = new WebSocket(WS_URL);
    wsRef.current = ws;

    ws.onopen = () => {
      setConnected(true);
      if (reconnectTimer.current) {
        clearTimeout(reconnectTimer.current);
        reconnectTimer.current = null;
      }
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data);
        if (msg.type === 'telemetry') {
          onTelemetry(msg);
        }
        if (msg.type === 'status' && onStatus) {
          onStatus(Boolean(msg.serial_connected));
        }
      } catch {
        /* ignore malformed frames */
      }
    };

    ws.onclose = () => {
      setConnected(false);
      wsRef.current = null;
      onStatus?.(false);
      reconnectTimer.current = setTimeout(_connect, WS_RECONNECT_MS);
    };

    ws.onerror = () => ws.close();
  }, [onTelemetry, onStatus]);

  useEffect(() => {
    connect();
    return () => {
      if (reconnectTimer.current) clearTimeout(reconnectTimer.current);
      if (wsRef.current) {
        wsRef.current.onclose = null; // prevent reconnect on unmount
        wsRef.current.close();
        wsRef.current = null;
      }
    };
  }, [connect]);

  const send = useCallback((payload) => {
    if (wsRef.current && wsRef.current.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify(payload));
    }
  }, []);

  return { connected, send };
}

// ---------------------------------------------------------------------------
// Main Application
// ---------------------------------------------------------------------------
const App = ({
  initialTab = 'dash',
  forceCompact = false,
  embeddedPreview = false,
  displayProfile = 'default',
}) => {
  const isCompactDisplay = forceCompact || displayProfile === 'generic-ili9486-hat';
  const dashboardFitWidth = isCompactDisplay ? COMPACT_DASHBOARD_FIT_WIDTH : DEFAULT_DASHBOARD_FIT_WIDTH;
  const dashboardFitHeight = isCompactDisplay ? COMPACT_DASHBOARD_FIT_HEIGHT : DEFAULT_DASHBOARD_FIT_HEIGHT;

  // Navigation State
  const [activeTab, setActiveTab] = useState(initialTab);
  const [viewportScale, setViewportScale] = useState(() => getViewportScale(dashboardFitWidth, dashboardFitHeight));
  const updateViewportScale = useCallback(() => {
    setViewportScale(getViewportScale(dashboardFitWidth, dashboardFitHeight));
  }, [dashboardFitHeight, dashboardFitWidth]);

  // Settings State (Internal state is ALWAYS PSI Gauge: 0 = Atmosphere)
  // Initial values are loaded from localStorage so they survive reboots.
  const [units, setUnits] = useState(() => loadSettings().units); // 'psi', 'psi_inhg', 'bar', 'kpa'
  const [pressureRef, setPressureRef] = useState(() => loadSettings().pressureRef); // 'gauge', 'abs'

  // Default to ~30inHg vacuum (-14.7 PSIg) and 20 PSI max
  const [minBoost, setMinBoost] = useState(() => loadSettings().minBoost);
  const [maxBoost, setMaxBoost] = useState(() => loadSettings().maxBoost);

  const [triggerMode, setTriggerMode] = useState(() => loadSettings().triggerMode);
  const [curve, setCurve] = useState(() => loadSettings().curve); // 'linear' or 'exponential'
  const [startInjectionAt, setStartInjectionAt] = useState(() => loadSettings().startInjectionAt);
  const [fullInjectionAt, setFullInjectionAt] = useState(() => loadSettings().fullInjectionAt);
  const [manualDuty, setManualDuty] = useState(() => loadSettings().manualDuty);

  // Sensor & System State
  const [rawBoost, setRawBoost] = useState(0); // Internal PSI Gauge
  const [peakBoost, setPeakBoost] = useState(DEFAULT_MIN_BOOST_PSI); // Peak Hold Memory
  const [boostHistory, setBoostHistory] = useState(Array(50).fill(DEFAULT_MIN_BOOST_PSI)); // Telemetry sparkline
  const [dutyCycle, setDutyCycle] = useState(0);
  const [tankIsLow, setTankIsLow] = useState(false);
  const [systemActive, setSystemActive] = useState(false);
  const [status, setStatus] = useState('Standby');
  const [isPriming, setIsPriming] = useState(false);

  // Hardware bridge state
  const [serialConnected, setSerialConnected] = useState(false);

  // --- UNIT CONVERSION LOGIC ---
  const formatBoost = (psiGauge) => formatBoostUtil(psiGauge, units, pressureRef);

  const getUnitLabel = () => {
    if (units === 'psi_inhg') return 'PSI/inHg';
    return units.toUpperCase();
  };

  const toInputVal = (psiGauge) => {
    const isAbs = pressureRef === 'abs' && units !== 'psi_inhg';
    const displayValue = isAbs ? psiGauge + ATM_PSI : psiGauge;
    if (units === 'bar') return (displayValue * PSI_TO_BAR).toFixed(2);
    if (units === 'kpa') return (displayValue * PSI_TO_KPA).toFixed(1);
    if (units === 'psi_inhg') {
      if (psiGauge < 0) return (psiGauge * -PSI_TO_INHG).toFixed(0);
      return psiGauge.toFixed(1);
    }
    return displayValue.toFixed(1);
  };

  const fromInputVal = (val, isMinField) => {
    const v = typeof val === 'number' ? val : parseFloat(val);
    if (isNaN(v)) return 0;
    const isAbs = pressureRef === 'abs' && units !== 'psi_inhg';
    if (units === 'bar') return (v / PSI_TO_BAR) - (isAbs ? ATM_PSI : 0);
    if (units === 'kpa') return (v / PSI_TO_KPA) - (isAbs ? ATM_PSI : 0);
    if (units === 'psi_inhg') {
      if (isMinField && v > 0) return v * -(1 / PSI_TO_INHG);
      return v;
    }
    return v - (isAbs ? ATM_PSI : 0);
  };

  const getInputUnitLabel = (isMinField) => {
    if (units === 'psi_inhg') return isMinField ? 'inHg' : 'PSI';
    const suffix = pressureRef === 'abs' ? ' (Abs)' : ' (Gauge)';
    return `${units.toUpperCase()}${suffix}`;
  };

  const getStepValue = () => {
    if (units === 'bar') return 0.07;
    if (units === 'kpa') return 6.9;
    return 1;
  };

  const handleAdjust = (isMin, direction) => {
    const step = getStepValue();
    let currentUIVal = parseFloat(toInputVal(isMin ? minBoost : maxBoost));
    let newUIVal = currentUIVal + (direction === 'up' ? step : -step);
    newUIVal = Math.round(newUIVal * 100) / 100;
    let newInternalVal = fromInputVal(newUIVal, isMin);
    if (isMin) {
      if (newInternalVal < -ATM_PSI) newInternalVal = -ATM_PSI;
      setMinBoost(newInternalVal);
      if (startInjectionAt < newInternalVal) setStartInjectionAt(newInternalVal);
      if (fullInjectionAt < newInternalVal) setFullInjectionAt(newInternalVal + 1);
    } else {
      if (newInternalVal > 200) newInternalVal = 200;
      setMaxBoost(newInternalVal);
      if (fullInjectionAt > newInternalVal) setFullInjectionAt(newInternalVal);
      if (startInjectionAt > newInternalVal) setStartInjectionAt(newInternalVal - 1);
    }
  };

  // ---------------------------------------------------------------------------
  // WebSocket / Hardware Bridge
  // Telemetry from ESP32 overrides simulation when bridge is connected.
  // ---------------------------------------------------------------------------
  const handleTelemetry = useCallback((msg) => {
    // msg: { type, pressure_psi, pump_duty, tank_low }
    const psi = parseFloat(msg.pressure_psi);
    if (!isNaN(psi)) {
      setRawBoost(psi);
      setPeakBoost((prev) => Math.max(prev, psi));
      setBoostHistory((prev) => [...prev.slice(1), psi]);
    }
    if (typeof msg.pump_duty === 'number') setDutyCycle(msg.pump_duty);
    if (typeof msg.tank_low === 'boolean') setTankIsLow(msg.tank_low);
    if (typeof msg.pump_active === 'boolean') {
      setStatus(msg.pump_active ? 'Injecting' : 'Monitoring');
    }
  }, []);

  const handleBridgeStatus = useCallback((isSerialConnected) => {
    setSerialConnected(isSerialConnected);
  }, []);

  const { connected: bridgeConnected, send: wsSend } = useSerialBridge({
    onTelemetry: handleTelemetry,
    onStatus: handleBridgeStatus,
  });
  const hwConnected = bridgeConnected && serialConnected;

  // Send settings to ESP32 whenever they change (only when hardware is connected)
  useEffect(() => {
    if (!hwConnected) return;
    wsSend({
      type: 'settings',
      system_active: systemActive,
      trigger_mode: triggerMode,
      start_psi: startInjectionAt,
      full_psi: fullInjectionAt,
      manual_duty: manualDuty,
      curve,
      min_boost: minBoost,
      max_boost: maxBoost,
    });
  }, [hwConnected, wsSend, systemActive, triggerMode, startInjectionAt, fullInjectionAt, manualDuty, curve, minBoost, maxBoost]);

  // Persist user settings to localStorage so they survive reboots.
  // systemActive is intentionally excluded — system always starts disarmed.
  useEffect(() => {
    try {
      localStorage.setItem(SETTINGS_KEY, JSON.stringify({
        units, pressureRef, minBoost, maxBoost,
        triggerMode, curve, startInjectionAt, fullInjectionAt, manualDuty,
      }));
    } catch { /* ignore quota / security errors */ }
  }, [units, pressureRef, minBoost, maxBoost, triggerMode, curve, startInjectionAt, fullInjectionAt, manualDuty]);


  const handlePrime = () => {
    setIsPriming(true);
    if (hwConnected) wsSend({ type: 'prime' });
    setTimeout(() => setIsPriming(false), 2000);
  };

  const isOutOfBounds = rawBoost < minBoost || rawBoost > maxBoost;

  // Graph Calculations
  const range = (maxBoost - minBoost) || 1;
  const graphPoints = boostHistory.map((val, i) => {
    const x = (i / (boostHistory.length - 1)) * 100;
    const clamped = Math.max(minBoost, Math.min(maxBoost, val));
    const y = 100 - ((clamped - minBoost) / range) * 100;
    return `${x.toFixed(1)},${y.toFixed(1)}`;
  }).join(' ');

  const thresholdY =
    triggerMode === 'full_scale'
      ? 100
      : Math.max(0, Math.min(100, 100 - ((startInjectionAt - minBoost) / range) * 100));
  const boostPercent = Math.max(0, Math.min(100, ((rawBoost - minBoost) / range) * 100));
  const boostNeedleAngle = -135 + (boostPercent * 2.7);
  const compactPad = isCompactDisplay ? 'p-1.5 gap-1.5' : 'p-2 gap-2';
  const compactGaugeTheme = isCompactDisplay
    ? {
        arcStartOpacity: 0.34,
        arcMidOpacity: 0.16,
        arcEndOpacity: 0.04,
        needleStartOpacity: 0.34,
        needleMidOpacity: 0.12,
        needleEndOpacity: 0.03,
        centerOpacity: 0.3,
        needleWidth: 5,
        centerRadius: 8,
      }
    : {
        arcStartOpacity: 1,
        arcMidOpacity: 0.72,
        arcEndOpacity: 0.22,
        needleStartOpacity: 0.95,
        needleMidOpacity: 0.55,
        needleEndOpacity: 0.18,
        centerOpacity: 0.85,
        needleWidth: 7,
        centerRadius: 10,
      };
  const mainGaugeLayerClass = isCompactDisplay
    ? 'right-[-8.4rem] top-[0.4rem] opacity-45'
    : 'right-[-6.25rem] top-[0.8rem] opacity-70';
  const pumpGaugeLayerClass = isCompactDisplay
    ? 'left-[-22.5rem] top-[-1rem] opacity-12'
    : 'left-[-21.85rem] top-[-0.75rem] opacity-18';
  const compactHeaderControlsClass = isCompactDisplay
    ? 'grid grid-cols-3 gap-1.5'
    : 'flex items-center gap-3';
  const connectionIndicator = hwConnected
    ? {
        label: 'HW',
        title: 'Hardware connected',
        tone: 'bg-lime-500/10 border-lime-500/30 text-lime-400',
        Icon: Wifi,
      }
    : bridgeConnected
      ? {
          label: 'LINK',
          title: 'Bridge online, waiting for controller',
          tone: 'bg-amber-500/10 border-amber-500/30 text-amber-400',
          Icon: Wifi,
        }
      : {
          label: 'OFF',
          title: 'Bridge disconnected',
          tone: 'bg-red-500/10 border-red-500/30 text-red-500',
          Icon: WifiOff,
        };

  useEffect(() => {
    updateViewportScale();
    window.addEventListener('resize', updateViewportScale);
    window.addEventListener('orientationchange', updateViewportScale);

    const viewport = window.visualViewport;
    viewport?.addEventListener('resize', updateViewportScale);
    viewport?.addEventListener('scroll', updateViewportScale);

    return () => {
      window.removeEventListener('resize', updateViewportScale);
      window.removeEventListener('orientationchange', updateViewportScale);
      viewport?.removeEventListener('resize', updateViewportScale);
      viewport?.removeEventListener('scroll', updateViewportScale);
    };
  }, [updateViewportScale]);

  const renderBoostGaugeLayer = (className, idSuffix) => (
    <div className={`absolute w-[30rem] h-[30rem] pointer-events-none z-0 ${className}`}>
      <svg viewBox="0 0 240 240" className="w-full h-full" style={{ transform: 'rotate(135deg)' }}>
        <defs>
          <linearGradient id={`boostArcFade-${idSuffix}`} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#a3e635" stopOpacity={compactGaugeTheme.arcStartOpacity} />
            <stop offset="62%" stopColor="#a3e635" stopOpacity={compactGaugeTheme.arcMidOpacity} />
            <stop offset="100%" stopColor="#a3e635" stopOpacity={compactGaugeTheme.arcEndOpacity} />
          </linearGradient>
          <linearGradient id={`boostNeedleFade-${idSuffix}`} x1="0" y1="0" x2="1" y2="0">
            <stop offset="0%" stopColor="#ecfccb" stopOpacity={compactGaugeTheme.needleStartOpacity} />
            <stop offset="70%" stopColor="#a3e635" stopOpacity={compactGaugeTheme.needleMidOpacity} />
            <stop offset="100%" stopColor="#a3e635" stopOpacity={compactGaugeTheme.needleEndOpacity} />
          </linearGradient>
        </defs>
        <circle
          cx="120" cy="120" r="100"
          fill="none" stroke="currentColor" strokeWidth="28"
          strokeLinecap="round" className="text-slate-800"
          strokeDasharray="471.24 628.32"
        />
        <circle
          cx="120" cy="120" r="100"
          fill="none" stroke={`url(#boostArcFade-${idSuffix})`} strokeWidth="28"
          strokeLinecap="round" className="transition-all duration-100 ease-linear"
          strokeDasharray={`${(boostPercent / 100) * 471.24} 628.32`}
        />
        <g
          className="transition-transform duration-100 ease-linear"
          style={{
            transformOrigin: '120px 120px',
            transform: `rotate(${boostNeedleAngle}deg)`,
          }}
        >
          <line
            x1="120" y1="120" x2="120" y2="28"
            stroke={`url(#boostNeedleFade-${idSuffix})`} strokeWidth={compactGaugeTheme.needleWidth}
            strokeLinecap="round"
          />
          <circle cx="120" cy="120" r={compactGaugeTheme.centerRadius} fill="#a3e635" opacity={compactGaugeTheme.centerOpacity} />
        </g>
      </svg>
    </div>
  );

  return (
    <div className={`${embeddedPreview ? 'h-full w-full' : 'h-screen w-screen'} overflow-hidden bg-slate-950 text-slate-100`}>
      <div className="flex h-full w-full items-center justify-center">
        <div
          className="relative origin-center"
          style={{
            width: `${DASHBOARD_WIDTH}px`,
            height: `${DASHBOARD_HEIGHT}px`,
            transform: `scale(${viewportScale})`,
          }}
        >
          <div
            data-testid="dashboard-shell"
            data-compact={isCompactDisplay ? 'true' : 'false'}
            className={`h-full w-full font-sans flex flex-col select-none overflow-hidden relative touch-manipulation ${compactPad}`}
          >

            <div className="absolute -top-12 -left-12 w-32 h-32 bg-lime-500/10 rounded-full blur-[60px] pointer-events-none" />
            <div className="absolute -bottom-12 -right-12 w-32 h-32 bg-cyan-500/10 rounded-full blur-[60px] pointer-events-none" />

      <div
        className="flex-1 flex transition-transform duration-200 ease-out h-full"
        style={{ transform: activeTab === 'dash' ? 'translateX(0%)' : 'translateX(-100%)' }}
      >

        {/* ================================================================
            DASHBOARD PAGE
            ================================================================ */}
        <div className={`min-w-full flex flex-col ${isCompactDisplay ? 'gap-1.5' : 'gap-2'}`}>
          {/* Header */}
          <div
            data-testid="dashboard-header"
            className={`flex justify-between items-center bg-slate-900/80 backdrop-blur-md rounded-xl border border-slate-800 shadow-md ${isCompactDisplay ? 'p-2' : 'p-3'}`}
          >
            <div className={`flex items-center min-w-0 ${isCompactDisplay ? 'gap-2' : 'gap-3'}`}>
              <div className={`${isCompactDisplay ? 'w-10 h-10 rounded-lg p-1' : 'w-12 h-12 rounded-xl p-1.5'} bg-black border border-slate-700 flex items-center justify-center shadow-[0_0_14px_rgba(163,230,53,0.18)] overflow-hidden flex-shrink-0`}>
                <img
                  src="/logo.png"
                  alt="Logo"
                  className="w-full h-full object-contain"
                  onError={(e) => { e.currentTarget.style.display = 'none'; }}
                />
              </div>
              <div className="flex flex-col justify-center min-w-0">
                <h1 className={`${isCompactDisplay ? 'text-lg' : 'text-xl'} font-black tracking-tight leading-none italic`}>
                  <span className="text-white">MILD</span>
                  <span className="mx-1"> </span>
                  <span className="text-lime-400">MODZ</span>
                </h1>
                <p className={`${isCompactDisplay ? 'text-[9px] mt-0.5' : 'text-xs mt-1'} uppercase tracking-widest text-slate-500 font-bold`}>
                  <span className={`${isCompactDisplay ? 'mr-1 text-lime-700/90' : 'mr-1.5 text-lime-700'}`}>NOTHING MILD</span>
                  <span>·</span>
                  <span className={`${isCompactDisplay ? 'ml-1 w-24' : 'ml-1.5 w-28'} truncate inline-block align-bottom`}>{status}</span>
                </p>
              </div>
            </div>

            <div
              data-testid="dashboard-actions"
              className={`${compactHeaderControlsClass} flex-shrink-0`}
            >
              {/* Hardware connection indicator */}
              <div
                data-testid="hardware-status"
                title={connectionIndicator.title}
                className={`flex items-center rounded-lg border font-bold uppercase tracking-wider ${isCompactDisplay ? 'col-span-3 min-h-[2.35rem] justify-center gap-1.5 px-2 py-1 text-[10px]' : 'gap-1.5 px-2 py-1 text-xs'} ${connectionIndicator.tone}`}
              >
                <connectionIndicator.Icon size={isCompactDisplay ? 12 : 15} />
                <span className="inline">{connectionIndicator.label}</span>
              </div>

              <button
                onClick={handlePrime}
                disabled={isPriming || !systemActive}
                aria-label="Prime system"
                className={`flex items-center rounded-lg border transition-all ${isCompactDisplay ? 'gap-1 px-2 py-1.5 text-[11px]' : 'gap-1.5 px-3 py-2'} ${isPriming ? 'bg-amber-500/20 border-amber-500 text-amber-500' : 'bg-slate-800 border-slate-700 active:scale-95 disabled:opacity-30'}`}
              >
                <RefreshCw size={isCompactDisplay ? 14 : 18} className={isPriming ? 'animate-spin' : ''} />
                <span className={`${isCompactDisplay ? 'text-[11px]' : 'text-sm'} font-bold uppercase inline`}>Purge</span>
              </button>

              <button
                onClick={() => setSystemActive(!systemActive)}
                aria-label={systemActive ? 'Kill system' : 'Arm system'}
                className={`flex items-center rounded-lg font-bold uppercase tracking-wider transition-all shadow-md justify-center ${isCompactDisplay ? 'gap-1 px-2 py-1.5 text-sm' : 'gap-1.5 px-4 py-2 text-base'} ${systemActive ? 'bg-red-600 shadow-red-900/20' : 'bg-lime-600 shadow-lime-900/20'}`}
              >
                <Power size={isCompactDisplay ? 16 : 21} />
                {systemActive ? 'Kill' : 'Arm'}
              </button>

              <button
                onClick={() => setActiveTab('settings')}
                aria-label="Open settings"
                className={`${isCompactDisplay ? 'min-h-[2.35rem] px-2 py-1.5 flex items-center justify-center' : 'p-2'} rounded-lg bg-slate-800 border border-slate-700 hover:bg-slate-700 transition-colors`}
              >
                <ChevronRight size={isCompactDisplay ? 24 : 30} className="text-slate-400" />
              </button>
            </div>
          </div>

          {/* Main Grid */}
          <div className={`grid grid-cols-12 flex-1 min-h-0 ${isCompactDisplay ? 'gap-1.5' : 'gap-2'}`}>
            {/* Boost Gauge */}
            <div className={`col-span-7 bg-slate-900/50 rounded-xl border border-slate-800 flex flex-col justify-between relative overflow-hidden group z-10 ${isCompactDisplay ? 'p-2.5' : 'p-3'}`}>
              {renderBoostGaugeLayer(mainGaugeLayerClass, 'main')}

              <div className="relative z-10 flex-1 flex flex-col">
                <div className="flex items-center gap-1">
                  <span className="text-[10px] font-bold text-slate-500 uppercase tracking-widest">Manifold Pressure</span>
                  {triggerMode === 'full_scale' && (
                    <span className="text-[8px] bg-lime-500/20 text-lime-400 px-1.5 py-0.5 rounded border border-lime-500/30">FULL SCALE</span>
                  )}
                </div>
                <div className="flex flex-col mt-1">
                  <span className={`${isCompactDisplay ? 'text-5xl' : 'text-6xl'} font-black tracking-tighter tabular-nums drop-shadow-md leading-none transition-colors duration-300 ${isOutOfBounds ? 'text-red-500' : 'text-white'}`}>
                    {formatBoost(rawBoost)}
                  </span>
                  <div className="flex items-end gap-2 mt-1">
                    <span className={`text-lg font-bold drop-shadow-md transition-colors duration-300 ${isOutOfBounds ? 'text-red-500' : 'text-lime-400'}`}>
                      {getUnitLabel()}
                    </span>
                    <span className={`text-[10px] font-bold uppercase tracking-widest transition-colors duration-300 mb-0.5 ${isOutOfBounds ? 'text-red-500' : 'text-slate-500'}`}>
                      {pressureRef === 'abs' && units !== 'psi_inhg' ? 'ABSOLUTE' : 'GAUGE'}
                    </span>
                  </div>
                </div>

                {/* Telemetry Sparkline */}
                <div className="flex-1 w-full mt-2 flex flex-col justify-end relative min-h-[50px]">
                  <div className="absolute top-0 right-0 text-right z-20">
                    <div className="flex items-center justify-end gap-1 mb-0.5">
                      <span className="text-[8px] text-slate-500 font-bold uppercase tracking-widest">Peak</span>
                      <button
                        onClick={() => setPeakBoost(minBoost)}
                        className="text-[8px] bg-slate-800/80 text-slate-400 px-1 py-0.5 rounded border border-slate-700 hover:bg-slate-300 transition-colors cursor-pointer"
                      >
                        RESET
                      </button>
                    </div>
                    <div className="text-lg font-black text-slate-300 tabular-nums leading-none">
                      {formatBoost(peakBoost)}
                    </div>
                  </div>

                  <div className="w-full h-12 relative z-10 opacity-70">
                    <svg width="100%" height="100%" viewBox="0 0 100 100" preserveAspectRatio="none" className="overflow-visible">
                      <defs>
                        <linearGradient id="lineGrad" x1="0" y1="0" x2="0" y2="1">
                          <stop offset="0%" stopColor="#a3e635" stopOpacity="0.4" />
                          <stop offset="100%" stopColor="#a3e635" stopOpacity="0" />
                        </linearGradient>
                      </defs>
                      <polygon points={`0,100 ${graphPoints} 100,100`} fill="url(#lineGrad)" />
                      <polyline points={graphPoints} fill="none" stroke="#a3e635" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                      {triggerMode !== 'manual' && (
                        <line x1="0" y1={thresholdY} x2="100" y2={thresholdY} stroke="#0ea5e9" strokeWidth="1" strokeDasharray="4 4" opacity="0.6" />
                      )}
                    </svg>
                  </div>
                </div>
              </div>

              {/* Boost progress bar */}
              <div className={`w-full bg-slate-800 rounded-full overflow-hidden border border-slate-700 p-0.5 relative z-10 flex-shrink-0 ${isCompactDisplay ? 'h-3.5 mt-1.5' : 'h-4 mt-2'}`}>
                <div
                  className="h-full bg-gradient-to-r from-lime-600 to-emerald-400 rounded-full transition-all duration-100"
                  style={{ width: `${Math.max(0, Math.min(100, ((rawBoost - minBoost) / (maxBoost - minBoost)) * 100))}%` }}
                />
              </div>
            </div>

            <div className={`col-span-5 flex flex-col z-10 ${isCompactDisplay ? 'gap-1.5' : 'gap-2'}`}>
              {/* Pump Flow */}
              <div className={`flex-1 bg-slate-900/40 rounded-xl border border-slate-800 flex items-center justify-between relative overflow-hidden ${isCompactDisplay ? 'p-2.5' : 'p-3'}`}>
                {renderBoostGaugeLayer(pumpGaugeLayerClass, 'pump')}
                <div className="flex flex-col relative z-10">
                  <span className="text-[10px] font-bold text-slate-500 uppercase tracking-widest">Pump Flow</span>
                  <span className={`${isCompactDisplay ? 'text-5xl' : 'text-6xl'} font-black tracking-tighter tabular-nums leading-none transition-colors duration-300 ${Math.round(dutyCycle) >= 100 ? 'text-red-500 drop-shadow-md' : 'text-white'}`}>
                    {Math.round(dutyCycle)}%
                  </span>
                  {triggerMode === 'manual' && (
                    <span className="text-[8px] text-amber-500 font-bold uppercase mt-1">MANUAL</span>
                  )}
                </div>

                {/* Injector SVG */}
                <div className="h-20 w-16 flex flex-col items-center justify-start relative mr-1 z-10">
                  <svg width="100%" height="100%" viewBox="0 0 60 110" className="overflow-visible">
                    <defs>
                      <linearGradient id="sprayGrad" x1="0" y1="0" x2="0" y2="1">
                        <stop offset="0%" stopColor="#06b6d4" stopOpacity="0.8" />
                        <stop offset="100%" stopColor="#22d3ee" stopOpacity="0" />
                      </linearGradient>
                    </defs>
                    <path
                      d="M24,0 h12 v8 l4,4 v14 l-6,8 v10 h-8 v-10 l-6,-8 v-14 l4,-4 v-8 z"
                      fill={systemActive ? '#1e293b' : '#0f172a'}
                      stroke={systemActive ? '#06b6d4' : '#334155'}
                      strokeWidth="2" strokeLinejoin="round"
                      className="transition-colors duration-300"
                    />
                    <line x1="20" y1="12" x2="40" y2="12" stroke={systemActive ? '#06b6d4' : '#334155'} strokeWidth="2" className="transition-colors duration-300" />
                    <line x1="26" y1="34" x2="34" y2="34" stroke={systemActive ? '#06b6d4' : '#334155'} strokeWidth="2" className="transition-colors duration-300" />
                    <rect
                      x="27" y="44" width="6" height="4" rx="1"
                      fill={systemActive ? '#a3e635' : '#334155'}
                      className={`transition-all duration-300 ${systemActive ? 'drop-shadow-[0_0_8px_rgba(163,230,53,1)]' : ''}`}
                    />
                    <g style={{
                      transformOrigin: '30px 48px',
                      transform: `scaleY(${dutyCycle / 100})`,
                      opacity: dutyCycle > 0 ? 1 : 0,
                      transition: 'transform 0.1s linear',
                    }}>
                      <polygon points="30,48 0,110 60,110" fill="url(#sprayGrad)" />
                      <line x1="30" y1="48" x2="30" y2="110" stroke="#cffafe" strokeWidth="2" strokeDasharray="8 6" className="animate-spray" opacity="0.9" />
                      <line x1="30" y1="48" x2="10" y2="105" stroke="#a5f3fc" strokeWidth="1.5" strokeDasharray="6 8" className="animate-spray-fast" opacity="0.6" />
                      <line x1="30" y1="48" x2="50" y2="105" stroke="#a5f3fc" strokeWidth="1.5" strokeDasharray="6 8" className="animate-spray-fast" opacity="0.6" />
                      <line x1="30" y1="48" x2="20" y2="108" stroke="#cffafe" strokeWidth="1" strokeDasharray="4 4" className="animate-spray-slow" opacity="0.4" />
                      <line x1="30" y1="48" x2="40" y2="108" stroke="#cffafe" strokeWidth="1" strokeDasharray="4 4" className="animate-spray-slow" opacity="0.4" />
                    </g>
                  </svg>
                </div>
              </div>

              <div
                data-testid="dash-secondary-cards"
                className={`${isCompactDisplay ? 'grid grid-cols-1 grid-rows-2 gap-1.5 h-[5.75rem]' : 'flex gap-2 h-14'} flex-shrink-0`}
              >
                {/* Map Curve Display */}
                <div className={`flex-1 bg-slate-900/50 rounded-xl border border-slate-800 ${isCompactDisplay ? 'px-2 py-1.5 items-start' : 'p-2 items-center'} flex flex-col justify-center shadow-inner`}>
                  <span className="text-[8px] font-bold text-slate-500 uppercase tracking-widest mb-1">Curve</span>
                  <div className="flex items-center gap-1">
                    <span className="text-[10px] font-black text-lime-400 uppercase tracking-widest">{curve}</span>
                    <div className="w-5 h-4 flex items-center justify-center text-lime-400">
                      <svg width="20" height="12" viewBox="0 0 32 20" className="overflow-visible">
                        {curve === 'linear' ? (
                          <line x1="0" y1="12" x2="20" y2="0" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
                        ) : (
                          <path d="M0,12 Q15,12 20,0" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" />
                        )}
                      </svg>
                    </div>
                  </div>
                </div>

                {/* Tank Status */}
                <div className={`flex-1 rounded-xl border flex ${isCompactDisplay ? 'flex-row justify-between px-2 py-1.5' : 'flex-col justify-center items-center p-2'} items-center gap-1 transition-all ${tankIsLow ? 'bg-red-950/30 border-red-500/50 shadow-md shadow-red-900/20' : 'bg-slate-900/50 border-slate-800'}`}>
                  <div className="flex items-center gap-1.5">
                    <div className={`${tankIsLow ? 'text-red-500 animate-pulse' : 'text-slate-500'}`}>
                      {tankIsLow ? <AlertTriangle size={14} /> : <Droplet size={14} />}
                    </div>
                    <span className="text-[8px] font-bold text-slate-500 uppercase tracking-widest">Tank</span>
                  </div>
                  <span className={`text-xs font-black ${tankIsLow ? 'text-red-500' : 'text-emerald-400'}`}>
                    {tankIsLow ? 'LOW' : 'OK'}
                  </span>
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* ================================================================
            SETTINGS PAGE
            ================================================================ */}
        <div className={`settings-page min-w-full flex flex-col ${isCompactDisplay ? 'compact-settings gap-1' : 'gap-2'}`}>
            <div className={`flex justify-between items-center bg-slate-900/80 rounded-xl border border-slate-800 shadow-md ${isCompactDisplay ? 'p-1.5' : 'p-3'}`}>
              <div className={`flex items-center min-w-0 ${isCompactDisplay ? 'gap-1.5' : 'gap-3'}`}>
              <button
                onClick={() => setActiveTab('dash')}
                aria-label="Return to dashboard"
                className={`${isCompactDisplay ? 'p-1' : 'p-2'} bg-slate-800 rounded-lg hover:bg-slate-700 transition-colors`}
              >
                <ChevronLeft size={isCompactDisplay ? 24 : 30} />
              </button>
              <div className="flex flex-col min-w-0">
                <h2 className={`${isCompactDisplay ? 'text-base' : 'text-xl'} font-black uppercase tracking-tight leading-none`}>System Configuration</h2>
                <span className={`${isCompactDisplay ? 'text-[9px] mt-0' : 'text-xs mt-1'} text-slate-400 font-bold uppercase tracking-widest`}>
                  HW REV: <span className="text-lime-400">{HW_REVISION}</span>
                </span>
              </div>
            </div>
            <button
              onClick={() => setActiveTab('dash')}
              aria-label="Save settings and return to dashboard"
              className={`flex items-center gap-1.5 bg-lime-600 rounded-lg font-bold shadow-md shadow-lime-900/20 active:scale-95 ${isCompactDisplay ? 'px-2.5 py-1 text-[11px]' : 'px-4 py-2 text-sm'}`}
            >
              <Save size={isCompactDisplay ? 16 : 21} /> <span className="inline">SAVE & EXIT</span>
            </button>
          </div>

          <div className={`grid grid-cols-2 flex-1 overflow-y-auto custom-scrollbar ${isCompactDisplay ? 'gap-1 pr-0' : 'gap-2 pr-1'}`}>
            {/* Column 1: Display & Units */}
            <div className={`bg-slate-900/50 rounded-xl border border-slate-800 flex flex-col h-fit ${isCompactDisplay ? 'p-2 gap-1.5' : 'p-3 gap-3'}`}>
              <div>
                <label className="text-[10px] font-bold text-slate-500 uppercase tracking-widest block mb-1.5">Pressure Units</label>
                <div className="grid grid-cols-4 gap-1 mb-1.5">
                  {['psi', 'psi_inhg', 'bar', 'kpa'].map((u) => (
                    <button
                      key={u}
                      onClick={() => {
                        setUnits(u);
                        if (u === 'psi_inhg') setPressureRef('gauge');
                      }}
                      className={`py-1.5 rounded-lg text-[10px] font-bold uppercase border transition-all ${units === u ? 'bg-lime-500 border-lime-400 text-black shadow-md shadow-lime-500/20' : 'bg-slate-800 border-slate-700 text-slate-400 hover:border-slate-500'}`}
                    >
                      {u.replace('_', '+')}
                    </button>
                  ))}
                </div>

                {units !== 'psi_inhg' && (
                  <div className="flex gap-1 p-0.5 bg-black rounded-lg border border-slate-800 animate-in fade-in duration-300">
                    <button
                      onClick={() => setPressureRef('gauge')}
                      className={`flex-1 py-1 rounded-[6px] text-[8px] font-bold uppercase transition-all ${pressureRef === 'gauge' ? 'bg-slate-800 text-white' : 'text-slate-500'}`}
                    >
                      Gauge (PSIg)
                    </button>
                    <button
                      onClick={() => setPressureRef('abs')}
                      className={`flex-1 py-1 rounded-[6px] text-[8px] font-bold uppercase transition-all ${pressureRef === 'abs' ? 'bg-slate-800 text-white' : 'text-slate-500'}`}
                    >
                      Absolute (PSIa)
                    </button>
                  </div>
                )}
              </div>

              <div>
                <label className="text-[10px] font-bold text-slate-500 uppercase tracking-widest block mb-1.5">Gauge Scaling Limits</label>
                <div className={`${isCompactDisplay ? 'flex gap-1.5' : 'flex gap-2'}`}>
                  {/* MIN INPUT */}
                  <div className="flex-1">
                    <span className="text-[8px] text-slate-500 block font-bold mb-0.5">MIN ({getInputUnitLabel(true)})</span>
                    <div
                      data-testid="gauge-limit-min"
                      className={`${isCompactDisplay ? 'grid grid-cols-2 grid-rows-[1.9rem_1.95rem]' : 'flex h-8'} bg-slate-800 border border-slate-700 rounded-lg overflow-hidden focus-within:border-lime-500 transition-colors`}
                    >
                      <button
                        onClick={() => handleAdjust(true, 'down')}
                        className={`${isCompactDisplay ? 'min-h-0 px-2 py-1 border-b' : 'px-2 py-1 border-r'} bg-slate-900/50 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors active:scale-95 flex items-center justify-center border-slate-700`}
                      >
                        <Minus size={14} />
                      </button>
                      <button
                        onClick={() => handleAdjust(true, 'up')}
                        className={`${isCompactDisplay ? 'min-h-0 px-2 py-1 border-l border-b' : 'px-4 py-2 border-l'} bg-slate-900/50 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors active:scale-95 flex items-center justify-center border-slate-700`}
                      >
                        <Plus size={isCompactDisplay ? 14 : 18} />
                      </button>
                      <input
                        type="number"
                        inputMode="decimal"
                        aria-label="Minimum gauge limit"
                        value={toInputVal(minBoost)}
                        onChange={(e) => {
                          let val = fromInputVal(e.target.value, true);
                          if (val < -ATM_PSI) val = -ATM_PSI;
                          setMinBoost(val);
                          if (startInjectionAt < val) setStartInjectionAt(val);
                          if (fullInjectionAt < val) setFullInjectionAt(val + 1);
                        }}
                        className={`${isCompactDisplay ? 'col-span-2 h-[1.95rem] border-t' : 'w-full px-2 py-2'} bg-transparent text-center text-white font-bold outline-none hide-arrows border-slate-700`}
                      />
                    </div>
                  </div>

                  {/* MAX INPUT */}
                  <div className="flex-1">
                    <span className="text-[8px] text-slate-500 block font-bold mb-0.5">MAX ({getInputUnitLabel(false)})</span>
                    <div
                      data-testid="gauge-limit-max"
                      className={`${isCompactDisplay ? 'grid grid-cols-2 grid-rows-[1.9rem_1.95rem]' : 'flex h-8'} bg-slate-800 border border-slate-700 rounded-lg overflow-hidden focus-within:border-lime-500 transition-colors`}
                    >
                      <button
                        onClick={() => handleAdjust(false, 'down')}
                        className={`${isCompactDisplay ? 'min-h-0 px-2 py-1 border-b' : 'px-2 py-1 border-r'} bg-slate-900/50 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors active:scale-95 flex items-center justify-center border-slate-700`}
                      >
                        <Minus size={14} />
                      </button>
                      <button
                        onClick={() => handleAdjust(false, 'up')}
                        className={`${isCompactDisplay ? 'min-h-0 px-2 py-1 border-l border-b' : 'px-2 py-1 border-l'} bg-slate-900/50 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors active:scale-95 flex items-center justify-center border-slate-700`}
                      >
                        <Plus size={14} />
                      </button>
                      <input
                        type="number"
                        inputMode="decimal"
                        aria-label="Maximum gauge limit"
                        value={toInputVal(maxBoost)}
                        onChange={(e) => {
                          let val = fromInputVal(e.target.value, false);
                          if (val > 200) val = 200;
                          setMaxBoost(val);
                          if (fullInjectionAt > val) setFullInjectionAt(val);
                          if (startInjectionAt > val) setStartInjectionAt(val - 1);
                        }}
                        className={`${isCompactDisplay ? 'col-span-2 h-[1.95rem] border-t text-sm' : 'w-full px-1 py-1 text-xs'} bg-transparent text-center text-white font-bold outline-none hide-arrows border-slate-700`}
                      />
                    </div>
                  </div>
                </div>

                {maxBoost > 30 && (
                  <div className="mt-2 p-1.5 bg-amber-500/10 border border-amber-500/30 rounded-lg flex items-center gap-1.5 text-amber-500 animate-in fade-in zoom-in-95 duration-300">
                    <AlertTriangle size={12} className="flex-shrink-0" />
                    <span className="text-[8px] font-bold uppercase leading-tight">External MAP Sensor must be connected</span>
                  </div>
                )}
              </div>
            </div>

            {/* Column 2: Trigger Logic */}
            <div className={`bg-slate-900/50 rounded-xl border border-slate-800 flex flex-col h-fit ${isCompactDisplay ? 'p-2 gap-1.5' : 'p-3 gap-3'}`}>
              {/* Map Curve Setting */}
              <div>
                <label className={`text-[10px] font-bold text-slate-500 uppercase tracking-widest block ${isCompactDisplay ? 'mb-1' : 'mb-1.5'}`}>Injection Map Curve</label>
                <div className="flex gap-1 p-0.5 bg-black rounded-lg border border-slate-800">
                  <button
                    onClick={() => setCurve('linear')}
                    className={`flex-1 py-1 rounded-[6px] text-[8px] font-bold uppercase transition-all flex items-center justify-center gap-1.5 ${curve === 'linear' ? 'bg-slate-800 text-lime-400' : 'text-slate-500 hover:text-slate-400'}`}
                  >
                    <TrendingUp size={12} /> Linear
                  </button>
                  <button
                    onClick={() => setCurve('exponential')}
                    className={`flex-1 py-1 rounded-[6px] text-[8px] font-bold uppercase transition-all flex items-center justify-center gap-1.5 ${curve === 'exponential' ? 'bg-slate-800 text-lime-400' : 'text-slate-500 hover:text-slate-400'}`}
                  >
                    <Zap size={12} /> Exponential
                  </button>
                </div>
              </div>

              <div className={`border-t border-slate-800 ${isCompactDisplay ? 'my-0' : 'my-0.5'}`}></div>

              <label className="text-[10px] font-bold text-slate-500 uppercase tracking-widest block">Injection Mapping Mode</label>

              <div className="flex gap-1 p-0.5 bg-black rounded-xl border border-slate-800">
                <button
                  onClick={() => setTriggerMode('thresholds')}
                  className={`flex-1 rounded-lg text-[8px] font-black uppercase transition-all flex items-center justify-center gap-1 ${isCompactDisplay ? 'py-1' : 'py-1.5'} ${triggerMode === 'thresholds' ? 'bg-slate-800 text-lime-400 shadow-inner' : 'text-slate-500'}`}
                >
                  <Zap size={10} /> Thresholds
                </button>
                <button
                  onClick={() => setTriggerMode('full_scale')}
                  className={`flex-1 rounded-lg text-[8px] font-black uppercase transition-all flex items-center justify-center gap-1 ${isCompactDisplay ? 'py-1' : 'py-1.5'} ${triggerMode === 'full_scale' ? 'bg-slate-800 text-lime-400 shadow-inner' : 'text-slate-500'}`}
                >
                  <Gauge size={10} /> Full Scale
                </button>
                <button
                  onClick={() => setTriggerMode('manual')}
                  className={`flex-1 rounded-lg text-[8px] font-black uppercase transition-all flex items-center justify-center gap-1 ${isCompactDisplay ? 'py-1' : 'py-1.5'} ${triggerMode === 'manual' ? 'bg-slate-800 text-amber-500 shadow-inner' : 'text-slate-500'}`}
                >
                  <Sliders size={10} /> Manual
                </button>
              </div>

              {/* Conditional Inputs */}
              <div
                data-testid="trigger-inputs"
                className={`${isCompactDisplay ? 'min-h-[54px] gap-1' : 'min-h-[70px] gap-1.5'} flex flex-col justify-center`}
              >
                {triggerMode === 'thresholds' && (
                  <div className={`${isCompactDisplay ? 'space-y-1' : 'space-y-1.5'} animate-in fade-in slide-in-from-top-2 duration-300`}>
                    <div>
                      <div className="flex justify-between text-[8px] font-bold uppercase mb-0.5">
                        <span className="text-slate-400">Injection Start:</span>
                        <span className="text-lime-400">{formatBoost(startInjectionAt)} {getUnitLabel()}</span>
                      </div>
                      <input type="range" min={minBoost} max={fullInjectionAt - 0.1} step="0.1" value={startInjectionAt} onChange={(e) => setStartInjectionAt(Number(e.target.value))} className="w-full accent-lime-500 h-1" />
                    </div>
                    <div>
                      <div className="flex justify-between text-[8px] font-bold uppercase mb-0.5">
                        <span className="text-slate-400">100% Flow:</span>
                        <span className="text-cyan-400">{formatBoost(fullInjectionAt)} {getUnitLabel()}</span>
                      </div>
                      <input type="range" min={startInjectionAt + 0.1} max={maxBoost} step="0.1" value={fullInjectionAt} onChange={(e) => setFullInjectionAt(Number(e.target.value))} className="w-full accent-cyan-500 h-1" />
                    </div>
                  </div>
                )}

                {triggerMode === 'full_scale' && (
                  <div className="bg-slate-800/40 p-2 rounded-lg border border-slate-700 text-center animate-in zoom-in-95 duration-300">
                    <p className="text-[9px] text-slate-300 font-bold uppercase leading-tight">
                      Pump will ramp linearly from <span className="text-lime-400">{formatBoost(minBoost)} {getUnitLabel()}</span> to <span className="text-cyan-400">{formatBoost(maxBoost)} {getUnitLabel()}</span>.
                    </p>
                    <p className="text-[8px] text-slate-500 mt-1 italic">Based on your Gauge Scaling settings.</p>
                  </div>
                )}

                {triggerMode === 'manual' && (
                  <div className="space-y-2 animate-in fade-in slide-in-from-bottom-2 duration-300">
                    <div>
                      <div className="flex justify-between text-[8px] font-bold uppercase mb-0.5">
                        <span className="text-amber-500 font-black">Manual Duty Cycle:</span>
                        <span className="text-white text-xs">{manualDuty}%</span>
                      </div>
                      <input type="range" min="0" max="100" value={manualDuty} onChange={(e) => setManualDuty(Number(e.target.value))} className="w-full accent-amber-500 h-1" />
                    </div>
                    <p className="text-[8px] text-red-400 font-bold uppercase text-center bg-red-950/20 py-0.5 rounded">
                      Caution: Fixed speed.
                    </p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Nav Dots */}
      <div className={`flex justify-center ${isCompactDisplay ? 'gap-1 pb-0.5' : 'gap-1.5 pb-1'}`}>
        <div className={`h-1 rounded-full transition-all duration-300 ${activeTab === 'dash' ? 'w-6 bg-lime-500 shadow-[0_0_10px_rgba(132,204,22,0.5)]' : 'w-1.5 bg-slate-700'}`} />
        <div className={`h-1 rounded-full transition-all duration-300 ${activeTab === 'settings' ? 'w-6 bg-lime-500 shadow-[0_0_10px_rgba(132,204,22,0.5)]' : 'w-1.5 bg-slate-700'}`} />
      </div>

          </div>
        </div>
      </div>
    </div>
  );
};

export default App;
