#include "logic.h"
#include <iostream>
#include <cassert>

using namespace std;

void test_disarmed() {
    Settings s;
    s.armed = false;
    assert(calcDuty(100.0f, false, s) == 0);
}

void test_tank_low() {
    Settings s;
    s.armed = true;
    assert(calcDuty(100.0f, true, s) == 0);
}

void test_manual_mode() {
    Settings s;
    s.armed = true;
    s.triggerMode = 2;
    s.manualDuty = 42;
    assert(calcDuty(10.0f, false, s) == 42);
    assert(calcDuty(100.0f, false, s) == 42);
}

void test_full_scale_linear() {
    Settings s;
    s.armed = true;
    s.triggerMode = 1;
    s.curve = 0; // Linear

    float range = MAP_KPA_MAX - MAP_KPA_MIN;

    // Below min
    assert(calcDuty(MAP_KPA_MIN - 10.0f, false, s) == 0);

    // At min
    assert(calcDuty(MAP_KPA_MIN, false, s) == 0);

    // Midpoint
    assert(calcDuty(MAP_KPA_MIN + range / 2.0f, false, s) == 50);

    // At max
    assert(calcDuty(MAP_KPA_MAX, false, s) == 100);

    // Above max
    assert(calcDuty(MAP_KPA_MAX + 10.0f, false, s) == 100);
}

void test_full_scale_exponential() {
    Settings s;
    s.armed = true;
    s.triggerMode = 1;
    s.curve = 1; // Exponential

    float range = MAP_KPA_MAX - MAP_KPA_MIN;

    // Below min
    assert(calcDuty(MAP_KPA_MIN - 10.0f, false, s) == 0);

    // At min
    assert(calcDuty(MAP_KPA_MIN, false, s) == 0);

    // Midpoint (0.5 * 0.5 = 0.25 -> 25%)
    assert(calcDuty(MAP_KPA_MIN + range / 2.0f, false, s) == 25);

    // At max
    assert(calcDuty(MAP_KPA_MAX, false, s) == 100);
}

void test_thresholds_linear() {
    Settings s;
    s.armed = true;
    s.triggerMode = 0;
    s.curve = 0; // Linear
    s.startKpa = 110.0f;
    s.fullKpa = 210.0f;

    // Below start
    assert(calcDuty(100.0f, false, s) == 0);

    // At start
    assert(calcDuty(110.0f, false, s) == 0);

    // Midpoint
    assert(calcDuty(160.0f, false, s) == 50);

    // At full
    assert(calcDuty(210.0f, false, s) == 100);

    // Above full
    assert(calcDuty(220.0f, false, s) == 100);
}

void test_thresholds_exponential() {
    Settings s;
    s.armed = true;
    s.triggerMode = 0;
    s.curve = 1; // Exponential
    s.startKpa = 110.0f;
    s.fullKpa = 210.0f;

    // Below start
    assert(calcDuty(100.0f, false, s) == 0);

    // At start
    assert(calcDuty(110.0f, false, s) == 0);

    // Midpoint (0.5 * 0.5 = 0.25 -> 25%)
    assert(calcDuty(160.0f, false, s) == 25);

    // At full
    assert(calcDuty(210.0f, false, s) == 100);

    // Above full
    assert(calcDuty(220.0f, false, s) == 100);
}

void test_thresholds_zero_range() {
    Settings s;
    s.armed = true;
    s.triggerMode = 0;
    s.curve = 0;
    s.startKpa = 150.0f;
    s.fullKpa = 150.0f;

    // Edge case: range <= 0
    assert(calcDuty(140.0f, false, s) == 0);
    assert(calcDuty(150.0f, false, s) == 0);
    assert(calcDuty(151.0f, false, s) == 100);
}

int main() {
    cout << "Running logic tests..." << endl;

    test_disarmed();
    test_tank_low();
    test_manual_mode();
    test_full_scale_linear();
    test_full_scale_exponential();
    test_thresholds_linear();
    test_thresholds_exponential();
    test_thresholds_zero_range();

    cout << "All logic tests passed!" << endl;
    return 0;
}
