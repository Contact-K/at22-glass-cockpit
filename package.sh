#!/bin/bash
# AT22 を署名済み DMG に固める。
#
#   ./package.sh 0.1.0
#
# 事前に一度だけ必要（このスクリプトでは自動化できない）:
#   1. Apple Developer Program に登録
#   2. Developer ID Application 証明書を発行
#   3. xcrun notarytool store-credentials AT22_NOTARY \
#        --apple-id <Apple ID> --team-id <Team ID> --password <App用パスワード>
#
# ponytail: create-dmg は入れない。hdiutil で足りるし、
#           依存ゼロという本体の方針を配布側でも崩さない。

set -euo pipefail

USAGE="使い方: ./package.sh <version> [--dry-run]   例) ./package.sh 0.1.0"
VERSION="${1:?$USAGE}"
# 証明書が揃う前に、ビルドと .app の組み立てまでを確かめるための空撃ち
DRY_RUN="${2:-}"
BUNDLE_ID="com.contactk.at22"
NOTARY_PROFILE="AT22_NOTARY"
MIN_MACOS="15.0"

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGE="$ROOT/.build/dmg"
APP="$STAGE/AT22.app"
DIST="$ROOT/dist"
DMG="$DIST/AT22-$VERSION.dmg"

# --- 署名の準備ができているか先に見る。ビルドしてから落ちても時間の無駄 ---
IDENTITY="$(security find-identity -v -p codesigning \
  | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo "== 空撃ち: 署名・公証は行わない =="
  [ -n "$IDENTITY" ] && echo "署名 ID: $IDENTITY" || echo "署名 ID: まだ無い（本番ではここで止まる）"
elif [ -z "$IDENTITY" ]; then
  cat >&2 <<'MSG'
Developer ID Application 証明書が見つからない。

配布用の署名には Apple Developer Program（年 $99）の登録と、
Developer ID Application 証明書の発行が要る。Apple Development 証明書では配布できない。

  Xcode → Settings → Accounts → Manage Certificates → ＋ → Developer ID Application

発行後に確認:
  security find-identity -v -p codesigning
MSG
  exit 1
else
  echo "署名 ID: $IDENTITY"
fi

if [ "$DRY_RUN" != "--dry-run" ] \
   && ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  cat >&2 <<MSG
公証用の資格情報 '$NOTARY_PROFILE' が保存されていない。

  xcrun notarytool store-credentials $NOTARY_PROFILE \\
    --apple-id <Apple ID> --team-id <Team ID> --password <App用パスワード>

App用パスワードは appleid.apple.com で作る。
MSG
  exit 1
fi

# --- ビルド ---
echo "==> ビルド"
swift build -c release --arch arm64
# 成果物の場所は SwiftPM に聞く（--arch を付けると .build/release ではなく
# .build/arm64-apple-macosx/release になる。決め打ちすると壊れる）
BUILD="$(swift build -c release --arch arm64 --show-bin-path | tail -1)"

# --- .app を組む ---
echo "==> AT22.app を組み立て"
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD/AT22" "$APP/Contents/MacOS/AT22"
cp "$ROOT/Resources/AT22.icns" "$APP/Contents/Resources/AT22.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AT22</string>
  <key>CFBundleDisplayName</key><string>AT22 Glass Cockpit</string>
  <key>CFBundleExecutable</key><string>AT22</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key><string>AT22</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

if [ "$DRY_RUN" = "--dry-run" ]; then
  echo
  echo "空撃ち終了。組み立てまでは通った: $APP"
  echo "中身:"
  /usr/bin/find "$APP" -type f | sed "s|$APP|  AT22.app|"
  echo
  echo "署名・公証・DMG 化は証明書が揃ってから ./package.sh $VERSION で実行する。"
  exit 0
fi

# --- 署名 ---
# --options runtime（Hardened Runtime）は公証の必須条件。
# サンドボックスも JIT も使わないので entitlements は要らない。
echo "==> .app に署名"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

# --- .app を公証して staple ---
# .app 自体にも券を貼る。DMG にだけ貼ると、Applications へコピーした後の
# .app は券を持たず、オフラインの環境で弾かれる。
echo "==> .app を公証（数分かかる）"
ZIP="$ROOT/.build/AT22.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$ZIP"

# --- DMG ---
# 券を貼った .app を入れてから DMG を作る（順序が逆だと貼り直しが要る）
echo "==> DMG を作成"
mkdir -p "$DIST"
ln -sf /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "AT22 Glass Cockpit" -srcfolder "$STAGE" \
  -ov -format UDZO -quiet "$DMG"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

echo "==> DMG を公証"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# --- 検証 ---
echo "==> 検証"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl -a -t exec -vv "$APP"

echo
echo "完成: $DMG"
echo "配布前に、ダウンロード直後の状態で開けるか確かめること:"
echo "  cp '$DMG' /tmp/dl.dmg && xattr -w com.apple.quarantine '0081;0;Safari;' /tmp/dl.dmg && open /tmp/dl.dmg"
