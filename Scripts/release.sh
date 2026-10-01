#!/bin/zsh
# Builds HyperKeys.zip for a GitHub release: a universal Release build signed with
# Developer ID, notarized by Apple and stapled.
#
#   Scripts/release.sh                       # build, sign, notarize, staple, zip
#   SKIP_NOTARIZE=1 Scripts/release.sh       # signed build only, to check things locally
#   NOTARY_PROFILE=other Scripts/release.sh  # a different notarytool keychain profile
#
# One-time setup for notarizing (Apple ID, team WYY7PK57DM, an app-specific password):
#   xcrun notarytool store-credentials hyperkeys
#
# The version comes from MARKETING_VERSION in Config/Shared.xcconfig. Output goes to build/release.
set -euo pipefail

ROOT=${0:A:h:h}
OUT="$ROOT/build/release"
DERIVED="$ROOT/build/DerivedData"
PROFILE=${NOTARY_PROFILE:-hyperkeys}
TEAM=WYY7PK57DM
VERSION=$(awk -F' = ' '/^MARKETING_VERSION/ { print $2 }' "$ROOT/Config/Shared.xcconfig")
APP="$OUT/HyperKeys.app"
ZIP="$OUT/HyperKeys.zip"

rm -rf "$OUT"
mkdir -p "$OUT"

echo "› Building HyperKeys $VERSION"
xcodebuild build \
  -workspace "$ROOT/HyperKeys.xcworkspace" \
  -scheme HyperKeys \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -quiet \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM=$TEAM

ditto "$DERIVED/Build/Products/Release/HyperKeys.app" "$APP"

echo "› Checking the signature"
codesign --verify --deep --strict "$APP"
codesign --display --verbose=2 "$APP" 2>&1 | grep -E '^(Authority=Developer ID Application|Runtime Version|Timestamp)'
lipo -archs "$APP/Contents/MacOS/HyperKeys"

ditto -c -k --keepParent "$APP" "$ZIP"

if [[ -z ${SKIP_NOTARIZE:-} ]]; then
  echo "› Notarizing (this usually takes a few minutes)"
  result=$(xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait --output-format json)
  notary_status=$(plutil -extract status raw -o - - <<< "$result")
  if [[ $notary_status != Accepted ]]; then
    echo "Notarization finished with status: $notary_status" >&2
    echo "Details: xcrun notarytool log $(plutil -extract id raw -o - - <<< "$result") --keychain-profile $PROFILE" >&2
    exit 1
  fi

  xcrun stapler staple "$APP"
  rm "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  spctl --assess --type execute --verbose=2 "$APP"
else
  echo "› Skipped notarizing (SKIP_NOTARIZE is set)"
fi

SHA=$(shasum -a 256 "$ZIP" | awk '{ print $1 }')
echo "$SHA" > "$ZIP.sha256"

echo
echo "HyperKeys $VERSION → $ZIP"
echo "sha256 $SHA"
