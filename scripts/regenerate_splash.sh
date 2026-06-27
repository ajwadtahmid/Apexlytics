#!/bin/sh
# Regenerates splash screens for iOS and Android, then restores the gradient background.
# flutter_native_splash always writes a solid-color 1x1 background, so we overwrite it
# with the gradient PNG after generation.
# Run this instead of `flutter pub run flutter_native_splash:create`.

set -e

GRADIENT="assets/logos/splash_background.png"

echo "Running flutter_native_splash..."
flutter pub run flutter_native_splash:create

echo "Restoring gradient background..."
cp "$GRADIENT" ios/Runner/Assets.xcassets/LaunchBackground.imageset/background.png
cp "$GRADIENT" android/app/src/main/res/drawable/background.png
cp "$GRADIENT" android/app/src/main/res/drawable-v21/background.png

echo "Done. Gradient splash restored for iOS and Android."
