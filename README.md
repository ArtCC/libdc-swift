# libdc-swift

This project integrates Bluetooth Low Energy (BLE) functionality with dive computers, specifically focusing on Suunto devices. It provides a bridge between Swift and C for using libdivecomputer, a user interface for scanning and connecting to BLE devices, and a manager for handling BLE operations.

## Components

### 1. BLEBridge

**Files**: `BLEBridge.m` and `BLEBridge.h`

The BLEBridge acts as an intermediary between the Swift codebase and the C-based libdivecomputer library. It provides the following functionality:

- Creation and management of BLE objects
- Connection to BLE devices
- Service and characteristic discovery
- Enabling notifications
- Reading and writing data
- Handling timeouts and sleep operations

Key functions:
- `createBLEObject`
- `connectToBLEDevice`
- `discoverServices`
- `enableNotifications`
- `ble_read`, `ble_write`

### 2. ConfigureDC

**Files**: `configuredc.c` and `configuredc.h`

ConfigureDC handles the configuration and opening of dive computer devices, particularly Suunto EON Steel. It provides:

- Opening of Suunto EON Steel devices
- Initialization of device data structures
- Setup of BLE packet communication

Key functions:
- `open_suunto_eonsteel`
- `ble_packet_open`

### 3. BluetoothScanView

**File**: `BluetoothScanView.swift`

BluetoothScanView is a SwiftUI view that provides the user interface for:

- Scanning for available BLE devices
- Displaying a list of discovered devices
- Connecting to selected devices
- Showing connection status and device information

Key features:
- Device list with connection buttons
- Scan start/stop functionality
- Display of connected device information

### 4. BLEManager (CoreBluetoothManager)

**File**: `BLEManager.swift`

The BLEManager (implemented as CoreBluetoothManager) is responsible for managing BLE operations in Swift. It provides:

- Bluetooth device scanning
- Connection to BLE devices
- Service and characteristic discovery
- Reading and writing data to BLE devices
- Handling of BLE events and state changes

Key functions:
- `startScanning`, `stopScanning`
- `connectToDevice`
- `discoverServices`
- `readData`, `writeData`

## Integration Flow

1. The user interacts with the BluetoothScanView to scan for and select a dive computer.
2. Upon selection, the BLEManager establishes a connection with the device.
3. The ConfigureDC component uses the BLEBridge to open a connection to the dive computer using libdivecomputer.
4. Data can then be exchanged between the iOS app and the dive computer through the established BLE connection.

## Requirements

- iOS 14.0+
- Swift 5.0+
- libdivecomputer (linked as a C library)

## Known Issues

- CRC mismatch when receiving data from Suunto devices
- Occasional disconnections after initial connection

## Future Improvements

- Enhance error handling and recovery mechanisms
- Improve data parsing for specific dive computer models
- Add support for additional dive computer brands

## Libdivecomputer License

<details>
<summary>Click to expand</summary>

Overview
========

Libdivecomputer is a cross-platform and open source library for
communication with dive computers from various manufacturers.

The official web site is:

  http://www.libdivecomputer.org/

The sourceforge project page is:

  http://sourceforge.net/projects/libdivecomputer/

Installation
============

On UNIX-like systems (including Linux, Mac OS X, MinGW), use the
autotools based build system. Run the following commands from the top
directory (containing this file) to configure, build and install the
library and utilities:

  $ ./configure
  $ make
  $ make install

If you downloaded the libdivecomputer source code directly from the git
source code repository, then you need to create the configure script as
the first step:

  $ autoreconf --install

To uninstall libdivecomputer again, run:

  $ make uninstall

Support
=======

Please send bug reports, feedback or questions to the mailing list:

  http://libdivecomputer.org/cgi-bin/mailman/listinfo/devel

or contact me directly:

  jef@libdivecomputer.org

License
=======

Libdivecomputer is free software, released under the terms of the GNU
Lesser General Public License (LGPL).

You can find a copy of the license in the file COPYING.

</details>
