CXX = g++
CXXFLAGS = -std=c++14 -Wall -I. -I../wmi_controller

# If ArduinoJson is not installed globally, we can clone it
ARDUINO_JSON_DIR = ArduinoJson
ARDUINO_JSON_TAG = v7.3.0

# Google Test libraries
LIBS = -lgtest -lgtest_main -pthread

TARGET = test_logic
SRCS = test_logic.cpp

all: $(TARGET)

$(ARDUINO_JSON_DIR):
	if [ ! -d "$(ARDUINO_JSON_DIR)" ]; then git clone --depth 1 --branch $(ARDUINO_JSON_TAG) https://github.com/bblanchon/ArduinoJson.git $(ARDUINO_JSON_DIR); fi

$(TARGET): $(SRCS) $(ARDUINO_JSON_DIR)
	$(CXX) $(CXXFLAGS) -I$(ARDUINO_JSON_DIR)/src $(SRCS) -o $(TARGET) $(LIBS)

test: all
	./$(TARGET)

clean:
	rm -f $(TARGET)
	rm -rf $(ARDUINO_JSON_DIR)

.PHONY: all test clean
