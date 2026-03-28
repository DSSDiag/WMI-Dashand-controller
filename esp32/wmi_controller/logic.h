#pragma once

#ifndef ARDUINO
#include "mock_arduino.h"
#else
#include <Arduino.h>
#endif

#include <ArduinoJson.h>
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

// ── External variables referenced by parseIncoming ────────────────────────────
extern Settings settings;
extern unsigned long lastSettingsMs;
extern bool isPriming;
extern unsigned long primeEndMs;

// ── Parse incoming serial JSON from Pi ───────────────────────────────────────
inline void parseIncoming(const String& line) {
  StaticJsonDocument<256> doc;
  if (deserializeJson(doc, line.c_str()) != DeserializationError::Ok) return;

  const char* t = doc["t"];
  if (!t) return;

  if (strcmp(t, "s") == 0) {
    settings.triggerMode = doc["tm"]  | settings.triggerMode;
    settings.startKpa    = doc["sp"]  | settings.startKpa;
    settings.fullKpa     = doc["fp"]  | settings.fullKpa;
    settings.manualDuty  = doc["md"]  | settings.manualDuty;
    settings.curve       = doc["c"]   | settings.curve;
    settings.armed       = (doc["a"]  | (settings.armed ? 1 : 0)) != 0;
    lastSettingsMs       = millis();
  } else if (strcmp(t, "prime") == 0) {
    isPriming   = true;
    primeEndMs  = millis() + 2000;
  }
}
#include "config.h"

// ── Duty cycle calculation ────────────────────────────────────────────────────
uint8_t calcDuty(float kpa, bool tankLow, const Settings& settings);
