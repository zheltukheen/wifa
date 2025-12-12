#!/bin/bash

set -e

APP_NAME="WiFA"
SCHEME="$APP_NAME"
ARCHS="arm64 x86_64"
OUT_DIR="build"
ARCHIVE_PATH="$OUT_DIR/${APP_NAME}.xcarchive"
PRODUCT_PATH="$OUT_DIR/${APP_NAME}-Universal"
CLEAN_ARCHIVE=${CLEAN_ARCHIVE:-1}

if [ ! -d ".xcodeproj" ] && ! ls *.xcodeproj 1> /dev/null 2>&1; then
  echo "Ошибка: Сначала создайте Xcode-проект через Xcode или xcodebuild!"
  exit 1
fi

echo "==> Очистка предыдущих сборок (только Release артефакты)"
rm -rf "$ARCHIVE_PATH" "$PRODUCT_PATH"
mkdir -p "$OUT_DIR"

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

if [ "$CLEAN_ARCHIVE" = "1" ]; then
  echo "==> Удаление .xcarchive (оставляем только $PRODUCT_PATH)"
  rm -rf "$ARCHIVE_PATH"
fi

echo "==> Готово. Universal Binary находится в $PRODUCT_PATH"
