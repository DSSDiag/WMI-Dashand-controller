import timeit
from typing import Optional

class MockPort:
    def __init__(self, device, description, hwid):
        self.device = device
        self.description = description
        self.hwid = hwid

# Original
def find_esp32_port_orig(ports):
    preferred_keywords = [
        "CP210", "CH340", "CH9102", "FTDI", "USB Serial",
        "USB-SERIAL", "ttyUSB", "ttyACM",
    ]
    for port in ports:
        desc = f"{port.description or ''} {port.hwid or ''}"
        for kw in preferred_keywords:
            if kw.lower() in desc.lower() or kw.lower() in port.device.lower():
                return port.device
    return ports[0].device if ports else None

# Optimized
def find_esp32_port_opt(ports):
    preferred_keywords = [
        "cp210", "ch340", "ch9102", "ftdi", "usb serial",
        "usb-serial", "ttyusb", "ttyacm",
    ]
    for port in ports:
        desc = f"{port.description or ''} {port.hwid or ''}".lower()
        device = port.device.lower()
        if any(kw in desc or kw in device for kw in preferred_keywords):
            return port.device
    return ports[0].device if ports else None

ports = [
    MockPort("COM1", "Standard Serial over Bluetooth link", "BTHENUM\\{00001101-0000-1000-8000-00805F9B34FB}_LOCALMFG&0000\\7&199E0F2B&0&000000000000_00000000"),
    MockPort("COM2", "Standard Serial over Bluetooth link", "BTHENUM\\{00001101-0000-1000-8000-00805F9B34FB}_LOCALMFG&0000\\7&199E0F2B&0&000000000000_00000000"),
    MockPort("COM3", "Standard Serial", "ACPI\\PNP0501\\1"),
    MockPort("/dev/ttyACM0", "USB Serial Device", "USB VID:PID=2341:0043")
]

# When it's not found
ports_not_found = ports[:-1]

orig_time = timeit.timeit(lambda: find_esp32_port_orig(ports), number=100000)
opt_time = timeit.timeit(lambda: find_esp32_port_opt(ports), number=100000)

orig_nf_time = timeit.timeit(lambda: find_esp32_port_orig(ports_not_found), number=100000)
opt_nf_time = timeit.timeit(lambda: find_esp32_port_opt(ports_not_found), number=100000)

print(f"Found Case:")
print(f"  Original: {orig_time:.4f}s")
print(f"  Optimized: {opt_time:.4f}s")
print(f"  Improvement: {orig_time / opt_time:.2f}x")

print(f"\nNot Found Case:")
print(f"  Original: {orig_nf_time:.4f}s")
print(f"  Optimized: {opt_nf_time:.4f}s")
print(f"  Improvement: {orig_nf_time / opt_nf_time:.2f}x")
