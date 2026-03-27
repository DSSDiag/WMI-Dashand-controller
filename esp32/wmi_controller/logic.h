#pragma once

#include <stdint.h>
#include "config.h"

// ── Settings (updated from Pi) ────────────────────────────────────────────────
struct Settings {
  uint8_t  triggerMode  = DEFAULT_TRIGGER_MODE;
  float    startKpa     = DEFAULT_START_KPA;
  float    fullKpa      = DEFAULT_FULL_KPA;
  uint8_t  manualDuty   = DEFAULT_MANUAL_DUTY;
  uint8_t  curve        = DEFAULT_CURVE;
  bool     armed        = DEFAULT_ARMED;
};

// ── Duty cycle calculation ────────────────────────────────────────────────────
uint8_t calcDuty(float kpa, bool tankLow, const Settings& settings);
