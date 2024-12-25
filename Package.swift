// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LibDCSwift",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "LibDCSwift",
            targets: ["LibDCSwift"]
        ),
        .library(
            name: "LibDCBridge",
            targets: ["LibDCBridge"]
        )
    ],
    targets: [
        .target(
            name: "Clibdivecomputer",
            path: "libdivecomputer",
            exclude: [
                "doc",
                "m4",
                "src/libdivecomputer.rc",
                "src/libdivecomputer.symbols",
                "src/Makefile.am"
            ],
            sources: ["src"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("."),
                .headerSearchPath("include"),
                .headerSearchPath("include/libdivecomputer"),
                .headerSearchPath("src"),
                .define("HAVE_CONFIG_H"),
                .define("PACKAGE", to: "libdivecomputer"),
                .define("VERSION", to: "0.8.0"),
                .unsafeFlags(["-fmodules"])
            ],
            linkerSettings: [
                .linkedLibrary("divecomputer")
            ]
        ),
        .target(
            name: "LibDCBridge",
            dependencies: ["Clibdivecomputer"],
            path: "Sources/LibDCBridge",
            sources: ["src/configuredc.c", "src/BLEBridge.m"],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .headerSearchPath("../../libdivecomputer/include"),
                .headerSearchPath("../../libdivecomputer/src"),
                .define("HAVE_CONFIG_H"),
                .unsafeFlags(["-fmodules"])
            ],
            linkerSettings: [
                .linkedLibrary("divecomputer")
            ]
        ),
        .target(
            name: "LibDCSwift",
            dependencies: ["LibDCBridge", "Clibdivecomputer"],
            path: "Sources/LibDCSwift",
            sources: [
                "Logger.swift",
                "BLEManager.swift",
                "Models/DeviceConfiguration.swift",
                "Models/DiveData.swift",
                "ViewModels/DiveDataViewModel.swift",
                "Parser/"
            ],
            cSettings: [
                .headerSearchPath("../LibDCBridge/include"),
                .headerSearchPath("../../libdivecomputer/include")
            ]
        )
    ]
) 
