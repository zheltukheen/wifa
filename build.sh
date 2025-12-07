#!/bin/bash

set -e

APP_NAME="WiFA"
SCHEME="$APP_NAME"
ARCHS="arm64 x86_64"
DERIVED_DATA="build"
ARCHIVE_PATH="$DERIVED_DATA/${APP_NAME}.xcarchive"
PRODUCT_PATH="$DERIVED_DATA/${APP_NAME}-Universal"

if [ ! -d ".xcodeproj" ] && ! ls *.xcodeproj 1> /dev/null 2>&1; then
  echo "Ошибка: Сначала создайте Xcode-проект через Xcode или xcodebuild!"
  exit 1
fi

echo "==> Очистка предыдущих сборок"
rm -rf "$DERIVED_DATA"

echo "==> Сборка xcarchive для обеих архитектур..."
xcodebuild archive \
  -scheme "$SCHEME" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  -configuration Release \
  ONLY_ACTIVE_ARCH=NO \
  SUPPORTED_ARCHS="$ARCHS"

mkdir -p "$PRODUCT_PATH"

echo "==> Копирование приложения"
cp -R "$ARCHIVE_PATH/Products/Applications/${APP_NAME}.app" "$PRODUCT_PATH/"

echo "==> Готово. Universal Binary находится в $PRODUCT_PATH"
