CXX = g++
CXXFLAGS = -std=c++14 -Wall -I. -I../wmi_controller -I./vendor

# Google Test libraries
LIBS = -lgtest -lgtest_main -pthread

TARGET = test_logic
SRCS = test_logic.cpp

all: $(TARGET)

$(TARGET): $(SRCS)
	$(CXX) $(CXXFLAGS) $(SRCS) -o $(TARGET) $(LIBS)

test: all
	./$(TARGET)

clean:
	rm -f $(TARGET)

.PHONY: all test clean
