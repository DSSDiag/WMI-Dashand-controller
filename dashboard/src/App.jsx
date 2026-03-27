// Water Meth PERFECTION
// Dashboard + Controller UI for Raspberry Pi Zero 2 W / 5" touch screen.
// Connects to Python serial bridge (bridge/serial_bridge.py) via WebSocket when
// running on hardware. Falls back to built-in simulation when no bridge is present.

import React, { useState, useEffect, useRef, useCallback } from 'react';
import {
  Droplet,
  Activity,
  AlertTriangle,
  Settings,
  Power,
  Gauge,
  Thermometer,
  RefreshCw,
  ChevronRight,
  ChevronLeft,
  ChevronDown,
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

function useSerialBridge({ onTelemetry }) {
  const [connected, setConnected] = useState(false);
  const wsRef = useRef(null);
  const reconnectTimer = useRef(null);

  const connect = useCallback(() => {
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
        if (msg.type === 'telemetry') onTelemetry(msg);
      } catch {
        /* ignore malformed frames */
      }
    };

    ws.onclose = () => {
      setConnected(false);
      wsRef.current = null;
      reconnectTimer.current = setTimeout(connect, WS_RECONNECT_MS);
    };

    ws.onerror = () => ws.close();
  }, [onTelemetry]);

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
// Simulation logic — only runs when the hardware bridge is NOT connected
// ---------------------------------------------------------------------------
function useSimulation({
  hwConnected,
  systemActive,
  rawBoost,
  minBoost,
  maxBoost,
  triggerMode,
  manualDuty,
  startInjectionAt,
  fullInjectionAt,
  curve,
  setRawBoost,
  setPeakBoost,
  setBoostHistory,
  setDutyCycle,
  setStatus,
}) {
  useEffect(() => {
    if (hwConnected) return; // yield to real hardware data

    const interval = setInterval(() => {
      if (systemActive) {
        const noise = Math.random() * 4 - 2;
        const targetBoost = rawBoost < 15 ? rawBoost + 1.5 : maxBoost * 0.8;
        const nextBoost = Math.max(minBoost, Math.min(maxBoost + 5, targetBoost + noise));
        setRawBoost(nextBoost);
        setPeakBoost((prev) => Math.max(prev, nextBoost));
        setBoostHistory((prev) => [...prev.slice(1), nextBoost]);

        let calculatedDuty = 0;
        if (triggerMode === 'manual') {
          calculatedDuty = manualDuty;
          setStatus('Manual Mode');
        } else {
          const start = triggerMode === 'full_scale' ? minBoost : startInjectionAt;
          const end = triggerMode === 'full_scale' ? maxBoost : fullInjectionAt;
          if (nextBoost > start) {
            const range = end - start;
            let progress = Math.max(0, Math.min(1, (nextBoost - start) / range));
            if (curve === 'exponential') progress = Math.pow(progress, 2);
            calculatedDuty = progress * 100;
            setStatus(calculatedDuty > 95 ? 'Full Flow' : 'Injecting');
          } else {
            calculatedDuty = 0;
            setStatus('Monitoring');
          }
        }
        setDutyCycle(calculatedDuty);
      } else {
        const decayed = Math.max(minBoost, rawBoost - 2);
        setRawBoost(decayed);
        setBoostHistory((prev) => [...prev.slice(1), decayed]);
        setDutyCycle(0);
        setStatus('System Off');
      }
    }, 100);
    return () => clearInterval(interval);
  }, [
    hwConnected,
    systemActive,
    rawBoost,
    startInjectionAt,
    fullInjectionAt,
    maxBoost,
    triggerMode,
    manualDuty,
    minBoost,
    curve,
    setRawBoost,
    setPeakBoost,
    setBoostHistory,
    setDutyCycle,
    setStatus,
  ]);
}

