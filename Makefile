.PHONY: clean test build verify-signing final

PROJECT = Rio.xcodeproj
SCHEME = Rio
CONFIGURATION = Debug
DESTINATION = platform=macOS
DERIVED_DATA_PATH = .build/Iteration
XCODEBUILD_BASE_FLAGS = -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS)

# Prefer the full development identity Xcode has installed. On current Xcode
# versions this may be named Apple Development rather than Mac Development.
DEVELOPMENT_IDENTITY_HASH := $(shell security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:|"Mac Development:/ { print $$2; exit }')

ifneq ($(strip $(DEVELOPMENT_IDENTITY_HASH)),)
STABLE_SIGNING_FLAGS = $(XCODEBUILD_FLAGS) -allowProvisioningUpdates
TEST_XCODEBUILD_FLAGS = $(STABLE_SIGNING_FLAGS)
BUILD_XCODEBUILD_FLAGS = $(STABLE_SIGNING_FLAGS)
else
TEST_XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS) CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
BUILD_XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS) CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
endif

ifneq ($(wildcard Config/Development.xcconfig),)
XCODEBUILD_FLAGS += -xcconfig Config/Development.xcconfig
ifeq ($(strip $(DEVELOPMENT_IDENTITY_HASH)),)
$(error Config/Development.xcconfig exists, but no Apple or Mac Development signing identity is available)
endif
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

final:
	@pkill -x Rio 2>/dev/null || true
	@$(MAKE) test
	@$(MAKE) build
	@$(MAKE) verify-signing
	@echo "Launching Rio..."
	@open -n .build/Iteration/Build/Products/Debug/Rio.app
