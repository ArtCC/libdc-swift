// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LibDCSwift",
    platforms: [
        .iOS(.v17)
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
                "m4"
            ],
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include/libdivecomputer"),
                .headerSearchPath("src")
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
                .headerSearchPath("../libdivecomputer/include"),
                .headerSearchPath("../libdivecomputer/src"),
                .define("HAVE_CONFIG_H")
            ],
            swiftSettings: [
                .define("PRODUCT_MODULE_NAME=libdc_swift")
            ]
        ),
        .target(
            name: "LibDCSwift",
            dependencies: ["LibDCBridge", "Clibdivecomputer"],
            path: "Sources/LibDCSwift",
            swiftSettings: [
                .unsafeFlags(["-import-objc-header", "Sources/LibDCBridge/include/libdcswift-bridging-header.h"])
            ]
        )
    ]
) 
