export const PSI_TO_BAR = 0.0689476;
export const PSI_TO_KPA = 6.89476;
export const PSI_TO_INHG = 2.03602;
export const ATM_PSI = 14.7;
export const COMPACT_DISPLAY_PROFILES = new Set([
  '52pi-k0403',
  'generic-ili9486-hat',
  'waveshare-35g',
]);
export const SUPPORTED_DISPLAY_PROFILES = new Set([
  'dsi5',
  '52pi-k0403',
  'generic-ili9486-hat',
  'waveshare-35g',
  'preconfigured',
]);

export const normalizeDisplayProfile = (profile) => (
  typeof profile === 'string' && SUPPORTED_DISPLAY_PROFILES.has(profile)
    ? profile
    : 'default'
);

export const isCompactDisplayProfile = (profile) => COMPACT_DISPLAY_PROFILES.has(profile);

export const formatBoost = (psiGauge, units, pressureRef) => {
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
