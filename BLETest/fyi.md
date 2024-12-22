# BLE Test Application Overview

This codebase implements a Bluetooth Low Energy (BLE) application for communicating with Suunto EON Steel dive computers.

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