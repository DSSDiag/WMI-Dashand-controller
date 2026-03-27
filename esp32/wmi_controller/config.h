/**
 * config.h — WMI Controller (ESP32-S3)
 * =====================================
 * Edit this file to match your wiring and sensor.
 */

#pragma once

// ── Serial communication (USB to Raspberry Pi) ────────────────────────────────
#define SERIAL_BAUD         115200
// Watchdog: if no settings received from Pi in this many ms, use safe defaults
#define SETTINGS_WATCHDOG_MS  10000UL

// ── GPIO Pin Assignments ───────────────────────────────────────────────────────
// MAP sensor analog input — use a 10kΩ + 10kΩ voltage divider if sensor outputs 5V
#define PIN_MAP_SENSOR      4   // GPIO4 (ADC1_CH3 on ESP32-S3)
// Pump / solenoid relay output — drives a MOSFET gate or relay module
#define PIN_PUMP_PWM        5   // GPIO5  (LEDC capable)
// Tank level sensor — active LOW (float switch pulls to GND when fluid is present)
#define PIN_TANK_LEVEL      6   // GPIO6  (INPUT_PULLUP)
// Optional armed LED indicator
#define PIN_LED_ARMED       48  // ESP32-S3-DevKitC onboard LED (GPIO48)

// ── MAP Sensor Parameters ──────────────────────────────────────────────────────
// Sensor: any automotive 1-bar or 2-bar MAP sensor (e.g. Bosch 0261230050,
//         GM 12569240, Honeywell ASDXRRX100PGAA5)
//
// Calibration formula:  kPa_abs = (Vout - V_at_0kPa) / (V_at_100kPa - V_at_0kPa) * 100
// Override these with measured values for your specific sensor if needed.
//
// For a sensor running on 5V with a 1:2 voltage divider into the 3.3V ADC:
//   effective Vcc seen by formula = 3.3V
#define MAP_VCC_MV          3300.0f   // Millivolts at sensor Vcc as seen by ADC input
#define MAP_V_MIN_MV         165.0f   // Vout at ~10 kPa absolute (vacuum, engine off)
#define MAP_V_MAX_MV        2970.0f   // Vout at ~105 kPa absolute (WOT / max boost)
#define MAP_KPA_MIN          10.0f   // kPa absolute at MAP_V_MIN_MV
#define MAP_KPA_MAX         105.0f   // kPa absolute at MAP_V_MAX_MV  (adjust for 2-bar sensor)
#define MAP_ADC_SAMPLES        16   // Oversampling count for noise reduction

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
