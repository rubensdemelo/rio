.PHONY: clean test build final

PROJECT = Rio.xcodeproj
SCHEME = Rio
CONFIGURATION = Debug
DESTINATION = platform=macOS
DERIVED_DATA_PATH = .build/Iteration
XCODEBUILD_BASE_FLAGS = -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS)

# Xcode's Run action can use ad-hoc "Sign to Run Locally" signing when the
# account exposes only the unified Apple Development certificate. Prefer a
# real Mac Development identity when one is installed, but keep `make final`
# usable with the same local fallback as Xcode.
HAS_MAC_DEVELOPMENT_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | grep -q '"Mac Development:' && echo YES || echo NO)

ifeq ($(HAS_MAC_DEVELOPMENT_IDENTITY),YES)
TEST_XCODEBUILD_FLAGS = $(XCODEBUILD_FLAGS)
BUILD_XCODEBUILD_FLAGS = $(XCODEBUILD_FLAGS)
else
TEST_XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS) CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
BUILD_XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS) CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=-
endif

ifneq ($(wildcard Config/Development.xcconfig),)
XCODEBUILD_FLAGS += -xcconfig Config/Development.xcconfig
endif

clean:
	@rm -rf .build 2>/dev/null || true

test:
	@echo "Running the complete test suite..."
	@xcodebuild $(TEST_XCODEBUILD_FLAGS) test

build:
	@echo "Building the application..."
	@xcodebuild $(BUILD_XCODEBUILD_FLAGS) build

final:
	@pkill -x Rio 2>/dev/null || true
	@$(MAKE) test
	@$(MAKE) build
	@echo "Launching Rio..."
	@.build/Iteration/Build/Products/Debug/Rio.app/Contents/MacOS/Rio >/dev/null 2>&1 &
