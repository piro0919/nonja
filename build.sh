#!/bin/bash
# Nonja をビルドして Nonja.app を作る。Xcode 本体は不要（Command Line Tools のみで動く）。
set -euo pipefail

cd "$(dirname "$0")"

APP="Nonja.app"
TARGET="arm64-apple-macos14.0"

# 署名は固定した証明書で行う。暫定署名（`-`）だとビルドのたびに同一性が変わり、
# フルディスクアクセスとアクセシビリティの許可が毎回外れて開発が進まない。
# 証明書がなければ暫定署名に落とすが、そのときは許可を入れ直す必要がある
SIGN_IDENTITY="${NONJA_SIGN_IDENTITY:-Okigae Dev}"
if ! security find-identity -v -p codesigning | grep -q "$SIGN_IDENTITY"; then
  echo "警告: 証明書「$SIGN_IDENTITY」が見つかりません。暫定署名にします（許可が外れます）" >&2
  SIGN_IDENTITY="-"
fi
# リリース時は release.sh から渡される。手元のビルドでは 0.0.0 のままでよい
VERSION="${NONJA_VERSION:-0.0.0}"

rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS"

swiftc \
  -parse-as-library \
  -target "$TARGET" \
  -O \
  -framework AppKit \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -o "$APP/Contents/MacOS/Nonja" \
  Sources/Paths.swift Sources/Notification.swift Sources/Store.swift \
  Sources/Mark.swift Sources/Login.swift Sources/Rules.swift Sources/State.swift Sources/Engine.swift Sources/SelfTest.swift \
  Sources/Opener.swift Sources/ListWindow.swift Sources/RulesWindow.swift Sources/main.swift

# アイコンの下ごしらえ。元絵には手を入れず、build/ に加工したものを作る
mkdir -p build "$APP/Contents/Resources"
swiftc -O -target "$TARGET" -framework AppKit -o build/icontool Tools/icon/main.swift

if [ -f Resources/nonja-icon.png ]; then
  # macOS 26 は透明の無い正方形を求める。角丸は OS 側が付ける
  ./build/icontool square Resources/nonja-icon.png build/app-square.png

  ICONSET="build/Nonja.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size build/app-square.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) build/app-square.png \
      --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Nonja.icns"
fi


cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Nonja</string>
  <key>CFBundleDisplayName</key><string>Nonja</string>
  <key>CFBundleExecutable</key><string>Nonja</string>
  <key>CFBundleIconFile</key><string>Nonja</string>
  <key>CFBundleIdentifier</key><string>io.kkweb.nonja</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <!-- Dock とアプリ切替に出さず、メニューバーだけに常駐させる -->
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <!-- 通知センターを開いて本物の通知を押すために System Events を操作する -->
  <key>NSAppleEventsUsageDescription</key>
  <string>通知をクリックしたときに、元のアプリへ移動するため通知センターを操作します。</string>
</dict>
</plist>
PLIST

codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "できました: $(pwd)/${APP} — 署名 ${SIGN_IDENTITY}"
