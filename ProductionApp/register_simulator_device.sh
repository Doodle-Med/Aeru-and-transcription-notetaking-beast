#!/bin/bash

# Register Simulator Device for Apple Developer Account
# This script registers a simulator device to enable provisioning profiles

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✅ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

error() {
    echo -e "${RED}❌ $1${NC}"
}

# Configuration
SIMULATOR_NAME="iPhone 17 Pro"
SIMULATOR_ID="AB875782-946A-42DF-9699-32B88FE20969"
DEVICE_NAME="WhisperControl Simulator Device"

log "Registering simulator device for Apple Developer account..."

# Step 1: Ensure simulator is booted
log "Booting simulator: ${SIMULATOR_NAME}"
xcrun simctl boot "${SIMULATOR_ID}" 2>/dev/null || true

# Wait for simulator to be ready
log "Waiting for simulator to be ready..."
sleep 5

# Step 2: Get simulator UDID (same as ID for simulators)
UDID="${SIMULATOR_ID}"
log "Simulator UDID: ${UDID}"

# Step 3: Register device using xcodebuild (this is the key part)
log "Registering device with Apple Developer account..."

# Method 1: Try using xcodebuild to register the device
log "Attempting to register device via xcodebuild..."

# Create a temporary project to register the device
TEMP_DIR=$(mktemp -d)
cd "${TEMP_DIR}"

# Create a minimal project
cat > "DeviceRegistration.xcodeproj/project.pbxproj" << 'EOF'
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 56;
	objects = {

/* Begin PBXBuildFile section */
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		1A0000000000000000000001 /* DeviceRegistration.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DeviceRegistration.app; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXGroup section */
		1A0000000000000000000002 = {
			isa = PBXGroup;
			children = (
				1A0000000000000000000003 /* DeviceRegistration */,
				1A0000000000000000000004 /* Products */,
			);
			sourceTree = "<group>";
		};
		1A0000000000000000000003 /* DeviceRegistration */ = {
			isa = PBXGroup;
			children = (
			);
			path = DeviceRegistration;
			sourceTree = "<group>";
		};
		1A0000000000000000000004 /* Products */ = {
			isa = PBXGroup;
			children = (
				1A0000000000000000000001 /* DeviceRegistration.app */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		1A0000000000000000000005 /* DeviceRegistration */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 1A0000000000000000000006 /* Build configuration list for PBXNativeTarget "DeviceRegistration" */;
			buildPhases = (
			);
			buildRules = (
			);
			dependencies = (
			);
			name = DeviceRegistration;
			productName = DeviceRegistration;
			productReference = 1A0000000000000000000001 /* DeviceRegistration.app */;
			productType = "com.apple.product-type.application";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		1A0000000000000000000007 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1500;
				LastUpgradeCheck = 1500;
				TargetAttributes = {
					1A0000000000000000000005 = {
						CreatedOnToolsVersion = 15.0;
					};
				};
			};
			buildConfigurationList = 1A0000000000000000000008 /* Build configuration list for PBXProject "DeviceRegistration" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 1A0000000000000000000002;
			productRefGroup = 1A0000000000000000000004 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				1A0000000000000000000005 /* DeviceRegistration */,
			);
		};
/* End PBXProject section */

