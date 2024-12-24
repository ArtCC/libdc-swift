#!/bin/sh

#  build-xcframework.sh
#  BLETest
#
#  Created by User on 24/12/2024.
#

#!/bin/bash

# Build libdivecomputer for various architectures and create XCFramework
LIBDC_VERSION="0.8.0"
BUILD_DIR="build"
FRAMEWORK_NAME="libdivecomputer"

# Create build directory
mkdir -p $BUILD_DIR

# Build for iOS
xcodebuild -create-xcframework \
  -library "lib/$FRAMEWORK_NAME.a" \
  -headers "include" \
  -output "$BUILD_DIR/$FRAMEWORK_NAME.xcframework"
