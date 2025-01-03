# BLE Test Application Overview

This codebase implements a Bluetooth Low Energy (BLE) application for communicating with Suunto EON Steel and D5 dive computers.

## Key Files and Their Purposes

### Core Components
- **BLEManager.swift**: Handles BLE communication and device management
- **DiveDataViewModel.swift**: Manages dive data and state, includes active download state management

### Protocol Implementation
- **configuredc.c**: Bridge between Swift and libdivecomputer
- **DiveLogRetriever.swift**: Handles dive log downloading and parsing
- **GenericParser.swift**: Parses dive data from different device families

## Key Features

### Fingerprint Implementation

The fingerprint system in libdivecomputer is used to identify previously downloaded dives and optimize subsequent downloads. The fingerprint represents the last downloaded dive's identifier, which is used to skip all dives up to that point in the next download. Here's how it works:

1. Device-Side Implementation:
   - Each dive computer stores a unique identifier (fingerprint) for each dive
   - Fingerprints are used to identify specific dives on the device
   - Format and size of fingerprints vary by device manufacturer

2. Download Process:
   - When starting a download, stored fingerprint is set via `dc_device_set_fingerprint()`
   - Device uses this fingerprint to identify the last downloaded dive
   - Only dives newer than the fingerprinted dive are downloaded
   - Each downloaded dive provides its own fingerprint via callback

3. Storage Flow:
   - Persistent Storage:
     * Fingerprints are stored with device type and serial number in UserDefaults
     * Kept until explicitly cleared or device is forgotten
     * Used to maintain download history across app sessions
   - Temporary Storage:
     * Stored in device_data_t during download operation
     * Cleaned up when device connection closes
     * Used for active download session only

## Dive Log Download Flow

### Download Sequence
1. **Initial Call**: `retrieveDiveLogs()` is called from ConnectedDeviceView
   - Sets up the device context and callbacks
   - Registers event handler with `dc_device_set_events()`
   - Sets up fingerprint lookup function
   - Calls `dc_device_foreach()` to start enumeration
   - Stores active download state for UI restoration

2. **Device Info Event**:
   - When device connects, `DC_EVENT_DEVINFO` is triggered
   - Event callback (`event_cb`) in configuredc.c receives device info
   - Callback gets serial number and model info
   - If fingerprint lookup is configured, it calls the Swift lookup function
   - If fingerprint found, sets it with `dc_device_set_fingerprint()`

3. **Dive Enumeration**:
   - After device info, `dc_device_foreach()` starts enumerating dives
   - For each dive, calls `diveCallbackClosure` in Swift
   - Callback receives dive data and fingerprint
   - If fingerprint matches stored one, stops enumeration
   - Otherwise processes dive data and continues

### Fingerprint System and Download Behavior

First Download:
1. Start enumeration
2. First dive (newest) -> store fingerprint in context.lastFingerprint
3. Continue processing remaining dives
4. Enumeration completes
5. Save context.lastFingerprint as the stored fingerprint

Next Download:
1. Get device info
2. Set stored fingerprint on device
3. Start enumeration
4. First dive (newest) -> store fingerprint in context.lastFingerprint
5. Continue until matching fingerprint found
6. Enumeration completes
7. Save context.lastFingerprint as new stored fingerprint