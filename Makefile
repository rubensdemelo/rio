.PHONY: clean test build verify-signing verify-keychain-access verify-system-audio-capture final

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
XCODEBUILD_BASE_FLAGS = -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
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

verify-signing:
ifeq ($(LOCAL_SIGNED),YES)
	@echo "Verifying the stable development signature..."
	@codesign -dv --verbose=4 $(RIO_APP_PATH) 2>&1 | grep -Fq -e 'Authority=Apple Development:' -e 'Authority=Mac Development:'
	@codesign -d --entitlements - $(RIO_APP_PATH) 2>&1 | grep -Fq '.com.rubensmelo.rio'
else
	@echo "Verifying the local ad-hoc signature..."
	@codesign -dv --verbose=4 $(RIO_APP_PATH) 2>&1 | grep -Fq 'Signature=adhoc'
endif

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

final:
	@$(MAKE) test
	@$(MAKE) build
	@$(MAKE) verify-signing
	@$(MAKE) verify-keychain-access

ifeq ($(LOCAL_SIGNED),YES)
	@pkill -x Rio 2>/dev/null || true
	@echo "Launching Rio..."
	@open -n $(RIO_APP_PATH)
else
	@echo "Unsigned validation complete; Rio was not stopped or launched."
endif