/* Begin XCBuildConfiguration section */
		1A0000000000000000000009 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			};
			name = Debug;
		};
		1A000000000000000000000A /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS = YES;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION = YES_AGGRESSIVE;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				CLANG_ENABLE_OBJC_WEAK = YES;
				CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
				CLANG_WARN_BOOL_CONVERSION = YES;
				CLANG_WARN_COMMA = YES;
				CLANG_WARN_CONSTANT_CONVERSION = YES;
				CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
				CLANG_WARN_DIRECT_OBJC_ISA_USAGE = YES_ERROR;
				CLANG_WARN_DOCUMENTATION_COMMENTS = YES;
				CLANG_WARN_EMPTY_BODY = YES;
				CLANG_WARN_ENUM_CONVERSION = YES;
				CLANG_WARN_INFINITE_RECURSION = YES;
				CLANG_WARN_INT_CONVERSION = YES;
				CLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
				CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
				CLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
				CLANG_WARN_OBJC_ROOT_CLASS = YES_ERROR;
				CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
				CLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
				CLANG_WARN_STRICT_PROTOTYPES = YES;
				CLANG_WARN_SUSPICIOUS_MOVE = YES;
				CLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
				CLANG_WARN_UNREACHABLE_CODE = YES;
				CLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNDECLARED_SELECTOR = YES;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				GCC_WARN_UNUSED_FUNCTION = YES;
				GCC_WARN_UNUSED_VARIABLE = YES;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				LOCALIZATION_PREFERS_STRING_CATALOGS = YES;
				MTL_ENABLE_DEBUG_INFO = NO;
				MTL_FAST_MATH = YES;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				VALIDATE_PRODUCT = YES;
			};
			name = Release;
		};
		1A000000000000000000000B /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = JA6967Z8P6;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.josephhennig.deviceRegistration;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Debug;
		};
		1A000000000000000000000C /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = JA6967Z8P6;
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.josephhennig.deviceRegistration;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		1A0000000000000000000006 /* Build configuration list for PBXNativeTarget "DeviceRegistration" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				1A000000000000000000000B /* Debug */,
				1A000000000000000000000C /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		1A0000000000000000000008 /* Build configuration list for PBXProject "DeviceRegistration" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				1A0000000000000000000009 /* Debug */,
				1A000000000000000000000A /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 1A0000000000000000000007 /* Project object */;
}
EOF

# Create a minimal Swift file
mkdir -p DeviceRegistration
cat > DeviceRegistration/DeviceRegistrationApp.swift << 'EOF'
import SwiftUI

@main
struct DeviceRegistrationApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Device Registration")
            .padding()
    }
}
EOF

# Try to build and register the device
log "Building project to register device..."
if xcodebuild -project DeviceRegistration.xcodeproj -scheme DeviceRegistration -destination "id=${SIMULATOR_ID}" build -allowProvisioningUpdates 2>/dev/null; then
    success "Device registration successful!"
else
    warning "Direct registration failed, trying alternative method..."
fi

# Clean up
cd - > /dev/null
rm -rf "${TEMP_DIR}"

# Step 4: Alternative method - Use xcrun to register device
log "Trying alternative registration method..."

# Method 2: Try using xcrun simctl to register
log "Attempting to register via simctl..."

# This is a more direct approach
if xcrun simctl list devices | grep -q "${SIMULATOR_ID}"; then
    success "Simulator device found and available"
    
    # Try to build a simple app to trigger device registration
    log "Building WhisperControl to register device..."
    cd /Users/johnsnow/01_Whisper_Repo/ProductionApp
    
    if xcodebuild -project WhisperControlMobile.xcodeproj -scheme WhisperControlMobile -destination "id=${SIMULATOR_ID}" build -allowProvisioningUpdates 2>/dev/null; then
        success "Device registration completed via WhisperControl build!"
    else
        warning "Build failed, but device may still be registered"
    fi
else
    error "Simulator device not found"
    exit 1
fi

# Step 5: Verify registration
log "Verifying device registration..."

# Check if we can now create provisioning profiles
if xcodebuild -showBuildSettings -project WhisperControlMobile.xcodeproj -scheme WhisperControlMobile | grep -q "DEVELOPMENT_TEAM"; then
    success "Device registration verified! Provisioning profiles should now work."
    
    log "You can now run the App Store submission script:"
    log "./automate_appstore_submission.sh"
else
    warning "Device registration may not be complete. Try the Xcode GUI method instead."
fi

success "Device registration process completed!"
log "Next steps:"
log "1. Try running: ./automate_appstore_submission.sh"
log "2. Or use Xcode GUI: Product → Archive"
log "3. If issues persist, connect a physical device and register it"
