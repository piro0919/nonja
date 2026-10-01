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
  # release.sh はこれを立てて呼ぶ。暫定署名のまま配ると、更新のたびに利用者の許可が外れる
  if [ "${NONJA_REQUIRE_IDENTITY:-0}" = "1" ]; then
    echo "エラー: 証明書「${SIGN_IDENTITY}」が見つかりません。暫定署名のままでは配れません" >&2
    exit 1
  fi
  echo "警告: 証明書「${SIGN_IDENTITY}」が見つかりません。暫定署名にします（許可が外れます）" >&2
  SIGN_IDENTITY="-"
fi
# リリース時は release.sh から渡される。手元のビルドでは 0.0.0 のままでよい
VERSION="${NONJA_VERSION:-0.0.0}"
SPARKLE_VERSION="2.9.5"
# 取ってきた書庫を確かめる値。版を上げたら一緒に差し替える。
# GitHub Releases の asset に載っている digest と同じもの:
#   gh api repos/sparkle-project/Sparkle/releases/tags/<版> --jq '.assets[] | "\(.name) \(.digest)"'
SPARKLE_SHA256="015336b601493e05c237964954bff6191370003d94edefe663724c88840d73cc"

# 自動更新に Sparkle を使う。framework は大きいのでリポジトリに置かず、
# 無ければ取ってくる（Vendor/ は git の管理外）
if [ ! -d "Vendor/Sparkle.framework" ]; then
  echo "Sparkle $SPARKLE_VERSION を取得します…"
  mkdir -p Vendor
  TMP="$(mktemp -d)"
  curl -fsSL -o "$TMP/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  # 中身を検めずに同梱すると、差し替えられた framework がそのまま配布物に入る
  if ! echo "${SPARKLE_SHA256}  $TMP/sparkle.tar.xz" | shasum -a 256 -c - >/dev/null; then
    echo "エラー: Sparkle ${SPARKLE_VERSION} の SHA-256 が一致しません。" >&2
    echo "        期待値: ${SPARKLE_SHA256}" >&2
    echo "        実際:   $(shasum -a 256 "$TMP/sparkle.tar.xz" | cut -d' ' -f1)" >&2
    rm -rf "$TMP"
    exit 1
  fi
  tar xf "$TMP/sparkle.tar.xz" -C "$TMP"
  cp -R "$TMP/Sparkle.framework" Vendor/
  cp -R "$TMP/bin" Vendor/
  rm -rf "$TMP"
fi

rm -rf "$APP" build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks"
cp -R Vendor/Sparkle.framework "$APP/Contents/Frameworks/"

swiftc \
  -parse-as-library \
  -target "$TARGET" \
  -swift-version 6 \
  -O \
  -framework AppKit \
  -framework ApplicationServices \
  -framework ServiceManagement \
  -F Vendor \
  -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "$APP/Contents/MacOS/Nonja" \
  Sources/Localization.swift Sources/Paths.swift Sources/Notification.swift Sources/Store.swift \
  Sources/Mark.swift Sources/Login.swift Sources/Rules.swift Sources/State.swift Sources/Engine.swift Sources/SelfTest.swift \
  Sources/Updater.swift Sources/Opener.swift \
  Sources/ListWindow.swift Sources/SettingsWindow.swift Sources/main.swift

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

  <!-- 自動更新（Sparkle）。確認は起動時に1回だけ行い、見つかったときだけ画面を出す。
       この2つを false にしておかないと、初回起動で「自動で確認していいか」を尋ねる画面が出る -->
  <key>SUFeedURL</key><string>https://github.com/piro0919/nonja/releases/latest/download/appcast.xml</string>
  <!-- 更新の署名を確かめる公開鍵。対になる秘密鍵はログインキーチェーンにあり、
       これを失うと更新を配れなくなる。Gocci・Konechi と同じ鍵 -->
  <key>SUPublicEDKey</key><string>qYQq1iewXYNDhhkJJak1nXUXmFkZ0jAF6Gr+pjB4Bxo=</string>
  <key>SUEnableAutomaticChecks</key><false/>
  <key>SUAutomaticallyUpdate</key><false/>

  <key>NSAppleEventsUsageDescription</key>
  <string>通知をクリックしたときに、元のアプリへ移動するため通知センターを操作します。</string>
</dict>
</plist>
PLIST

# 同梱した framework は中から署名する。先にアプリを署名すると、
# 後から中身が変わって壊れる
for xpc in Downloader Installer; do
  codesign --force --sign "$SIGN_IDENTITY" \
    "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/${xpc}.xpc" 2>/dev/null || true
done
codesign --force --sign "$SIGN_IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate" 2>/dev/null || true
codesign --force --sign "$SIGN_IDENTITY" \
  "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/Updater.app" 2>/dev/null || true
codesign --force --sign "$SIGN_IDENTITY" "$APP/Contents/Frameworks/Sparkle.framework"
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "できました: $(pwd)/${APP} — 署名 ${SIGN_IDENTITY}"
