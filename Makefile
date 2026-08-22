.PHONY: clean test build verify-signing verify-keychain-access final

PROJECT = Rio.xcodeproj
SCHEME = Rio
CONFIGURATION = Debug
DESTINATION = platform=macOS
DERIVED_DATA_PATH = .build/Iteration
XCODEBUILD_BASE_FLAGS = -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS)

ifneq ($(wildcard Config/Development.xcconfig),)
XCODEBUILD_FLAGS += -xcconfig Config/Development.xcconfig
TEST_XCODEBUILD_FLAGS = $(XCODEBUILD_FLAGS) -allowProvisioningUpdates
BUILD_XCODEBUILD_FLAGS = $(XCODEBUILD_FLAGS) -allowProvisioningUpdates
else
# A checkout without local development signing configuration may still run its
# tests and build an ad-hoc app. `make final` rejects that artifact before launch.
TEST_XCODEBUILD_FLAGS = $(XCODEBUILD_FLAGS) CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
BUILD_XCODEBUILD_FLAGS = $(XCODEBUILD_FLAGS) CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
endif

clean:
	@rm -rf .build 2>/dev/null || true

test:
	@echo "Running the complete test suite..."
	@xcodebuild $(TEST_XCODEBUILD_FLAGS) test

build:
	@echo "Building the application..."
	@xcodebuild $(BUILD_XCODEBUILD_FLAGS) build

verify-signing:
ifneq ($(wildcard Config/Development.xcconfig),)
	@echo "Verifying the stable development signature..."
	@codesign -dv --verbose=4 .build/Iteration/Build/Products/Debug/Rio.app 2>&1 | grep -Fq -e 'Authority=Apple Development:' -e 'Authority=Mac Development:'
	@codesign -d --entitlements - .build/Iteration/Build/Products/Debug/Rio.app 2>&1 | grep -Fq '.com.rio.app'
endif

verify-keychain-access:
	@echo "Verifying built-app Keychain access..."
	@scripts/verify-keychain-access.sh .build/Iteration/Build/Products/Debug/Rio.app

final:
	@pkill -x Rio 2>/dev/null || true
	@$(MAKE) test
	@$(MAKE) build
	@$(MAKE) verify-signing
	@$(MAKE) verify-keychain-access
	@echo "Launching Rio..."
	@open -n .build/Iteration/Build/Products/Debug/Rio.app
