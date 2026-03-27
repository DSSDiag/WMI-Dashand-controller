#pragma once

#include "config.h"

// ── Duty cycle calculation ────────────────────────────────────────────────────
uint8_t calcDuty(float kpa, bool tankLow, const Settings& settings);
