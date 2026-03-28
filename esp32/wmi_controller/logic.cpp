#include "logic.h"

// Provide a generic constrain function if compiling outside Arduino
#ifndef constrain
#define constrain(amt,low,high) ((amt)<(low)?(low):((amt)>(high)?(high):(amt)))
#endif

uint8_t calcDuty(float kpa, bool tankLow, const Settings& settings) {
  if (!settings.armed || tankLow) return 0;

  switch (settings.triggerMode) {
    case 2: // Manual
      return settings.manualDuty;

    case 1: // Full scale — ramp across entire sensor range
      {
        float range = MAP_KPA_MAX - MAP_KPA_MIN;
        float progress = constrain((kpa - MAP_KPA_MIN) / range, 0.0f, 1.0f);
        if (settings.curve == 1) progress = progress * progress;
        return (uint8_t)(progress * 100.0f);
      }

    default: // Thresholds
      {
        if (kpa <= settings.startKpa) return 0;
        float range = settings.fullKpa - settings.startKpa;
        if (range <= 0.0f) return (kpa > settings.startKpa) ? 100 : 0;
        float progress = constrain((kpa - settings.startKpa) / range, 0.0f, 1.0f);
        if (settings.curve == 1) progress = progress * progress;
        return (uint8_t)(progress * 100.0f);
      }
  }
}
