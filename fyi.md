# BLE Test Application Overview

This codebase implements a Bluetooth Low Energy (BLE) application for communicating with Suunto EON Steel and D5 dive computers.

## Key Files and Their Purposes

### Core Components
- **BLEManager.swift**: Handles BLE communication and device management
- **BluetoothScanView.swift**: Main UI for scanning and connecting to devices
- **ConnectedDeviceView.swift**: Handles dive log retrieval and display
- **DiveDataViewModel.swift**: Manages dive data and state
- **DiveLogSettingsView.swift**: Manages fingerprint and device settings

### Protocol Implementation
- **configuredc.c**: Bridge between Swift and libdivecomputer
- **DiveLogRetriever.swift**: Handles dive log downloading and parsing
- **GenericParser.swift**: Parses dive data from different device families

## Key Features

### Fingerprint Implementation
- Stores fingerprint of most recent dive
- Uses UserDefaults for persistence
- Speeds up subsequent downloads
- Set via dc_device_set_fingerprint()
- Toggle in settings to enable/disable fingerprint usage

### Device Management
- Stores connected device information
- Tracks first connection date
- Allows manual device forgetting
- Persists device settings

### Progress Reporting
- Real-time dive counting as logs are processed
- Accurate representation of discovered dives
- UI updates as each dive is parsed
- Timer-based progress monitoring

## Common Operations

### Retrieving Dive Logs
1. Connect to device via BLE
2. Open device using libdivecomputer
3. Set fingerprint if enabled
4. Enumerate dives using dc_device_foreach
5. Parse dive data using appropriate parser
6. Display results in UI

### Error Handling
- Validates device connections
- Checks parsing status
- Reports detailed errors in UI
- Handles BLE disconnections
- Provides status codes in error messages

## Future Work

### High Priority
1. Fix dive enumeration issues:
   - Investigate why dives aren't being enumerated
   - Add more detailed logging for dive callbacks
   - Verify parser creation and usage
   - Test with different device states

2. Improve Fingerprint System:
   - Add ability to manually set fingerprint
   - Better fingerprint validation
   - Visual indicator for fingerprint status
   - Fingerprint history tracking

3. Enhance Error Handling:
   - More detailed error messages
   - Recovery suggestions
   - Automatic retry mechanisms
   - Connection state recovery

### Medium Priority
1. Data Management:
   - Local storage for dive logs
   - Export functionality
   - Backup/restore capabilities
   - Data synchronization

2. UI Improvements:
   - Dive profile visualization
   - Better progress indicators
   - Detailed dive statistics
   - Custom dive log filters

3. Device Support:
   - Add support for more dive computers
   - Better device identification
   - Multiple device management
   - Device-specific settings

## Known Issues
1. Dive enumeration not working properly
2. Fingerprint toggle needs improvement
3. Progress reporting could be more accurate
4. Error messages need more detail
5. Device identification could be more robust

## Recent Findings and Improvements

### Bluetooth Connection Management
1. Device Disconnection:
   - Proper cleanup of device pointers
   - Handling of system-level disconnects
   - UI state synchronization during disconnect
   - Prevention of memory deallocation issues
   - Improved connection timeout handling
   - Better state management during transitions

2. Connection State Handling:
   - Better state management between views
   - Improved connection status indicators
   - Proper handling of transitional states
   - Clear distinction between app-level and system-level connections
   - Connection timeout with automatic cleanup
   - Proper state reset after failed connections

3. Device Organization:
   - Separated devices into "My Devices" and "Available Devices" sections
   - Proper categorization based on storage status
   - Maintained device state across disconnections
   - Improved device row state management
   - Better handling of forgotten devices
   - Clear visual indicators for device status

4. UI Improvements:
   - Better button state management
   - Clear connection status indicators
   - Proper timeout handling for connections
   - Improved error handling and user feedback
   - Consistent device presentation
   - Swipe-to-forget functionality for stored devices

### Known Issues and Limitations
1. iOS Bluetooth Settings:
   - System-level Bluetooth connection may persist after app disconnect
   - No direct way to force system-level disconnect
   - May require manual "Forget This Device" in iOS settings

2. Connection Management:
   - Connection attempts need timeout handling
   - State cleanup required across multiple views
   - Need to handle background disconnections
   - Must manage multiple state variables

3. UI State:
   - Need to force refresh device list after state changes
   - Must handle transitional states carefully
   - Connection status needs to be clearly indicated
   - Device categorization must be maintained

### Memory Management Notes
- Device pointers must be properly managed during disconnect
- State cleanup must happen in correct order
- Proper main thread handling for UI updates
- Clear separation between app and system-level disconnects
- Timer cleanup required to prevent memory leaks
- Connection state must be properly reset

### Future Improvements
1. Connection Management:
   - Implement automatic reconnection for temporary disconnects
   - Better handling of system-level Bluetooth state
   - Improved connection timeout handling
   - More robust state management

2. UI Enhancements:
   - Better visual feedback during state transitions
   - More detailed connection status information
   - Improved error messaging
   - Smoother list updates

3. Device Management:
   - Better handling of forgotten devices
   - Improved device categorization
   - More detailed device information
   - Better storage management