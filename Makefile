.PHONY: clean test build install verify-keychain-access verify-system-audio-capture final

PROJECT = Rio.xcodeproj
SCHEME = Rio
CONFIGURATION = Debug
DESTINATION = platform=macOS
LOCAL_SIGNED ?= YES
CAPTURE_CYCLES ?= 2
CAPTURE_SECONDS ?= 3

ifeq ($(LOCAL_SIGNED),YES)
DERIVED_DATA_PATH = .build/Iteration
else
DERIVED_DATA_PATH = .build/UnsignedValidation
endif
RIO_APP_PATH = $(DERIVED_DATA_PATH)/Build/Products/Debug/Rio.app
XCODEBUILD_BASE_FLAGS = -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) -arch arm64 SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS)

ifneq ($(wildcard Config/Development.xcconfig),)
XCODEBUILD_FLAGS += -xcconfig Config/Development.xcconfig
endif

ifeq ($(LOCAL_SIGNED),YES)
TEST_XCODEBUILD_FLAGS = $(XCODEBUILD_FLAGS) -allowProvisioningUpdates
BUILD_XCODEBUILD_FLAGS = $(XCODEBUILD_FLAGS) -allowProvisioningUpdates
else
TEST_XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS) CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
BUILD_XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS) CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- CODE_SIGN_ENTITLEMENTS=
endif

clean:
	@rm -rf .build 2>/dev/null || true

test:
	@echo "Running the complete test suite..."
	@xcodebuild $(TEST_XCODEBUILD_FLAGS) test

build:
	@echo "Building the application..."
	@xcodebuild $(BUILD_XCODEBUILD_FLAGS) build

verify-keychain-access:
ifeq ($(LOCAL_SIGNED),YES)
	@echo "Verifying built-app Keychain access..."
	@scripts/verify-keychain-access.sh $(RIO_APP_PATH)
else
	@echo "Skipping built-app Keychain verification for the ad-hoc local build."
endif

verify-system-audio-capture:
	@scripts/verify-system-audio-capture.sh \
		$(RIO_APP_PATH) \
		$(CAPTURE_CYCLES) \
		$(CAPTURE_SECONDS)

ifeq ($(LOCAL_SIGNED),YES)
install: build
	@scripts/install-rio.sh "$(RIO_APP_PATH)"
else
install:
	@echo "Installation requires the stable signed Debug build. Run make install without LOCAL_SIGNED=NO." >&2
	@exit 1
endif

final:
	@$(MAKE) test
ifeq ($(LOCAL_SIGNED),YES)
	@$(MAKE) install
else
	@$(MAKE) build
	@echo "Unsigned validation complete; Rio was not stopped or launched."
endif
