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

4. Implementation Details:
   - Fingerprints stored in device_data_t structure
   - Set during device info event in configuredc.c
   - Updated during dive enumeration callback
   - Persisted via DiveDataViewModel for future sessions

5. Memory Management:
   - Temporary fingerprint data allocated in device_data_t
   - Freed when device connection closes
   - Persistent copy maintained in UserDefaults
   - Safe copying between C and Swift layers

6. Key Functions:
   - dc_device_set_fingerprint(): Sets fingerprint on device
   - setup_device_events(): Configures event handling
   - event_cb(): Handles device events including fingerprint
   - diveCallbackClosure: Processes new fingerprints

7. Benefits:
   - Significantly reduces download time
   - Prevents duplicate dive downloads
   - Maintains download continuity
   - Device-specific optimization

8. Limitations:
   - Requires persistent storage
   - Device-specific implementation
   - Must handle first-time downloads
   - Needs proper error handling

### Important Steps for Fingerprinting
1. Register event handler first
2. Let it receive device info and set fingerprint
3. Then start enumeration

### Fingerprint Mechanism for Suunto Devices
1. Dives are enumerated newest to oldest (Dive 1 is newest)
2. Store fingerprint from newest dive (Dive 1) during first download
3. On next download:
   - Set stored fingerprint during device info event
   - Device should skip all dives up to that fingerprint
   - Only download dives newer than stored fingerprint
4. Update stored fingerprint with newest dive's fingerprint

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

## Dive Log Download Flow

### Download Sequence
1. **Initial Call**: `retrieveDiveLogs()` is called from the UI
   - Sets up the device context and callbacks
   - Registers event handler with `dc_device_set_events()`
   - Sets up fingerprint lookup function
   - Calls `dc_device_foreach()` to start enumeration

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

4. **Dive Processing**:
   - Each dive is parsed using `GenericParser`
   - Parsed data is added to view model
   - Progress is updated
   - New fingerprint is stored for next time

### Callback Chain
UI Action -> retrieveDiveLogs() -> dc_device_set_events() -> Registers event_cb -> dc_device_foreach() -> Starts enumeration -> event_cb (DC_EVENT_DEVINFO) -> Gets device info
-> fingerprintLookup() -> Checks stored fingerprint -> dc_device_set_fingerprint() -> Sets fingerprint on device -> diveCallbackClosure -> Processes each dive -> Parsing & Storage -> Updates UI

### Key Components
1. **event_cb (C callback)**:
   - Handles device events (info, progress)
   - Sets up fingerprint checking
   - First callback in the chain

2. **fingerprintLookup (Swift callback)**:
   - Called by event_cb when device info received
   - Checks stored fingerprints
   - Returns fingerprint data if found

3. **diveCallbackClosure (Swift callback)**:
   - Called for each dive during enumeration
   - Checks if dive matches stored fingerprint
   - Processes dive data if new

### Important Notes
- Callbacks are asynchronous
- Device info must be received before fingerprint can be set
- Fingerprint checking happens at two points:
  1. During device info event (to set device fingerprint)
  2. During dive enumeration (to check each dive)
- Progress updates happen during enumeration
- Background task warnings appear after 30 seconds

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

### Fingerprint System and Download Behavior

The fingerprint system works by storing the identifier of the newest dive during download. Here's how it handles different scenarios:

1. **Normal Download Flow**:
   - Dives are enumerated newest to oldest (Dive 1 is newest)
   - First dive's fingerprint is stored automatically
   - Used as reference point for next download

2. **Edge Cases**:

   a. **Toggle After Download**:
   - Toggle should be automatically ON after successful download
   - No manual enabling needed - fingerprint is already set
   - User can only disable to force full download next time

   b. **Toggle During Download**:
   - Toggle state cannot be changed during active download
   - Download must complete or be cancelled first
   - Prevents inconsistent fingerprint state

   c. **Toggle Before Download**:
   - Toggle should be disabled (grayed out)
   - Only enabled automatically after first successful download
   - Prevents invalid fingerprint states

   d. **Interrupted Downloads**:
   - If download is interrupted (crash/disconnect):
     * No fingerprint is saved
     * Next download starts fresh
     * Must complete a full download to set fingerprint
   - Ensures data consistency

3. **Best Practices**:
   - Fingerprint is always set automatically
   - Users can only disable, not enable manually
   - Toggle reflects fingerprint existence
   - Clear UI feedback about automatic nature

4. **Recovery Behavior**:
   - Failed download: No fingerprint saved
   - Partial download: No fingerprint saved
   - Successful download: Fingerprint saved automatically
   - Manual clear: Forces full download next time