#!/bin/bash
# Nonja を1つ上げる。DMG を作り、更新情報に署名して、GitHub Releases に置く。
#
#   ./release.sh 0.1.0
#
# 秘密鍵はログインキーチェーンにある。Gocci・Konechi と同じ鍵で、
# これを失うと、既に配ったアプリへ更新を届けられなくなる。
set -euo pipefail

cd "$(dirname "$0")"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "使い方: ./release.sh <版数>   例: ./release.sh 0.1.0" >&2
  exit 1
fi

REPO="piro0919/nonja"
APP="Nonja.app"
DMG="Nonja-${VERSION}.dmg"
ZIP="Nonja-${VERSION}.zip"

# 版数を Info.plist に焼き込むため、build.sh へ渡す
NONJA_VERSION="$VERSION" ./build.sh

# 配る前に、ルールの当たり方だけでも確かめておく
./"$APP"/Contents/MacOS/Nonja --selftest

rm -rf dist
# 更新用の zip は別の場所に置く。generate_appcast は同じ版数の書庫が2つあると
# 「重複」と判断して止まるので、zip と DMG を同じ場所に並べない
mkdir -p dist/update

# 更新の中身は zip で配る。Sparkle が受け取れる形はこれが素直
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/update/$ZIP"

# 利用者が最初に入れるときは DMG。ドラッグ＆ドロップで /Applications に入れてもらう
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Nonja" -srcfolder "$STAGE" -ov -format UDZO "dist/$DMG"
rm -rf "$STAGE"

# 更新情報に署名する。generate_appcast は zip を読んで appcast.xml を作る。
# 鍵はログインキーチェーンから読むので、初回は許可を求められる
./Vendor/bin/generate_appcast \
  --download-url-prefix "https://github.com/${REPO}/releases/download/v${VERSION}/" \
  dist/update

echo
echo "できました:"
ls -1 dist dist/update

echo
echo "GitHub Releases に上げます…"
gh release create "v${VERSION}" \
  --repo "$REPO" \
  --title "v${VERSION}" \
  --generate-notes \
  "dist/${DMG}" "dist/update/${ZIP}" "dist/update/appcast.xml"

echo "完了: https://github.com/${REPO}/releases/tag/v${VERSION}"
