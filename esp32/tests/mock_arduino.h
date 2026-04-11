#pragma once

#include <string>
#include <cstdint>
#include <cstring>

class String {
public:
    String(const char* str) : data(str) {}
    String(const std::string& str) : data(str) {}
    const char* c_str() const { return data.c_str(); }
    bool operator==(const char* str) const { return data == str; }

    // Add methods that ArduinoJson expects from a String-like object
    size_t length() const { return data.length(); }
    const char* begin() const { return data.c_str(); }
    const char* end() const { return data.c_str() + data.length(); }
private:
    std::string data;
};

// Define constants that would normally come from config.h and Arduino.h
// Omit them here and let config.h define them to avoid redefinition warnings

typedef uint8_t byte;

unsigned long millis();
