/**
 * config.h — WMI Sensor Module
 * ============================
 * Edit this file to match your wiring and sensor.
 *
 * The sensor module firmware is intended to build for:
 *   - ESP32
 *   - ESP32-C3 (including SuperMini-style boards)
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
  #define SENSOR_MODULE_BOARD_KEY "esp32-c3"
  #define SENSOR_MODULE_BOARD_NAME "ESP32-C3"
  #define SENSOR_MODULE_LED_PIN_DEFAULT 8
#elif defined(CONFIG_IDF_TARGET_ESP32S3)
  #define SENSOR_MODULE_BOARD_KEY "esp32-s3"
  #define SENSOR_MODULE_BOARD_NAME "ESP32-S3"
  #define SENSOR_MODULE_LED_PIN_DEFAULT 48
#elif defined(CONFIG_IDF_TARGET_ESP32)
  #define SENSOR_MODULE_BOARD_KEY "esp32"
  #define SENSOR_MODULE_BOARD_NAME "ESP32"
  #define SENSOR_MODULE_LED_PIN_DEFAULT 2
#else
  #define SENSOR_MODULE_BOARD_KEY "esp32"
  #define SENSOR_MODULE_BOARD_NAME "ESP32"
  #define SENSOR_MODULE_LED_PIN_DEFAULT 2
#endif

#define SENSOR_MODULE_LABEL SENSOR_MODULE_BOARD_NAME " Sensor Module"

// ── GPIO Pin Assignments ──────────────────────────────────────────────────────
// The boxed module should accept a conditioned 0–5V MAP sensor or ECU analog
// output at its external input, while the ESP32 ADC itself remains 0–3.3V.
#ifndef PIN_MAP_SENSOR
  #define PIN_MAP_SENSOR      4
#endif
#ifndef PIN_PUMP_PWM
  #define PIN_PUMP_PWM        5
#endif
#ifndef PIN_TANK_LEVEL
  #define PIN_TANK_LEVEL      6
#endif
#ifndef PIN_LED_ARMED
  #define PIN_LED_ARMED       SENSOR_MODULE_LED_PIN_DEFAULT
#endif

// ── MAP Sensor Parameters ─────────────────────────────────────────────────────
// These remain the default calibration baked into the sensor module firmware.
// The Raspberry Pi dashboard can override calibration at runtime when that path
// is enabled, but these values provide safe baseline behaviour.
#define MAP_VCC_MV          3300.0f
#define MAP_V_MIN_MV         165.0f
#define MAP_V_MAX_MV        2970.0f
#define MAP_KPA_MIN          10.0f
#define MAP_KPA_MAX         105.0f
#define MAP_ADC_SAMPLES        16

// ── Pump PWM Parameters ───────────────────────────────────────────────────────
#define PWM_FREQ_HZ         1000
#define PWM_RESOLUTION_BITS    8

// ── Physical Constants ────────────────────────────────────────────────────────
#define ATM_KPA             101.325f

// ── Safe Defaults (applied when no settings received) ────────────────────────
#define DEFAULT_TRIGGER_MODE   0
#define DEFAULT_START_KPA    137.9f
#define DEFAULT_FULL_KPA     240.2f
#define DEFAULT_MANUAL_DUTY    0
#define DEFAULT_CURVE          0
#define DEFAULT_ARMED          0

// ── Settings (updated from Pi) ────────────────────────────────────────────────
struct Settings {
  uint8_t  triggerMode  = DEFAULT_TRIGGER_MODE;
  float    startKpa     = DEFAULT_START_KPA;
  float    fullKpa      = DEFAULT_FULL_KPA;
  uint8_t  manualDuty   = DEFAULT_MANUAL_DUTY;
  uint8_t  curve        = DEFAULT_CURVE;
  bool     armed        = DEFAULT_ARMED;
};