// ---------------------------------------------------------------------------
// Main Application
// ---------------------------------------------------------------------------
const App = () => {
  // Navigation State
  const [activeTab, setActiveTab] = useState('dash');

  // Settings State (Internal state is ALWAYS PSI Gauge: 0 = Atmosphere)
  const [units, setUnits] = useState('psi_inhg'); // 'psi', 'psi_inhg', 'bar', 'kpa'
  const [pressureRef, setPressureRef] = useState('gauge'); // 'gauge', 'abs'

  // Default to ~30inHg vacuum (-14.7 PSIg) and 20 PSI max
  const [minBoost, setMinBoost] = useState(DEFAULT_MIN_BOOST_PSI);
  const [maxBoost, setMaxBoost] = useState(20);

  const [triggerMode, setTriggerMode] = useState('thresholds');
  const [curve, setCurve] = useState('linear'); // 'linear' or 'exponential'
  const [startInjectionAt, setStartInjectionAt] = useState(5);
  const [fullInjectionAt, setFullInjectionAt] = useState(25);
  const [manualDuty, setManualDuty] = useState(0);

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
  const [hwConnected, setHwConnected] = useState(false);

  // --- UNIT CONVERSION LOGIC ---
  const PSI_TO_BAR = 0.0689476;
  const PSI_TO_KPA = 6.89476;
  const PSI_TO_INHG = 2.03602;
  const ATM_PSI = 14.7;

  const formatBoost = (psiGauge) => {
    const isAbs = pressureRef === 'abs' && units !== 'psi_inhg';
    const displayValue = isAbs ? psiGauge + ATM_PSI : psiGauge;
    switch (units) {
      case 'bar': return (displayValue * PSI_TO_BAR).toFixed(2);
      case 'kpa': return (displayValue * PSI_TO_KPA).toFixed(1);
      case 'psi_inhg':
        if (psiGauge <= -0.1) return `${(psiGauge * -PSI_TO_INHG).toFixed(0)} inHg`;
        return `${psiGauge.toFixed(1)} PSI`;
      default: return displayValue.toFixed(1);
    }
  };

  const getUnitLabel = () => {
    if (units === 'psi_inhg') return 'PSI/inHg';
    return units.toUpperCase();
  };

  const toInputVal = (psiGauge, isMinField) => {
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
    const v = parseFloat(val);
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
    if (units === 'bar') return '0.07';
    if (units === 'kpa') return '6.9';
    return '1';
  };

  const handleAdjust = (isMin, direction) => {
    const step = parseFloat(getStepValue());
    let currentUIVal = parseFloat(toInputVal(isMin ? minBoost : maxBoost, isMin));
    let newUIVal = currentUIVal + (direction === 'up' ? step : -step);
    newUIVal = parseFloat(newUIVal.toFixed(2));
    let newInternalVal = fromInputVal(newUIVal.toString(), isMin);
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

  const { connected: bridgeConnected, send: wsSend } = useSerialBridge({
    onTelemetry: handleTelemetry,
  });

  // Track bridge connected state so simulation can yield
  useEffect(() => {
    setHwConnected(bridgeConnected);
  }, [bridgeConnected]);

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
    });
  }, [hwConnected, wsSend, systemActive, triggerMode, startInjectionAt, fullInjectionAt, manualDuty, curve]);

  // ---------------------------------------------------------------------------
  // Simulation loop — only runs when the hardware bridge is NOT connected
  // ---------------------------------------------------------------------------
  useSimulation({
    hwConnected,
    systemActive,
    rawBoost,
    minBoost,
    maxBoost,
    triggerMode,
    manualDuty,
    startInjectionAt,
    fullInjectionAt,
    curve,
    setRawBoost,
    setPeakBoost,
    setBoostHistory,
    setDutyCycle,
    setStatus,
  });

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

  return (
    <div className="min-h-screen bg-slate-950 text-slate-100 font-sans p-4 flex flex-col gap-4 select-none overflow-hidden relative">

      <div className="absolute -top-24 -left-24 w-64 h-64 bg-lime-500/10 rounded-full blur-[120px] pointer-events-none" />
      <div className="absolute -bottom-24 -right-24 w-64 h-64 bg-cyan-500/10 rounded-full blur-[120px] pointer-events-none" />

      <div
        className="flex-1 flex transition-transform duration-500 ease-out h-full"
        style={{ transform: activeTab === 'dash' ? 'translateX(0%)' : 'translateX(-100%)' }}
      >

        {/* ================================================================
            DASHBOARD PAGE
            ================================================================ */}
        <div className="min-w-full flex flex-col gap-4">
          {/* Header */}
          <div className="flex justify-between items-center bg-slate-900/80 backdrop-blur-md p-3 rounded-2xl border border-slate-800 shadow-xl">
            <div className="flex items-center gap-4">
              <div className="w-12 h-12 bg-black rounded-lg border border-slate-700 flex items-center justify-center p-1 shadow-[0_0_15px_rgba(163,230,53,0.15)] overflow-hidden">
                <img
                  src="/logo.svg"
                  alt="Logo"
                  className="w-full h-full object-contain"
                  onError={(e) => { e.currentTarget.style.display = 'none'; }}
                />
              </div>
              <div className="flex flex-col justify-center">
                <h1 className="text-xl font-black tracking-tighter leading-none italic">
                  <span className="text-white">MILD</span>
                  <span className="mx-1.5"> </span>
                  <span className="text-lime-400">MODZ</span>
                </h1>
                <p className="text-[10px] uppercase tracking-widest text-slate-500 font-bold mt-1">
                  <span className="text-lime-700 mr-1.5">NOTHING MILD</span>
                  <span>·</span>
                  <span className="ml-1.5">{status}</span>
                </p>
              </div>
            </div>

            <div className="flex gap-3 items-center">
              {/* Hardware connection indicator */}
              <div
                title={hwConnected ? 'ESP32 connected via USB' : 'Simulation mode — no ESP32 detected'}
                className={`flex items-center gap-1.5 px-2 py-1 rounded-lg border text-[9px] font-bold uppercase tracking-wider ${hwConnected ? 'bg-lime-500/10 border-lime-500/30 text-lime-400' : 'bg-slate-800/50 border-slate-700 text-slate-600'}`}
              >
                {hwConnected ? <Wifi size={10} /> : <WifiOff size={10} />}
                <span className="hidden md:inline">{hwConnected ? 'HW' : 'SIM'}</span>
              </div>

              <button
                onClick={handlePrime}
                disabled={isPriming || !systemActive}
                className={`flex items-center gap-2 px-3 py-2 rounded-xl border transition-all ${isPriming ? 'bg-amber-500/20 border-amber-500 text-amber-500' : 'bg-slate-800 border-slate-700 active:scale-95 disabled:opacity-30'}`}
              >
                <RefreshCw size={14} className={isPriming ? 'animate-spin' : ''} />
                <span className="text-xs font-bold uppercase hidden md:inline">Purge</span>
              </button>

              <button
                onClick={() => setSystemActive(!systemActive)}
                className={`flex items-center gap-2 px-5 py-2 rounded-xl font-bold uppercase tracking-wider transition-all shadow-lg text-sm ${systemActive ? 'bg-red-600 shadow-red-900/20' : 'bg-lime-600 shadow-lime-900/20'}`}
              >
                <Power size={16} />
                {systemActive ? 'Kill' : 'Arm'}
              </button>

              <button
                onClick={() => setActiveTab('settings')}
                className="p-2 rounded-xl bg-slate-800 border border-slate-700 hover:bg-slate-700 transition-colors"
              >
                <ChevronRight size={24} className="text-slate-400" />
              </button>
            </div>
          </div>

          {/* Main Grid */}
          <div className="grid grid-cols-12 gap-4 flex-1">
            {/* Boost Gauge */}
            <div className="col-span-12 md:col-span-7 bg-slate-900/50 rounded-3xl border border-slate-800 p-6 flex flex-col justify-between relative overflow-hidden group">

              {/* Background Radial Gauge */}
              <div className="absolute -right-8 -top-8 w-72 h-72 pointer-events-none opacity-40">
                <svg viewBox="0 0 240 240" className="w-full h-full" style={{ transform: 'rotate(135deg)' }}>
                  <circle
                    cx="120" cy="120" r="100"
                    fill="none" stroke="currentColor" strokeWidth="24"
                    strokeLinecap="round" className="text-slate-800"
                    strokeDasharray="471.24 628.32"
                  />
                  <circle
                    cx="120" cy="120" r="100"
                    fill="none" stroke="currentColor" strokeWidth="24"
                    strokeLinecap="round" className="text-lime-500 transition-all duration-100 ease-linear"
                    strokeDasharray={`${(Math.max(0, Math.min(100, ((rawBoost - minBoost) / (maxBoost - minBoost)) * 100)) / 100) * 471.24} 628.32`}
                  />
                </svg>
              </div>

              <div className="relative z-10 flex-1 flex flex-col">
                <div className="flex items-center gap-2">
                  <span className="text-xs font-bold text-slate-500 uppercase tracking-widest">Manifold Pressure</span>
                  {triggerMode === 'full_scale' && (
                    <span className="text-[8px] bg-lime-500/20 text-lime-400 px-2 py-0.5 rounded border border-lime-500/30">FULL SCALE</span>
                  )}
                </div>
                <div className="flex flex-col mt-2">
                  <span className={`text-7xl md:text-8xl font-black tracking-tighter tabular-nums drop-shadow-lg leading-none transition-colors duration-300 ${isOutOfBounds ? 'text-red-500' : 'text-white'}`}>
                    {formatBoost(rawBoost)}
                  </span>
                  <span className={`text-xl md:text-2xl font-bold drop-shadow-md mt-1 transition-colors duration-300 ${isOutOfBounds ? 'text-red-500' : 'text-lime-400'}`}>
                    {getUnitLabel()}
                  </span>
                  <span className={`text-xs font-bold uppercase tracking-widest mt-0.5 transition-colors duration-300 ${isOutOfBounds ? 'text-red-500' : 'text-slate-500'}`}>
                    {pressureRef === 'abs' && units !== 'psi_inhg' ? 'ABSOLUTE' : 'GAUGE'}
                  </span>
                </div>

                {/* Telemetry Sparkline */}
                <div className="flex-1 w-full mt-6 flex flex-col justify-end relative min-h-[80px]">
                  <div className="absolute top-0 right-0 text-right z-20">
                    <div className="flex items-center justify-end gap-2 mb-1">
                      <span className="text-[10px] text-slate-500 font-bold uppercase tracking-widest">Session Peak</span>
                      <button
                        onClick={() => setPeakBoost(minBoost)}
                        className="text-[8px] bg-slate-800/80 text-slate-400 px-1.5 py-0.5 rounded border border-slate-700 hover:bg-slate-300 transition-colors cursor-pointer"
                      >
                        RESET
                      </button>
                    </div>
                    <div className="text-xl md:text-2xl font-black text-slate-300 tabular-nums leading-none">
                      {formatBoost(peakBoost)}
                    </div>
                  </div>

                  <div className="w-full h-20 md:h-24 relative z-10 opacity-70">
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
              <div className="w-full bg-slate-800 h-6 rounded-full mt-4 overflow-hidden border border-slate-700 p-1 relative z-10 flex-shrink-0">
                <div
                  className="h-full bg-gradient-to-r from-lime-600 to-emerald-400 rounded-full transition-all duration-100"
                  style={{ width: `${Math.max(0, Math.min(100, ((rawBoost - minBoost) / (maxBoost - minBoost)) * 100))}%` }}
                />
              </div>
            </div>

            <div className="col-span-12 md:col-span-5 flex flex-col gap-4">
              {/* Pump Flow */}
              <div className="flex-1 bg-slate-900/50 rounded-3xl border border-slate-800 p-6 flex items-center justify-between">
                <div className="flex flex-col">
                  <span className="text-xs font-bold text-slate-500 uppercase tracking-widest">Pump Flow</span>
                  <span className={`text-5xl font-black transition-colors duration-300 ${Math.round(dutyCycle) >= 100 ? 'text-red-500 drop-shadow-lg' : 'text-white'}`}>
                    {Math.round(dutyCycle)}%
                  </span>
                  {triggerMode === 'manual' && (
                    <span className="text-[10px] text-amber-500 font-bold uppercase mt-1">MANUAL OVERRIDE</span>
                  )}
                </div>

                {/* Injector SVG */}
                <div className="h-28 w-20 flex flex-col items-center justify-start relative mr-2">
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

              {/* Map Curve Display */}
              <div className="bg-slate-900/50 rounded-2xl border border-slate-800 p-4 flex items-center justify-between shadow-inner h-16 flex-shrink-0">
                <span className="text-[10px] font-bold text-slate-500 uppercase tracking-widest">Map Curve</span>
                <div className="flex items-center gap-3">
                  <span className="text-sm font-black text-lime-400 uppercase tracking-widest">{curve}</span>
                  <div className="w-8 h-6 flex items-center justify-center text-lime-400">
                    <svg width="32" height="20" viewBox="0 0 32 20" className="overflow-visible">
                      {curve === 'linear' ? (
                        <line x1="0" y1="20" x2="32" y2="0" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
                      ) : (
                        <path d="M0,20 Q24,20 32,0" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round" />
                      )}
                    </svg>
                  </div>
                </div>
              </div>

              {/* Tank Status */}
              <div className={`flex-1 rounded-3xl border p-6 flex items-center gap-4 transition-all ${tankIsLow ? 'bg-red-950/30 border-red-500/50 shadow-lg shadow-red-900/20' : 'bg-slate-900/50 border-slate-800'}`}>
                <div className={`p-3 rounded-2xl ${tankIsLow ? 'bg-red-500 text-white animate-pulse' : 'bg-slate-800 text-slate-500'}`}>
                  <Droplet size={32} />
                </div>
                <div className="flex flex-col">
                  <span className="text-xs font-bold text-slate-500 uppercase tracking-widest">Tank Status</span>
                  <span className={`text-2xl font-black ${tankIsLow ? 'text-red-500' : 'text-emerald-400'}`}>
                    {tankIsLow ? 'LOW FLUID' : 'LEVEL OK'}
                  </span>
                  {!hwConnected && (
                    <button
                      onClick={() => setTankIsLow(!tankIsLow)}
                      className="text-[8px] text-slate-600 uppercase mt-1 underline hover:text-slate-400"
                    >
                      Toggle Sensor (sim)
                    </button>
                  )}
                </div>
              </div>
            </div>
          </div>
        </div>

        {/* ================================================================
            SETTINGS PAGE
            ================================================================ */}
        <div className="min-w-full flex flex-col gap-4">
          <div className="flex justify-between items-center bg-slate-900/80 p-3 rounded-2xl border border-slate-800 shadow-lg">
            <div className="flex items-center gap-3">
              <button onClick={() => setActiveTab('dash')} className="p-2 bg-slate-800 rounded-xl hover:bg-slate-700 transition-colors">
                <ChevronLeft size={24} />
              </button>
              <div className="flex flex-col">
                <h2 className="text-xl font-black uppercase tracking-tight leading-none">System Configuration</h2>
                <span className="text-[10px] text-slate-400 font-bold uppercase tracking-widest mt-1">
                  HW REV: <span className="text-lime-400">{HW_REVISION}</span>
                </span>
              </div>
            </div>
            <button
              onClick={() => setActiveTab('dash')}
              className="flex items-center gap-2 px-4 py-2 bg-lime-600 rounded-xl font-bold text-sm shadow-lg shadow-lime-900/20 active:scale-95"
            >
              <Save size={16} /> <span className="hidden md:inline">SAVE & EXIT</span>
            </button>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-2 gap-4 flex-1 overflow-y-auto pr-2 custom-scrollbar">
            {/* Column 1: Display & Units */}
            <div className="bg-slate-900/50 rounded-3xl border border-slate-800 p-6 flex flex-col gap-6 h-fit">
              <div>
                <label className="text-xs font-bold text-slate-500 uppercase tracking-widest block mb-3">Pressure Units</label>
                <div className="grid grid-cols-4 gap-2 mb-3">
                  {['psi', 'psi_inhg', 'bar', 'kpa'].map((u) => (
                    <button
                      key={u}
                      onClick={() => {
                        setUnits(u);
                        if (u === 'psi_inhg') setPressureRef('gauge');
                      }}
                      className={`py-2 rounded-xl text-xs font-bold uppercase border transition-all ${units === u ? 'bg-lime-500 border-lime-400 text-black shadow-lg shadow-lime-500/20' : 'bg-slate-800 border-slate-700 text-slate-400 hover:border-slate-500'}`}
                    >
                      {u.replace('_', '+')}
                    </button>
                  ))}
                </div>

                {units !== 'psi_inhg' && (
                  <div className="flex gap-2 p-1 bg-black rounded-xl border border-slate-800 animate-in fade-in duration-300">
                    <button
                      onClick={() => setPressureRef('gauge')}
                      className={`flex-1 py-1.5 rounded-lg text-[10px] font-bold uppercase transition-all ${pressureRef === 'gauge' ? 'bg-slate-800 text-white' : 'text-slate-500'}`}
                    >
                      Gauge (PSIg)
                    </button>
                    <button
                      onClick={() => setPressureRef('abs')}
                      className={`flex-1 py-1.5 rounded-lg text-[10px] font-bold uppercase transition-all ${pressureRef === 'abs' ? 'bg-slate-800 text-white' : 'text-slate-500'}`}
                    >
                      Absolute (PSIa)
                    </button>
                  </div>
                )}
              </div>

              <div>
                <label className="text-xs font-bold text-slate-500 uppercase tracking-widest block mb-3">Gauge Scaling Limits</label>
                <div className="flex flex-col gap-4">
                  {/* MIN INPUT */}
                  <div className="flex-1">
                    <span className="text-[10px] text-slate-500 block font-bold mb-1">MIN ({getInputUnitLabel(true)})</span>
                    <div className="flex bg-slate-800 border border-slate-700 rounded-lg overflow-hidden focus-within:border-lime-500 transition-colors">
                      <button
                        onClick={() => handleAdjust(true, 'down')}
                        className="px-4 py-2 bg-slate-900/50 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors active:scale-95 flex items-center justify-center border-r border-slate-700"
                      >
                        <Minus size={18} />
                      </button>
                      <input
                        type="number"
                        value={toInputVal(minBoost, true)}
                        onChange={(e) => {
                          let val = fromInputVal(e.target.value, true);
                          if (val < -ATM_PSI) val = -ATM_PSI;
                          setMinBoost(val);
                          if (startInjectionAt < val) setStartInjectionAt(val);
                          if (fullInjectionAt < val) setFullInjectionAt(val + 1);
                        }}
                        className="w-full bg-transparent text-center px-2 py-2 text-white font-bold outline-none hide-arrows"
                      />
                      <button
                        onClick={() => handleAdjust(true, 'up')}
                        className="px-4 py-2 bg-slate-900/50 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors active:scale-95 flex items-center justify-center border-l border-slate-700"
                      >
                        <Plus size={18} />
                      </button>
                    </div>
                  </div>

                  {/* MAX INPUT */}
                  <div className="flex-1">
                    <span className="text-[10px] text-slate-500 block font-bold mb-1">MAX ({getInputUnitLabel(false)})</span>
                    <div className="flex bg-slate-800 border border-slate-700 rounded-lg overflow-hidden focus-within:border-lime-500 transition-colors">
                      <button
                        onClick={() => handleAdjust(false, 'down')}
                        className="px-4 py-2 bg-slate-900/50 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors active:scale-95 flex items-center justify-center border-r border-slate-700"
                      >
                        <Minus size={18} />
                      </button>
                      <input
                        type="number"
                        value={toInputVal(maxBoost, false)}
                        onChange={(e) => {
                          let val = fromInputVal(e.target.value, false);
                          if (val > 200) val = 200;
                          setMaxBoost(val);
                          if (fullInjectionAt > val) setFullInjectionAt(val);
                          if (startInjectionAt > val) setStartInjectionAt(val - 1);
                        }}
                        className="w-full bg-transparent text-center px-2 py-2 text-white font-bold outline-none hide-arrows"
                      />
                      <button
                        onClick={() => handleAdjust(false, 'up')}
                        className="px-4 py-2 bg-slate-900/50 hover:bg-slate-700 text-slate-400 hover:text-white transition-colors active:scale-95 flex items-center justify-center border-l border-slate-700"
                      >
                        <Plus size={18} />
                      </button>
                    </div>
                  </div>
                </div>

                {maxBoost > 30 && (
                  <div className="mt-4 p-2.5 bg-amber-500/10 border border-amber-500/30 rounded-lg flex items-center gap-2 text-amber-500 animate-in fade-in zoom-in-95 duration-300">
                    <AlertTriangle size={14} className="flex-shrink-0" />
                    <span className="text-[10px] font-bold uppercase leading-tight">External MAP Sensor must be connected</span>
                  </div>
                )}
              </div>
            </div>

            {/* Column 2: Trigger Logic */}
            <div className="bg-slate-900/50 rounded-3xl border border-slate-800 p-6 flex flex-col gap-6 h-fit">
              {/* Map Curve Setting */}
              <div>
                <label className="text-xs font-bold text-slate-500 uppercase tracking-widest block mb-3">Injection Map Curve</label>
                <div className="flex gap-2 p-1 bg-black rounded-xl border border-slate-800">
                  <button
                    onClick={() => setCurve('linear')}
                    className={`flex-1 py-1.5 rounded-lg text-[10px] font-bold uppercase transition-all flex items-center justify-center gap-2 ${curve === 'linear' ? 'bg-slate-800 text-lime-400' : 'text-slate-500 hover:text-slate-400'}`}
                  >
                    <TrendingUp size={14} /> Linear
                  </button>
                  <button
                    onClick={() => setCurve('exponential')}
                    className={`flex-1 py-1.5 rounded-lg text-[10px] font-bold uppercase transition-all flex items-center justify-center gap-2 ${curve === 'exponential' ? 'bg-slate-800 text-lime-400' : 'text-slate-500 hover:text-slate-400'}`}
                  >
                    <Zap size={14} /> Exponential
                  </button>
                </div>
              </div>

              <div className="border-t border-slate-800 my-1"></div>

              <label className="text-xs font-bold text-slate-500 uppercase tracking-widest block">Injection Mapping Mode</label>

              <div className="flex gap-2 p-1 bg-black rounded-2xl border border-slate-800">
                <button
                  onClick={() => setTriggerMode('thresholds')}
                  className={`flex-1 py-2 rounded-xl text-[10px] font-black uppercase transition-all flex items-center justify-center gap-2 ${triggerMode === 'thresholds' ? 'bg-slate-800 text-lime-400 shadow-inner' : 'text-slate-500'}`}
                >
                  <Zap size={12} /> Thresholds
                </button>
                <button
                  onClick={() => setTriggerMode('full_scale')}
                  className={`flex-1 py-2 rounded-xl text-[10px] font-black uppercase transition-all flex items-center justify-center gap-2 ${triggerMode === 'full_scale' ? 'bg-slate-800 text-lime-400 shadow-inner' : 'text-slate-500'}`}
                >
                  <Gauge size={12} /> Full Scale
                </button>
                <button
                  onClick={() => setTriggerMode('manual')}
                  className={`flex-1 py-2 rounded-xl text-[10px] font-black uppercase transition-all flex items-center justify-center gap-2 ${triggerMode === 'manual' ? 'bg-slate-800 text-amber-500 shadow-inner' : 'text-slate-500'}`}
                >
                  <Sliders size={12} /> Manual
                </button>
              </div>

              {/* Conditional Inputs */}
              <div className="min-h-[140px] flex flex-col justify-center gap-4">
                {triggerMode === 'thresholds' && (
                  <div className="space-y-4 animate-in fade-in slide-in-from-top-2 duration-300">
                    <div>
                      <div className="flex justify-between text-[10px] font-bold uppercase mb-1">
                        <span className="text-slate-400">Injection Start:</span>
                        <span className="text-lime-400">{formatBoost(startInjectionAt)} {getUnitLabel()}</span>
                      </div>
                      <input type="range" min={minBoost} max={fullInjectionAt - 0.1} step="0.1" value={startInjectionAt} onChange={(e) => setStartInjectionAt(Number(e.target.value))} className="w-full accent-lime-500" />
                    </div>
                    <div>
                      <div className="flex justify-between text-[10px] font-bold uppercase mb-1">
                        <span className="text-slate-400">100% Flow:</span>
                        <span className="text-cyan-400">{formatBoost(fullInjectionAt)} {getUnitLabel()}</span>
                      </div>
                      <input type="range" min={startInjectionAt + 0.1} max={maxBoost} step="0.1" value={fullInjectionAt} onChange={(e) => setFullInjectionAt(Number(e.target.value))} className="w-full accent-cyan-500" />
                    </div>
                  </div>
                )}

                {triggerMode === 'full_scale' && (
                  <div className="bg-slate-800/40 p-4 rounded-2xl border border-slate-700 text-center animate-in zoom-in-95 duration-300">
                    <p className="text-[11px] text-slate-300 font-bold uppercase leading-tight">
                      Pump will ramp linearly from <span className="text-lime-400">{formatBoost(minBoost)} {getUnitLabel()}</span> to <span className="text-cyan-400">{formatBoost(maxBoost)} {getUnitLabel()}</span>.
                    </p>
                    <p className="text-[9px] text-slate-500 mt-2 italic">Based on your Gauge Scaling settings.</p>
                  </div>
                )}

                {triggerMode === 'manual' && (
                  <div className="space-y-4 animate-in fade-in slide-in-from-bottom-2 duration-300">
                    <div>
                      <div className="flex justify-between text-[10px] font-bold uppercase mb-1">
                        <span className="text-amber-500 font-black">Manual Duty Cycle:</span>
                        <span className="text-white text-lg">{manualDuty}%</span>
                      </div>
                      <input type="range" min="0" max="100" value={manualDuty} onChange={(e) => setManualDuty(Number(e.target.value))} className="w-full accent-amber-500" />
                    </div>
                    <p className="text-[8px] text-red-400 font-bold uppercase text-center bg-red-950/20 py-1 rounded">
                      Caution: Pump will run at fixed speed regardless of pressure.
                    </p>
                  </div>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Nav Dots */}
      <div className="flex justify-center gap-2 pb-2">
        <div className={`h-1.5 rounded-full transition-all duration-300 ${activeTab === 'dash' ? 'w-8 bg-lime-500 shadow-[0_0_10px_rgba(132,204,22,0.5)]' : 'w-2 bg-slate-700'}`} />
        <div className={`h-1.5 rounded-full transition-all duration-300 ${activeTab === 'settings' ? 'w-8 bg-lime-500 shadow-[0_0_10px_rgba(132,204,22,0.5)]' : 'w-2 bg-slate-700'}`} />
      </div>

      <style dangerouslySetInnerHTML={{ __html: `
        @keyframes spray-flow {
          from { stroke-dashoffset: 20; }
          to { stroke-dashoffset: 0; }
        }
        .animate-spray { animation: spray-flow 0.3s linear infinite; }
        .animate-spray-fast { animation: spray-flow 0.2s linear infinite; }
        .animate-spray-slow { animation: spray-flow 0.4s linear infinite; }
        .hide-arrows::-webkit-inner-spin-button,
        .hide-arrows::-webkit-outer-spin-button { -webkit-appearance: none; margin: 0; }
        .hide-arrows { -moz-appearance: textfield; }
        input[type=range] { -webkit-appearance: none; background: transparent; }
        input[type=range]::-webkit-slider-runnable-track { width: 100%; height: 6px; background: #0f172a; border-radius: 3px; }
        input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; height: 18px; width: 18px; border-radius: 50%; background: currentColor; margin-top: -6px; box-shadow: 0 0 15px rgba(0,0,0,0.5); border: 2px solid #000; }
        .custom-scrollbar::-webkit-scrollbar { width: 4px; }
        .custom-scrollbar::-webkit-scrollbar-track { background: transparent; }
        .custom-scrollbar::-webkit-scrollbar-thumb { background: #334155; border-radius: 10px; }
      `}} />
    </div>
  );
};

export default App;
