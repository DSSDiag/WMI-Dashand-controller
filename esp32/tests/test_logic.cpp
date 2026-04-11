#include <gtest/gtest.h>
#include <ArduinoJson.h>
#include "mock_arduino.h"

// Mock millis
unsigned long millis_val = 0;
unsigned long millis() {
    return millis_val;
}

// include logic.h
#include "../wmi_controller/logic.h"

// Define the external variables referenced by logic.h
Settings settings;
unsigned long lastSettingsMs = 0;
bool isPriming = false;
unsigned long primeEndMs = 0;

class ParseIncomingTest : public ::testing::Test {
protected:
    void SetUp() override {
        // Reset state before each test
        settings = Settings();
        lastSettingsMs = 0;
        isPriming = false;
        primeEndMs = 0;
        millis_val = 0;
    }
};

TEST_F(ParseIncomingTest, ParsesCompleteSettings) {
    millis_val = 1000;
    parseIncoming(String(R"({"t":"s","tm":1,"sp":150.0,"fp":250.0,"md":50,"c":1,"a":1})"));

    EXPECT_EQ(settings.triggerMode, 1);
    EXPECT_FLOAT_EQ(settings.startKpa, 150.0f);
    EXPECT_FLOAT_EQ(settings.fullKpa, 250.0f);
    EXPECT_EQ(settings.manualDuty, 50);
    EXPECT_EQ(settings.curve, 1);
    EXPECT_TRUE(settings.armed);
    EXPECT_EQ(lastSettingsMs, 1000UL);
}

TEST_F(ParseIncomingTest, ParsesPartialSettings) {
    // Pre-set some fields to non-default values to verify they are preserved
    settings.armed = true;
    settings.startKpa = DEFAULT_START_KPA + 10.0f;
    settings.fullKpa = DEFAULT_FULL_KPA + 20.0f;
    settings.curve = DEFAULT_CURVE + 1;

    millis_val = 2000;
    parseIncoming(String(R"({"t":"s","tm":2,"md":75})"));

    // Should update provided values
    EXPECT_EQ(settings.triggerMode, 2);
    EXPECT_EQ(settings.manualDuty, 75);

    // Should keep existing values for omitted fields
    EXPECT_FLOAT_EQ(settings.startKpa, DEFAULT_START_KPA + 10.0f);
    EXPECT_FLOAT_EQ(settings.fullKpa, DEFAULT_FULL_KPA + 20.0f);
    EXPECT_EQ(settings.curve, DEFAULT_CURVE + 1);
    EXPECT_TRUE(settings.armed);

    // Should record the time at which settings were last received
    EXPECT_EQ(lastSettingsMs, 2000UL);
}

TEST_F(ParseIncomingTest, ParsesPrimeCommand) {
    millis_val = 5000;
    parseIncoming(String(R"({"t":"prime"})"));

    EXPECT_TRUE(isPriming);
    EXPECT_EQ(primeEndMs, 7000UL);
}

TEST_F(ParseIncomingTest, IgnoresInvalidJson) {
    parseIncoming(String("{invalid_json}"));

    // Should not change anything
    EXPECT_EQ(settings.triggerMode, DEFAULT_TRIGGER_MODE);
    EXPECT_FALSE(isPriming);
}

TEST_F(ParseIncomingTest, IgnoresMissingType) {
    parseIncoming(String(R"({"tm":1,"sp":150.0})"));

    // Should not change anything
    EXPECT_EQ(settings.triggerMode, DEFAULT_TRIGGER_MODE);
    EXPECT_FALSE(isPriming);
}

TEST_F(ParseIncomingTest, IgnoresUnknownType) {
    parseIncoming(String(R"({"t":"unknown","tm":1})"));

    // Should not change anything
    EXPECT_EQ(settings.triggerMode, DEFAULT_TRIGGER_MODE);
    EXPECT_FALSE(isPriming);
}

// ── calcDuty Tests ────────────────────────────────────────────────────────────

TEST(CalcDutyTest, ReturnsZeroWhenDisarmed) {
    Settings s;
    s.armed = false;
    EXPECT_EQ(calcDuty(100.0f, false, s), 0);
}

