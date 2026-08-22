.PHONY: clean test build final

PROJECT = Rio.xcodeproj
SCHEME = Rio
CONFIGURATION = Debug
DESTINATION = platform=macOS
DERIVED_DATA_PATH = .build/Iteration
XCODEBUILD_BASE_FLAGS = -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(DESTINATION)' -derivedDataPath $(DERIVED_DATA_PATH) SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
XCODEBUILD_FLAGS = $(XCODEBUILD_BASE_FLAGS)

# Prefer the full development identity Xcode has installed. On current Xcode
# versions this may be named Apple Development rather than Mac Development.
DEVELOPMENT_IDENTITY := $(shell security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(\(Apple\|Mac\) Development: [^"]*\)".*/\1/p' | head -n 1)

ifneq ($(strip $(DEVELOPMENT_IDENTITY)),)
STABLE_SIGNING_FLAGS = $(XCODEBUILD_FLAGS) CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY='$(DEVELOPMENT_IDENTITY)' DEVELOPMENT_TEAM=X59V2Q7WB7
TEST_XCODEBUILD_FLAGS = $(STABLE_SIGNING_FLAGS)
BUILD_XCODEBUILD_FLAGS = $(STABLE_SIGNING_FLAGS)
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
	@open -n .build/Iteration/Build/Products/Debug/Rio.app
