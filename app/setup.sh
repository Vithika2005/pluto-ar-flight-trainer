#!/usr/bin/env bash
# One-time setup for the Flutter iOS project. Run on a Mac with Flutter + Xcode installed:
#   cd app && ./setup.sh
set -euo pipefail
cd "$(dirname "$0")"

command -v flutter >/dev/null || { echo "Flutter is not installed or not on PATH."; exit 1; }
[ "$(uname)" = "Darwin" ] || { echo "iOS builds need macOS + Xcode."; exit 1; }

if [ ! -d ios ]; then
  echo "==> Generating the iOS runner project"
  TMP="$(mktemp -d)"
  flutter create --platforms=ios --project-name pluto_ar_sim --org com.cpad.pluto "$TMP/pluto_ar_sim" >/dev/null
  cp -R "$TMP/pluto_ar_sim/ios" ./ios
  rm -rf "$TMP"
fi

PLIST=ios/Runner/Info.plist
add_key() { /usr/libexec/PlistBuddy -c "$1" "$PLIST" 2>/dev/null || true; }
echo "==> Patching Info.plist (camera + local network access)"
add_key "Add :NSCameraUsageDescription string 'The camera shows the virtual Pluto drone in your room (AR).'"
add_key "Add :NSLocalNetworkUsageDescription string 'Connects to the training server on your laptop.'"
add_key "Add :NSAppTransportSecurity dict"
add_key "Add :NSAppTransportSecurity:NSAllowsArbitraryLoads bool true"

if [ -f ios/Podfile ]; then
  sed -i.bak -E "s/^# platform :ios, .*/platform :ios, '13.0'/" ios/Podfile
  rm -f ios/Podfile.bak
fi

echo "==> flutter pub get"
flutter pub get
echo "==> pod install"
(cd ios && pod install)

echo
echo "Done. Next: open ios/Runner.xcworkspace in Xcode, pick your Team under"
echo "Signing & Capabilities, plug in the iPhone, then run:  flutter run --release"
