/**
 * wmi_controller.ino — Water/Methanol Injection Controller
 * ==========================================================
 * ESP32-S3 firmware that:
 *   • Reads manifold absolute pressure from an automotive MAP sensor
 *   • Calculates pump duty cycle (linear or exponential curve)
 *   • Controls a PWM pump/solenoid relay output
 *   • Communicates with the Raspberry Pi dashboard via USB serial (JSON)
 *
 * Hardware requirements:
 *   - ESP32-S3 development board
 *   - Automotive MAP sensor (1-bar or 2-bar, see config.h)
 *   - MOSFET or relay module on PIN_PUMP_PWM
 *   - Tank level float switch on PIN_TANK_LEVEL
 *
 * Library dependency (install via Arduino IDE Library Manager):
 *   - ArduinoJson  ≥ 7.x  (Benoit Blanchon)
 *
 * Serial protocol:
 *   ESP32 → Pi  (100 ms interval):
 *     {"t":"d","p":120.5,"d":75,"l":0}
 *       p = kPa absolute, d = duty 0–100, l = 1 if tank low
 *
 *   Pi → ESP32  (on settings change):
 *     {"t":"s","tm":0,"sp":137.9,"fp":275.8,"md":0,"c":0,"a":1}
 *       tm = trigger mode, sp/fp = start/full kPa abs,
 *       md = manual duty, c = curve, a = armed
 *
 *   Pi → ESP32  (on purge button):
 *     {"t":"prime"}   → runs pump at 100% for 2 seconds
 */

#include <Arduino.h>
#include <ArduinoJson.h>
#include "config.h"
#include "logic.h"

// ── Variables declared extern in logic.h (defined here) ──────────────────────
Settings settings;
unsigned long lastSettingsMs = 0;
bool isPriming = false;
unsigned long primeEndMs = 0;

// ── State ─────────────────────────────────────────────────────────────────────
float    pressureKpa    = ATM_KPA + 0.0f; // Current MAP reading
uint8_t  pumpDuty       = 0;              // 0–100 %
bool     tankLow        = false;

// ── Telemetry timer ───────────────────────────────────────────────────────────
unsigned long lastTxMs  = 0;
constexpr unsigned long TX_INTERVAL_MS = 100;

// ── ADC oversampling ──────────────────────────────────────────────────────────
float readMapKpa() {
  uint32_t sum = 0;
  for (int i = 0; i < MAP_ADC_SAMPLES; i++) {
    sum += analogRead(PIN_MAP_SENSOR);
    delayMicroseconds(200);
  }
  float adcCounts = (float)sum / MAP_ADC_SAMPLES;

  // Convert ADC counts → millivolts
  float vMv = (adcCounts / 4095.0f) * MAP_VCC_MV;

  // Convert millivolts → kPa absolute (linear interpolation)
  float kpa = MAP_KPA_MIN + (vMv - MAP_V_MIN_MV) / (MAP_V_MAX_MV - MAP_V_MIN_MV)
              * (MAP_KPA_MAX - MAP_KPA_MIN);

  return constrain(kpa, 0.0f, MAP_KPA_MAX * 1.1f);
}

// ── Apply duty to LEDC PWM ────────────────────────────────────────────────────
void applyPwm(uint8_t duty0to100) {
  uint32_t raw = (uint32_t)duty0to100 * 255 / 100;
  ledcWrite(LEDC_CHANNEL, raw);
}

// ── Send telemetry JSON to Pi ─────────────────────────────────────────────────
void sendTelemetry() {
  StaticJsonDocument<128> doc;
  doc["t"] = "d";
  doc["p"] = serialized(String(pressureKpa, 1));
  doc["d"] = pumpDuty;
  doc["l"] = tankLow ? 1 : 0;
  serializeJson(doc, Serial);
  Serial.println();
}

// ── Arduino setup ─────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(SERIAL_BAUD);
  analogReadResolution(12);  // 12-bit ADC (0–4095)
  analogSetAttenuation(ADC_11db); // 0–3.3V input range

  pinMode(PIN_TANK_LEVEL, INPUT_PULLUP);
  pinMode(PIN_LED_ARMED,  OUTPUT);
  digitalWrite(PIN_LED_ARMED, LOW);

  // Configure LEDC PWM
  ledcSetup(LEDC_CHANNEL, PWM_FREQ_HZ, PWM_RESOLUTION_BITS);
  ledcAttachPin(PIN_PUMP_PWM, LEDC_CHANNEL);
  ledcWrite(LEDC_CHANNEL, 0);

  delay(200); // let ADC settle
}

// ── Arduino loop ──────────────────────────────────────────────────────────────
void loop() {
  unsigned long now = millis();

  // ── 1. Read incoming serial ──
  while (Serial.available()) {
    String line = Serial.readStringUntil('\n');
    line.trim();
    if (line.length() > 0) parseIncoming(line);
  }

  // ── 2. Settings watchdog: disarm if Pi goes silent ──
  if (lastSettingsMs > 0 && (now - lastSettingsMs) > SETTINGS_WATCHDOG_MS) {
    settings.armed = false;
  }

  // ── 3. Read sensors ──
  pressureKpa = readMapKpa();
  tankLow     = (digitalRead(PIN_TANK_LEVEL) == HIGH); // HIGH = switch open = low fluid

  // ── 4. Priming override ──
  if (isPriming) {
    if (now < primeEndMs) {
      applyPwm(100);
      pumpDuty = 100;
    } else {
      isPriming = false;
    }
  } else {
    // ── 5. Normal duty calculation ──
    pumpDuty = calcDuty(pressureKpa, tankLow, settings);
    applyPwm(pumpDuty);
  }

  // ── 6. Armed LED ──
  digitalWrite(PIN_LED_ARMED, settings.armed ? HIGH : LOW);

  // ── 7. Transmit telemetry at TX_INTERVAL_MS ──
  if (now - lastTxMs >= TX_INTERVAL_MS) {
    lastTxMs = now;
    sendTelemetry();
  }
}
