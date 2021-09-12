#!/usr/bin/env bash

set -e

function requireEnvVar() {
    local envVar="$1"

    if [[ -z "${!envVar}" ]]; then
        echo "$envVar is a required environment variable, but is not set"
        exit 1
    fi
}

requireEnvVar MATRIX_EMBEDDER
requireEnvVar MATRIX_OS

# === Constants ===============================================================

testResultsDir="test-results"
standaloneTestsPackage="packages/cbl_e2e_tests_standalone_dart"
cblFlutterExamplePackage="packages/cbl_flutter/example"
testAppBundleId="com.terwesten.gabriel.cblFlutterExample"

# === Steps ===================================================================

function buildNativeLibraries() {
    cd native/tools

    case "$MATRIX_OS" in
    iOS)
        ./build_apple.sh build ios_simulator Debug
        ;;
    macOS)
        ./build_apple.sh build macos Debug
        ;;
    Android)
        ./build_android.sh build Debug
        ;;
    Ubuntu)
        ./build_unix.sh build Debug
        ;;
    esac
}

function configureFlutter() {
    case "$MATRIX_OS" in
    macOS)
        flutter config --enable-macos-desktop
        ;;
    Ubuntu)
        flutter config --enable-linux-desktop
        ;;
    esac
}

function bootstrapPackages() {
    case "$MATRIX_EMBEDDER" in
    standalone)
        melos bootstrap --scope cbl_e2e_tests_standalone_dart
        ;;
    flutter)
        # `flutter pub get` creates some files which `melos bootstrap` doesn't.
        melos exec --scope cbl_flutter_example -- flutter pub get
        melos bootstrap --scope cbl_flutter_example
        ;;
    esac
}

function startVirtualDevices() {
    case "$MATRIX_OS" in
    iOS)
        ./tool/apple-simulator.sh start -o iOS-14-5 -d 'iPhone 12'
        ;;
    Android)
        ./tool/android-emulator.sh createAndStart -a 22 -d pixel_4
        ./tool/android-emulator.sh setupReversePort 4984
        ./tool/android-emulator.sh setupReversePort 4985
        ;;
    Ubuntu)
        Xvfb :99 &
        echo "DISPLAY=:99" >>$GITHUB_ENV
        ;;
    esac
}

function runE2ETests() {
    case "$MATRIX_EMBEDDER" in
    standalone)
        cd packages/cbl_e2e_tests_standalone_dart

        export ENABLE_TIME_BOMB=true
        testCommand="dart test -r expanded -j 1"

        case "$MATRIX_OS" in
        macOS)
            # The tests are run with sudo, so that macOS records crash reports.
            sudo $testCommand
            ;;
        Ubuntu)
            # Enable core dumps.
            ulimit -c unlimited
            $testCommand
            ;;
        esac
        ;;
    flutter)
        cd packages/cbl_flutter/example

        device=""
        case "$MATRIX_OS" in
        iOS)
            device="iPhone"
            ;;
        macOS)
            device="macOS"
            ;;
        Android)
            device="Android"
            ;;
        Ubuntu)
            # Enable core dumps.
            ulimit -c unlimited
            device="Linux"
            ;;
        esac

        flutter drive \
            --no-pub \
            -d "$device" \
            --dart-define enableTimeBomb=true \
            --keep-app-running \
            --driver test_driver/integration_test.dart \
            --target integration_test/cbl_e2e_test.dart
        ;;
    esac
}

function _collectFlutterIntegrationResponseData() {
    echo "Collecting Flutter integration test response data"

    local integrationResponseData="$cblFlutterExamplePackage/build/integration_response_data"

    if [ ! -e "$integrationResponseData" ]; then
        echo "Did not find data"
        return 0
    fi

    echo "Copying data..."
    cp -a "$integrationResponseData" "$testResultsDir"
    echo "Copied data"
}

function _collectCrashReportsMacOS() {
    # Crash reports are generated by the OS.
    echo "Copying macOS DiagnosticReports..."
    cp -a ~/Library/Logs/DiagnosticReports "$testResultsDir"
    echo "Copied macOS DiagnosticReports"
}

function _collectCrashReportsLinuxStandalone() {
    ./tool/create-crash-report-linux.sh \
        -e "$(which dart)" \
        -c "$standaloneTestsPackage/core" \
        -o "$testResultsDir"
}

function _collectCrashReportsLinuxFlutter() {
    ./tool/create-crash-report-linux.sh \
        -e "$cblFlutterExamplePackage/build/linux/x64/debug/bundle/cbl_flutter_example" \
        -c "$cblFlutterExamplePackage/core" \
        -o "$testResultsDir"
}

function _collectCrashReportsAndroid() {
    ./tool/android-emulator.sh bugreport -o "$testResultsDir"
}

function _collectCblLogsStandalone() {
    echo "Collecting Couchbase Lite logs"

    local cblLogsDir="$standaloneTestsPackage/test/.tmp/logs"

    if [ ! -e "$cblLogsDir" ]; then
        echo "Did not find logs"
        return 0
    fi

    echo "Copying files..."
    cp -a "$cblLogsDir" "$testResultsDir"
    echo "Copied files"
}

function _collectCblLogsIosSimulator() {
    echo "Collecting Couchbase Lite logs from iOS Simulator app"

    ./tool/apple-simulator.sh copyData \
        -o iOS-14-5 \
        -d "iPhone 12" \
        -b "$testAppBundleId" \
        -f "Library/Caches/cbl_flutter/logs" \
        -t "$testResultsDir"
}

function _collectCblLogsMacOS() {
    echo "Collecting Couchbase Lite logs from macOS app"

    local appDataContainer="~/Library/Containers/$testAppBundleId/Data"
    local cblLogsDir="$appDataContainer/Library/Caches/cbl_flutter/logs"

    if [ ! -e "$cblLogsDir" ]; then
        echo "Did not find logs"
        return 0
    fi

    echo "Copying files..."
    cp -a "$cblLogsDir" "$testResultsDir"
    echo "Copied files"
}

function collectTestResults() {
    mkdir "$testResultsDir"

    # Wait for crash reports/core dumps.
    sleep 60

    case "$MATRIX_EMBEDDER" in
    standalone)
        case "$MATRIX_OS" in
        macOS)
            _collectCrashReportsMacOS
            _collectCblLogsStandalone
            ;;
        Ubuntu)
            _collectCrashReportsLinuxStandalone
            _collectCblLogsStandalone
            ;;
        esac
        ;;
    flutter)
        _collectFlutterIntegrationResponseData

        case "$MATRIX_OS" in
        macOS)
            _collectCrashReportsMacOS
            _collectCblLogsMacOS
            ;;
        iOS)
            _collectCrashReportsMacOS
            _collectCblLogsIosSimulator
            ;;
        Android)
            _collectCrashReportsAndroid
            # TODO get cbl logs from device
            ;;
        Ubuntu)
            _collectCrashReportsLinuxFlutter
            # TODO get cbl logs from device
            ;;
        esac
        ;;
    esac
}

"$@"