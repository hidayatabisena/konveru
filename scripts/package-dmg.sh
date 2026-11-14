#!/bin/bash

set -euo pipefail

readonly SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
readonly PROJECT_PATH="${PROJECT_DIRECTORY}/Konveru.xcodeproj"
readonly SCHEME="Konveru"
readonly APP_NAME="Konveru"
readonly ARCHITECTURE="arm64"
readonly OUTPUT_DIRECTORY="${PROJECT_DIRECTORY}/dist"

temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/konveru-release.XXXXXX")"
readonly temporary_directory

cleanup() {
    rm -rf "${temporary_directory}"
}
trap cleanup EXIT

readonly build_directory="${temporary_directory}/Build"
readonly staging_directory="${temporary_directory}/DMG"
readonly app_path="${build_directory}/${APP_NAME}.app"

echo "Building ${APP_NAME} for ${ARCHITECTURE}..."
xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination "platform=macOS,arch=${ARCHITECTURE}" \
    -derivedDataPath "${temporary_directory}/DerivedData" \
    CONFIGURATION_BUILD_DIR="${build_directory}" \
    ARCHS="${ARCHITECTURE}" \
    ONLY_ACTIVE_ARCH=YES \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    DEVELOPMENT_TEAM="" \
    build

if [[ ! -d "${app_path}" ]]; then
    echo "error: Build succeeded but ${app_path} was not found." >&2
    exit 1
fi

echo "Applying an ad-hoc signature..."
codesign \
    --force \
    --deep \
    --sign - \
    --options runtime \
    --timestamp=none \
    "${app_path}"

codesign --verify --deep --strict --verbose=2 "${app_path}"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${app_path}/Contents/Info.plist")"
readonly version
readonly dmg_name="${APP_NAME}-${version}-${ARCHITECTURE}.dmg"
readonly dmg_path="${OUTPUT_DIRECTORY}/${dmg_name}"

mkdir -p "${staging_directory}" "${OUTPUT_DIRECTORY}"
ditto "${app_path}" "${staging_directory}/${APP_NAME}.app"
ln -s /Applications "${staging_directory}/Applications"

echo "Creating ${dmg_name}..."
rm -f "${dmg_path}"
hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${staging_directory}" \
    -format UDZO \
    -ov \
    "${dmg_path}"

hdiutil verify "${dmg_path}"

echo
echo "Created: ${dmg_path}"
echo "SHA-256: $(shasum -a 256 "${dmg_path}" | awk '{print $1}')"
echo
echo "This DMG is ad-hoc signed and is not notarized."
echo "On another Mac, Gatekeeper may require Control-clicking the app and choosing Open."
