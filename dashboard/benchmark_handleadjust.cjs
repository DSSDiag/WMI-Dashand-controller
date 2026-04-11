const { performance } = require('perf_hooks');

// Mock state
let units = 'psi';
let minBoost = -14.73;
let maxBoost = 20;
let pressureRef = 'gauge';
const ATM_PSI = 14.7;
const PSI_TO_BAR = 0.0689476;
const PSI_TO_KPA = 6.89476;
const PSI_TO_INHG = 2.03602;

const getStepValueOld = () => {
  if (units === 'bar') return '0.07';
  if (units === 'kpa') return '6.9';
  return '1';
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

const fromInputValOld = (val, isMinField) => {
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

const fromInputValNew = (val, isMinField) => {
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

const getStepValueNew = () => {
  if (units === 'bar') return 0.07;
  if (units === 'kpa') return 6.9;
  return 1;
};

const iterations = 100_000;

function benchOld() {
    let start = performance.now();
    for (let i = 0; i < iterations; i++) {
        const isMin = (i % 2 === 0);
        const direction = (i % 3 === 0) ? 'up' : 'down';

        const step = parseFloat(getStepValueOld());
        let currentUIVal = parseFloat(toInputVal(isMin ? minBoost : maxBoost, isMin));
        let newUIVal = currentUIVal + (direction === 'up' ? step : -step);
        newUIVal = parseFloat(newUIVal.toFixed(2));
        let newInternalVal = fromInputValOld(newUIVal.toString(), isMin);
    }
    let end = performance.now();
    console.log(`Old logic: ${end - start} ms`);
}

function benchNew() {
    let start = performance.now();
    for (let i = 0; i < iterations; i++) {
        const isMin = (i % 2 === 0);
        const direction = (i % 3 === 0) ? 'up' : 'down';

        const step = getStepValueNew();
        let currentUIVal = parseFloat(toInputVal(isMin ? minBoost : maxBoost, isMin));
        let newUIVal = currentUIVal + (direction === 'up' ? step : -step);
        newUIVal = Math.round(newUIVal * 100) / 100;
        let newInternalVal = fromInputValNew(newUIVal, isMin);
    }
    let end = performance.now();
    console.log(`New logic: ${end - start} ms`);
}

benchOld();
benchNew();
