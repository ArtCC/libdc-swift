Below is an updated version of your README that reflects how you use the dive log retriever in production (especially in SwiftUI). Feel free to adjust the code snippet and wording to match your project’s conventions.

---

# LibDC-Swift

A Swift framework for communicating with dive computers via Bluetooth Low Energy (BLE). Built on top of [libdivecomputer](https://www.libdivecomputer.org/), this package provides a modern Swift API for iOS and macOS applications to interact with various dive computers.

## Features

- 🔍 **BLE Device Scanning and Management:** Discover and manage BLE-enabled dive computers.
- 📱 **Broad Device Support:** Works with popular dive computer brands such as Suunto, Shearwater, Mares, Pelagic, and others.
- 📥 **Efficient Dive Log Retrieval:** Retrieve dive logs using a fingerprint system to avoid re-downloading previously fetched dives.
- 📊 **Comprehensive Data Parsing:** Parse raw dive data and transform it into usable models.
- 🛠 **Robust Error Handling and Logging:** Built-in mechanisms for tracking and reporting errors.
- ⏱ **Progress Tracking & Background Support:** Integrated progress updates, background execution, and even Live Activity integration for iOS.
- 🔄 **Seamless SwiftUI Integration:** Designed to work naturally with SwiftUI for real-time UI updates.

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.10+
- Xcode 15.0+

## Installation

Add LibDC-Swift to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/latishab/libdc-swift", from: "1.0.0")
]
```

## Quick Start

Before interacting with any dive computer features, set up the shared dive computer context. Once connected to a device (using, for example, `DeviceConfiguration.openBLEDevice(name:deviceAddress:)`), you can retrieve dive logs using the `DiveLogRetriever` class. The following snippet demonstrates a simplified SwiftUI integration:

```swift
import SwiftUI
import CoreBluetooth
import LibDCSwift

struct ConnectedDeviceView: View {
    let device: CBPeripheral
    @ObservedObject var bluetoothManager: CoreBluetoothManager
    @ObservedObject var diveViewModel: DiveDataViewModel

    var body: some View {
        VStack {
            // UI elements showing device info and dive logs...
            Button("Get Dive Logs") {
                retrieveDiveLogs()
            }
            if bluetoothManager.isRetrievingLogs {
                ProgressView("Downloading...")
            }
        }
    }
    
    private func retrieveDiveLogs() {
        // Ensure we have a valid device pointer
        guard let devicePtr = bluetoothManager.openedDeviceDataPtr else {
            print("❌ Device not connected")
            return
        }
        
        bluetoothManager.isRetrievingLogs = true
        bluetoothManager.currentRetrievalDevice = device
        
        DiveLogRetriever.retrieveDiveLogs(
            from: devicePtr,
            device: device,
            viewModel: diveViewModel,
            bluetoothManager: bluetoothManager,
            onProgress: { current, total in
                // Throttle and update progress (e.g., update a progress bar or Live Activity)
                DispatchQueue.main.async {
                    diveViewModel.updateProgress(count: current + 1)
                }
            },
            completion: { success in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Dive logs successfully retrieved!")
                    } else {
                        print("❌ Failed to retrieve dive logs.")
                    }
                    bluetoothManager.clearRetrievalState()
                }
            }
        )
    }
}
```

## Device Configuration & Dive Log Retrieval

The framework is built around two core classes:

- **DeviceConfiguration:**  
  Provides functionality to:
  - Retrieve known BLE service UUIDs for device discovery.
  - Connect to dive computers using stored configuration or descriptor-based identification.
  - Create parsers for dive data based on the device family and model.

- **DiveLogRetriever:**  
  Handles the retrieval of dive logs from a connected dive computer. It leverages:
  - A C-compatible callback mechanism to process individual dive logs.
  - Progress updates (which can be used to update the UI in real time).
  - Integration with background tasks and Live Activities (on iOS) to keep the download process alive even when the app is in the background.

For example, your production code in `ConnectedDeviceView.swift` demonstrates:
- Checking and displaying device info.
- Initiating a dive log download upon user action.
- Updating the UI with progress and handling errors.
- Integrating with background execution and Live Activity updates for a smoother user experience.

## Supported Devices

LibDC-Swift supports all dive computer brands with BLE connectivity as defined by [libdivecomputer](https://www.libdivecomputer.org/). Some supported families include:

- Suunto EON Steel/Core
- Shearwater Perdix/Teric
- Mares Icon HD
- Pelagic i330R/DSX
- ...and more (see code documentation for the complete list)

## Documentation

For complete documentation, advanced usage examples, and further integration details, please visit our [Wiki](wiki-link). Topics include:

- Detailed setup and configuration
- Advanced usage scenarios and error handling
- Logging and progress tracking mechanisms
- Contribution guidelines

## Contributing

Contributions are welcome! Please see our [Contributing Guide](CONTRIBUTING.md) for more information.

## License

This project is licensed under the GNU Lesser General Public License v2.1 – see the [LICENSE](LICENSE) file for details.

## Acknowledgments

LibDC-Swift builds upon [libdivecomputer](https://www.libdivecomputer.org/), providing Swift bindings and additional functionality to power modern iOS and macOS applications.
