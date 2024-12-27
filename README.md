# LibDC-Swift

A Swift framework for communicating with dive computers via Bluetooth Low Energy (BLE). Built on top of libdivecomputer, this package provides a modern Swift API for iOS and macOS applications to interact with various dive computers.

## Features

- 🔍 BLE device scanning and management
- 📱 Support for Suunto and Shearwater dive computers
- 📥 Efficient dive log retrieval with fingerprint system
- 📊 Comprehensive dive data parsing
- 🛠 Built-in error handling and logging
- 📈 Progress tracking for long operations

## Requirements

- iOS 15.0+ / macOS 12.0+
- Swift 5.10+
- Xcode 15.0+

## Installation

Add LibDC-Swift to your project using Swift Package Manager:

```swift
dependencies: [
    .package(url: "your-repo-url/LibDC-Swift.git", from: "1.0.0")
]
```

## Quick Start

```swift
import LibDCSwift

// Initialize and start scanning
let manager = CoreBluetoothManager.shared
manager.startScanning()

// Connect to a device
let success = DeviceConfiguration.openBLEDevice(
    name: deviceName,
    deviceAddress: deviceUUID
)

// Retrieve dive logs
let viewModel = DiveDataViewModel()
DiveLogRetriever.retrieveDiveLogs(
    from: devicePtr,
    deviceName: name,
    viewModel: viewModel
) { success in
    if success {
        // Handle retrieved dive logs
    }
}
```

## Supported Devices

### Suunto
- EON Steel / Black
- EON Core
- D5

### Shearwater
- Petrel / Petrel 2 / Petrel 3
- Perdix / Perdix AI
- NERD / NERD 2
- Teric
- Peregrine

## Documentation

For detailed documentation, please visit our [Wiki](wiki-link).

Key topics covered in the wiki:
- Detailed setup and configuration
- Advanced usage examples
- Data structures and handling
- Error handling strategies
- Logging system
- Contribution guidelines

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details.

## License

This project is licensed under the GNU Lesser General Public License v2.1 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

This project builds upon [libdivecomputer](https://libdivecomputer.org/), providing Swift bindings and additional functionality for iOS and macOS applications.
