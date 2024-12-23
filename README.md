# libdc-swift

This project integrates Bluetooth Low Energy (BLE) functionality with dive computers, specifically focusing on Suunto devices. It provides a bridge between Swift and C for using libdivecomputer, a user interface for scanning and connecting to BLE devices, and a manager for handling BLE operations.

## Components

### 1. BLEBridge

**Files**: `BLEBridge.m` and `BLEBridge.h`

The BLEBridge acts as an intermediary between Swift and C, managing:
- BLE object lifecycle (creation and disposal)
- Device connections and data transfer
- Service and characteristic discovery
- Notification handling
- Read/write operations with timeouts

### 2. ConfigureDC

**Files**: `configuredc.c` and `configuredc.h`

Handles dive computer configuration, particularly for Suunto EON Steel:
- Device initialization and opening
- BLE packet communication setup
- HDLC protocol implementation
- Data structure management

### 3. BluetoothScanView

**File**: `BluetoothScanView.swift`

SwiftUI interface providing:
- Device scanning and discovery
- Connection management
- Dive log retrieval
- Status display and progress updates

### 4. BLEManager

**File**: `BLEManager.swift`

Core Bluetooth operations manager handling:
- Device scanning and connection
- Service/characteristic discovery
- Data transfer with timeout handling
- Event management and state changes

## Communication Protocol

### HDLC Implementation
- Frame markers: 0x7E
- Data escaping for control characters
- Checksum validation
- Partial read support with timeouts
  - 5-second timeout for partial reads
  - 30-second timeout for full reads

### Dive Log Structure
1. Directory Listing
   - Returns .LOG files
   - XXXXXXXX.LOG format (X = hex timestamp)

2. Log Format
   - 4-byte timestamp (little-endian)
   - SBEM (Suunto Binary Encoded Message) data
   - Profile data, settings, and samples

### BLE Communication
- Notification-based data transfer (20-byte chunks)
- Buffer management for data accumulation
- Service UUID: "0000FEF5-0000-1000-8000-00805F9B34FB"
- Write Characteristic: "C6339440-E62E-11E3-A5B3-0002A5D5C51B"
- Notify Characteristic: "D0FD6B80-E62E-11E3-A2E9-0002A5D5C51B"

## Features

### Fingerprint Management
- Stores most recent dive fingerprint
- Persists across app launches via UserDefaults
- Enables incremental updates
- Set on device connection
- Updates after successful enumeration

### Error Prevention
- Safe BLE object lifecycle management
- Thread-safe buffer operations
- Proper cleanup on disconnection
- Timeout handling for operations

## Requirements
- iOS 14.0+
- Swift 5.0+
- libdivecomputer (linked as C library)
- CoreBluetooth
- SwiftUI

## Future Improvements
- Enhanced dive data parsing (depth, temperature)
- Profile visualization
- Local storage implementation
- Incremental update optimization
- Progress tracking per dive
- Multi-device support
- Enhanced event handling
- Cancellation support for long operations
- Memory dump capabilities for debugging
