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

# 作る前に確かめる。どれか一つでも外れたら、何も作らずに止める
fail() {
  echo "エラー: $*" >&2
  exit 1
}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "版数は 1.2.3 の形で渡してください（受け取った値: ${VERSION}）"
fi

# 作業ツリーが汚れていると、配る中身がどのコミットにも残らない
if [ -n "$(git status --porcelain)" ]; then
  git status --short >&2
  fail "作業ツリーに未コミットの変更があります。コミットするか退避してから上げてください"
fi

# 札はこのコミットに付ける。GitHub に無いコミットには付けられないので、先に push しておく
HEAD_SHA="$(git rev-parse HEAD)"
git fetch -q origin main
if ! git merge-base --is-ancestor "$HEAD_SHA" origin/main; then
  fail "手元の HEAD（${HEAD_SHA:0:7}）が origin/main に入っていません。push してから上げてください"
fi
if git rev-parse -q --verify "refs/tags/v${VERSION}" >/dev/null ||
  git ls-remote --exit-code --tags origin "refs/tags/v${VERSION}" >/dev/null; then
  fail "札 v${VERSION} はすでにあります。版数を上げてください"
fi

# リリースノートは CHANGELOG.md のこの版の節から取る。節が無い・空なら止める。
# --generate-notes は main へ直に積んだコミットを拾わず、「Full Changelog」の一行だけになる
NOTES_FILE="$(mktemp)"
trap 'rm -f "$NOTES_FILE"' EXIT
awk -v head="## [${VERSION}]" '
  /^## / { if (found) exit; if (index($0, head) == 1) { found = 1; next } }
  found { print }
' CHANGELOG.md >"$NOTES_FILE"
if ! grep -q '[^[:space:]]' "$NOTES_FILE"; then
  fail "CHANGELOG.md に「## [${VERSION}]」の節がありません（あっても中身が空です）"
fi

# 版数を Info.plist に焼き込むため、build.sh へ渡す
NONJA_VERSION="$VERSION" NONJA_REQUIRE_IDENTITY=1 ./build.sh

# 焼き込まれた版数が引数と食い違っていたら、札と中身がずれる
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [ "$BUILT_VERSION" != "$VERSION" ]; then
  fail "できたアプリの版数が ${BUILT_VERSION} です（期待値: ${VERSION}）"
fi
codesign --verify --deep --strict "$APP" || fail "できたアプリの署名が壊れています"
# 暫定署名で配ると、更新のたびに利用者の許可が外れる。決まった証明書で署名できたときだけ進む
SIGN_IDENTITY="${NONJA_SIGN_IDENTITY:-Okigae Dev}"
if ! codesign -dvv "$APP" 2>&1 | grep -qx "Authority=${SIGN_IDENTITY}"; then
  fail "「${SIGN_IDENTITY}」で署名されていません。証明書がキーチェーンにあるか確かめてください"
fi

# 配る前に、できたものの --selftest を通す
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
  --target "$HEAD_SHA" \
  --notes-file "$NOTES_FILE" \
  "dist/${DMG}" "dist/update/${ZIP}" "dist/update/appcast.xml"

echo "完了: https://github.com/${REPO}/releases/tag/v${VERSION}"
