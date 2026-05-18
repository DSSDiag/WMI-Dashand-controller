/**
 * config.h — WMI Sensor Module
 * ============================
 * Edit this file to match your wiring and sensor.
 *
 * The Pi-facing software refers to the ESP board as the "sensor module".
 * This file provides target-aware defaults for:
 *   - ESP32
 *   - ESP32-C3 (including SuperMini / Mini-style boards)
 *   - ESP32-S3
 */

#pragma once

#include <stdint.h>

// ── Serial communication (USB to Raspberry Pi) ────────────────────────────────
#define SERIAL_BAUD         115200
// Watchdog: if no settings received from Pi in this many ms, use safe defaults
#define SETTINGS_WATCHDOG_MS  10000UL

// ── Sensor module target detection ────────────────────────────────────────────
#if defined(CONFIG_IDF_TARGET_ESP32C3)
  #define SENSOR_MODULE_BOARD_KEY   "esp32-c3"
  #define SENSOR_MODULE_BOARD_NAME  "ESP32-C3"
  #define SENSOR_MODULE_LED_PIN_DEFAULT 8
#elif defined(CONFIG_IDF_TARGET_ESP32S3)
  #define SENSOR_MODULE_BOARD_KEY   "esp32-s3"
  #define SENSOR_MODULE_BOARD_NAME  "ESP32-S3"
  #define SENSOR_MODULE_LED_PIN_DEFAULT 48
#elif defined(CONFIG_IDF_TARGET_ESP32)
  #define SENSOR_MODULE_BOARD_KEY   "esp32"
  #define SENSOR_MODULE_BOARD_NAME  "ESP32"
  #define SENSOR_MODULE_LED_PIN_DEFAULT 2
#else
  #define SENSOR_MODULE_BOARD_KEY   "esp32"
  #define SENSOR_MODULE_BOARD_NAME  "ESP32"
  #define SENSOR_MODULE_LED_PIN_DEFAULT 2
#endif

#define SENSOR_MODULE_LABEL SENSOR_MODULE_BOARD_NAME " Sensor Module"

// ── GPIO Pin Assignments ──────────────────────────────────────────────────────
// Override any of these in a board-specific header if your wiring differs.
// MAP / ECU analog signal input — the boxed module is intended for direct 0–5V
// analog sources. Do not exceed +5.0V on this input.
#ifndef PIN_MAP_SENSOR
  #define PIN_MAP_SENSOR      4
#endif
// Pump / solenoid relay output — drives a MOSFET gate or relay module
#ifndef PIN_PUMP_PWM
  #define PIN_PUMP_PWM        5
#endif
// Tank level sensor — active LOW (float switch pulls to GND when fluid is present)
#ifndef PIN_TANK_LEVEL
  #define PIN_TANK_LEVEL      6
#endif
// Optional armed LED indicator
#ifndef PIN_LED_ARMED
  #define PIN_LED_ARMED       SENSOR_MODULE_LED_PIN_DEFAULT
#endif

// ── MAP Sensor Parameters ──────────────────────────────────────────────────────
// Sensor: any automotive 1-bar or 2-bar MAP sensor (e.g. Bosch 0261230050,
//         GM 12569240, Honeywell ASDXRRX100PGAA5)
//
// Calibration formula:  kPa_abs = (Vout - V_at_0kPa) / (V_at_100kPa - V_at_0kPa) * 100
// Override these with measured values for your specific sensor if needed.
//
// The ESP ADC itself is 3.3V, so the boxed module should condition any external
// 0–5V signal down to the 0–3.3V ADC range before it reaches PIN_MAP_SENSOR.
#define MAP_VCC_MV          3300.0f   // ADC-side full scale after input conditioning
#define MAP_V_MIN_MV         165.0f   // ADC-side voltage at MAP_KPA_MIN
#define MAP_V_MAX_MV        2970.0f   // ADC-side voltage at MAP_KPA_MAX
#define MAP_KPA_MIN          10.0f    // Absolute pressure at MAP_V_MIN_MV
#define MAP_KPA_MAX         105.0f    // Absolute pressure at MAP_V_MAX_MV
#define MAP_ADC_SAMPLES        16     // Oversampling count for noise reduction

// ── Pump PWM Parameters ────────────────────────────────────────────────────────
#define PWM_FREQ_HZ         1000    // 1 kHz PWM for progressive pump control
#define PWM_RESOLUTION_BITS    8    // 8-bit = 0–255 range

// ── Physical Constants ─────────────────────────────────────────────────────────
#define ATM_KPA             101.325f  // Standard atmospheric pressure (kPa absolute)

// ── Safe Defaults (applied when no settings received) ─────────────────────────
#define DEFAULT_TRIGGER_MODE   0    // 0=thresholds, 1=full_scale, 2=manual
#define DEFAULT_START_KPA    137.9f // ~5 PSI boost above atmosphere
#define DEFAULT_FULL_KPA     240.2f // ~20 PSI boost above atmosphere
#define DEFAULT_MANUAL_DUTY    0
#define DEFAULT_CURVE          0    // 0=linear, 1=exponential
#define DEFAULT_ARMED          0    // system starts disarmed

// ── Settings (updated from Pi) ────────────────────────────────────────────────
struct Settings {
  uint8_t  triggerMode  = DEFAULT_TRIGGER_MODE;
  float    startKpa     = DEFAULT_START_KPA;
  float    fullKpa      = DEFAULT_FULL_KPA;
  uint8_t  manualDuty   = DEFAULT_MANUAL_DUTY;
  uint8_t  curve        = DEFAULT_CURVE;
  bool     armed        = DEFAULT_ARMED;
  float    mapVoltageMinMv = MAP_V_MIN_MV;
  float    mapVoltageMaxMv = MAP_V_MAX_MV;
  float    mapKpaMin       = MAP_KPA_MIN;
  float    mapKpaMax       = MAP_KPA_MAX;
};