TEST(CalcDutyTest, ReturnsZeroWhenTankLow) {
    Settings s;
    s.armed = true;
    EXPECT_EQ(calcDuty(100.0f, true, s), 0);
}

TEST(CalcDutyTest, ManualMode) {
    Settings s;
    s.armed = true;
    s.triggerMode = 2;
    s.manualDuty = 42;
    EXPECT_EQ(calcDuty(10.0f, false, s), 42);
    EXPECT_EQ(calcDuty(100.0f, false, s), 42);
}

TEST(CalcDutyTest, FullScaleLinear) {
    Settings s;
    s.armed = true;
    s.triggerMode = 1;
    s.curve = 0; // Linear

    float range = MAP_KPA_MAX - MAP_KPA_MIN;

    // Below min
    EXPECT_EQ(calcDuty(MAP_KPA_MIN - 10.0f, false, s), 0);
    // At min
    EXPECT_EQ(calcDuty(MAP_KPA_MIN, false, s), 0);
    // Midpoint
    EXPECT_EQ(calcDuty(MAP_KPA_MIN + range / 2.0f, false, s), 50);
    // At max
    EXPECT_EQ(calcDuty(MAP_KPA_MAX, false, s), 100);
    // Above max
    EXPECT_EQ(calcDuty(MAP_KPA_MAX + 10.0f, false, s), 100);
}

TEST(CalcDutyTest, FullScaleExponential) {
    Settings s;
    s.armed = true;
    s.triggerMode = 1;
    s.curve = 1; // Exponential

    float range = MAP_KPA_MAX - MAP_KPA_MIN;

    // Below min
    EXPECT_EQ(calcDuty(MAP_KPA_MIN - 10.0f, false, s), 0);
    // At min
    EXPECT_EQ(calcDuty(MAP_KPA_MIN, false, s), 0);
    // Midpoint (0.5 * 0.5 = 0.25 -> 25%)
    EXPECT_EQ(calcDuty(MAP_KPA_MIN + range / 2.0f, false, s), 25);
    // At max
    EXPECT_EQ(calcDuty(MAP_KPA_MAX, false, s), 100);
}

TEST(CalcDutyTest, ThresholdsLinear) {
    Settings s;
    s.armed = true;
    s.triggerMode = 0;
    s.curve = 0; // Linear
    s.startKpa = 110.0f;
    s.fullKpa = 210.0f;

    // Below start
    EXPECT_EQ(calcDuty(100.0f, false, s), 0);
    // At start
    EXPECT_EQ(calcDuty(110.0f, false, s), 0);
    // Midpoint
    EXPECT_EQ(calcDuty(160.0f, false, s), 50);
    // At full
    EXPECT_EQ(calcDuty(210.0f, false, s), 100);
    // Above full
    EXPECT_EQ(calcDuty(220.0f, false, s), 100);
}

TEST(CalcDutyTest, ThresholdsExponential) {
    Settings s;
    s.armed = true;
    s.triggerMode = 0;
    s.curve = 1; // Exponential
    s.startKpa = 110.0f;
    s.fullKpa = 210.0f;

    // Below start
    EXPECT_EQ(calcDuty(100.0f, false, s), 0);
    // At start
    EXPECT_EQ(calcDuty(110.0f, false, s), 0);
    // Midpoint (0.5 * 0.5 = 0.25 -> 25%)
    EXPECT_EQ(calcDuty(160.0f, false, s), 25);
    // At full
    EXPECT_EQ(calcDuty(210.0f, false, s), 100);
    // Above full
    EXPECT_EQ(calcDuty(220.0f, false, s), 100);
}

TEST(CalcDutyTest, ThresholdsZeroRange) {
    Settings s;
    s.armed = true;
    s.triggerMode = 0;
    s.curve = 0;
    s.startKpa = 150.0f;
    s.fullKpa = 150.0f;

    // Edge case: range <= 0
    EXPECT_EQ(calcDuty(140.0f, false, s), 0);
    EXPECT_EQ(calcDuty(150.0f, false, s), 0);
    EXPECT_EQ(calcDuty(151.0f, false, s), 100);
}
