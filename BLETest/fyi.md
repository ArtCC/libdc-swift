# BLE Test Application Overview

This codebase implements a Bluetooth Low Energy (BLE) application for communicating with Suunto EON Steel and D5 dive computers.

## Key Files and Their Purposes

### BLETest App
- **BLETestApp.swift**: Main entry point for the SwiftUI application
- **BluetoothScanView.swift**: Main UI for scanning and connecting to BLE devices
  - Implements device discovery and connection interface
  - Handles device connection state management
  - Shows connected device details and controls

### Core Bluetooth Implementation
- **BLEManager.swift**: Core Bluetooth manager class
  - Handles BLE device scanning, connection, and communication
  - Implements CoreBluetooth protocols
  - Manages Suunto EON Steel specific services and characteristics

### Bridge Layer
- **BLEBridge.h/.m**: Objective-C bridge between Swift and C code
  - Provides C interface for BLE operations
  - Bridges CoreBluetoothManager to libdivecomputer
  - Handles memory management between Swift and C

### Dive Computer Library
- **configuredc.h/.c**: Configuration interface for dive computers
  - Defines device data structures
  - Implements device opening and configuration
  - Handles BLE protocol setup

- **suunto_eonsteel.c**: Suunto EON Steel specific implementation
  - Implements device-specific communication protocol
  - Handles HDLC protocol for BLE communication
  - Manages dive data transfer and parsing

### Headers
- **BLETest-Bridging-Header.h**: Swift-to-C bridging header
  - Exposes C functions to Swift code
  - Enables cross-language communication
- **hdlc.h**: HDLC protocol implementation
  - Handles HDLC framing for BLE communication
  - Provides packet encapsulation and error checking
  - Used by Suunto EON Steel/D5 communication

## Key Protocols and UUIDs

### Suunto EON Steel BLE Services
- Service UUID: "0000FEF5-0000-1000-8000-00805F9B34FB"
- Write Characteristic: "C6339440-E62E-11E3-A5B3-0002A5D5C51B" (Write without Response)
- Notify Characteristic: "D0FD6B80-E62E-11E3-A2E9-0002A5D5C51B" 

## Dependencies
- CoreBluetooth
- libdivecomputer (not really modified, only added configuredc.c for trying in Swift app)
- SwiftUI

## Communication Flow
1. Swift UI (BluetoothScanView) initiates device scanning and connects to the device.
2. From ConnectedDeviceView, user taps "Read Dive Data" → calls BLEManager.readData().
3. BLEManager calls open_suunto_eonsteel() in configuredc.c, which creates a custom DC I/O stream via ble_packet_open().
4. suunto_eonsteel_device_open() checks DC_TRANSPORT_BLE and calls dc_hdlc_open() internally. 
5. dc_device_foreach() is called to enumerate all dives on the device.
6. For each dive log found:
   - Dive date/time is parsed
   - Maximum depth is extracted
   - Dive duration is recorded
   - All data is printed to console (can be bridged to Swift)

## Communication Protocol

### HDLC Protocol
The Suunto D5 uses HDLC (High-Level Data Link Control) framing for BLE communication:
- Frame Start/End: 0x7E marker
- Data is escaped to avoid conflicts with control characters
- Example frame: 7E [payload] 7E

### Dive Log Structure
1. Directory Listing Request
   - Device responds with list of .LOG files
   - Each log file represents one dive
   - Format: XXXXXXXX.LOG (where X is hex timestamp)

2. Log File Format
   - First 4 bytes: Little-endian timestamp
   - Remaining data: SBEM (Suunto Binary Encoded Message)
   - Contains dive profile, settings, and samples

3. Sample Data Fields
   - Depth readings
   - Temperature
   - Tank pressure
   - Decompression information
   - Gas switches
   - Bookmarks

### Data Flow
1. Initial Connection
   ```
   7E 0002 0200 [device info] 7E
   ```

2. Directory Listing
   ```
   7E 1008/1009 [file entries] 7E
   ```

3. Individual Log Files
   ```
   [timestamp][SBEM data]
   ```

## Parsing Process
1. HDLC Layer
   - Strips 0x7E markers
   - De-escapes control sequences
   - Validates checksums

2. Command Layer
   - Interprets command codes (0x0002, 0x1008, etc.)
   - Handles directory listings
   - Manages file transfers

3. Log Parser
   - Uses suunto_eonsteel_parser
   - Extracts dive profile data
   - Processes sample information

# Additional FYI

- The ble_object_t lifecycle: Created by createBLEObject, freed by freeBLEObject (if iostream creation fails) or by ble_stream_close (if iostream exists). This prevents double-free issues.

- BLE Communication Pattern:
  - Device sends data via notifications in 20-byte chunks
  - BLE layer accumulates these chunks in a buffer
  - Supports partial reads: returns whatever data is available (up to requested size)
  - Uses 5-second timeout for partial reads, 30-second timeout for full reads
  - Let's libdivecomputer handle HDLC framing (0x7E markers)

- Error Prevention:
  - Avoid calling dc_iostream_close twice (once in suunto_eonsteel_device_open, once in error cleanup)
  - Never try direct reads from notification characteristic
  - Use thread-safe queue for buffer access