#!/usr/bin/env bash
#
# Builds a universal (arm64 + x86_64) Release copy of DotQuit into ./dist.
#
#   ./Scripts/build-release.sh                 build only
#   ./Scripts/build-release.sh --sign          build + Developer ID signing
#   ./Scripts/build-release.sh --sign --notarize   build + sign + notarize + staple
#
# Without --sign the script still produces a runnable .app and prints the exact
# signing commands it would have run, so the pipeline can be reviewed before
# any credentials exist.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — override by exporting these, or edit the defaults.
# ---------------------------------------------------------------------------

# Auto-detected from the login Keychain unless you override it.
# `security find-identity -v -p codesigning` lists what is installed.
# Returns empty (and succeeds) when no such certificate is installed — under
# `set -euo pipefail` a bare grep miss would abort the script before it could
# explain itself.
detect_developer_id() {
  local line
  line=$(security find-identity -v -p codesigning 2>/dev/null \
         | grep "Developer ID Application" || true)
  [ -n "$line" ] || return 0
  printf '%s\n' "$line" | sed -n -E '1s/.*"(.*)".*/\1/p'
}
DEVELOPER_ID_APP="${DEVELOPER_ID_APP:-$(detect_developer_id || true)}"

# Created once with:
#   xcrun notarytool store-credentials dotquit-notary \
#     --apple-id you@example.com --team-id YOURTEAMID --password <app-specific-password>
NOTARY_PROFILE="${NOTARY_PROFILE:-dotquit-notary}"

PROJECT="DotQuit.xcodeproj"
SCHEME="DotQuit"
CONFIGURATION="Release"
ARCHS_LIST="arm64 x86_64"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$REPO_ROOT/dist"
BUILD_DIR="$REPO_ROOT/.build-release"
APP_NAME="DotQuit.app"
APP_PATH="$DIST_DIR/$APP_NAME"
DMG_PATH="$DIST_DIR/DotQuit.dmg"
VOLUME_NAME="DotQuit"
ENTITLEMENTS="$REPO_ROOT/DotQuit/DotQuit.entitlements"

DO_SIGN=false
DO_NOTARIZE=false
for arg in "$@"; do
  case "$arg" in
    --sign)     DO_SIGN=true ;;
    --notarize) DO_SIGN=true; DO_NOTARIZE=true ;;
    -h|--help)  sed -n '2,12p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$1"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$1" >&2; exit 1; }

cd "$REPO_ROOT"

# ---------------------------------------------------------------------------
step "Preflight"
# ---------------------------------------------------------------------------
command -v xcodebuild >/dev/null || fail "xcodebuild not found (install Xcode)."
[ -f "$ENTITLEMENTS" ] || fail "missing entitlements at $ENTITLEMENTS"
xcodebuild -version | sed -n '1p'
echo "configuration : $CONFIGURATION"
echo "architectures : $ARCHS_LIST"
echo "sign          : $DO_SIGN"
echo "notarize      : $DO_NOTARIZE"
if [ -n "$DEVELOPER_ID_APP" ]; then
  echo "identity      : $DEVELOPER_ID_APP"
else
  echo "identity      : (none found — no 'Developer ID Application' certificate)"
fi

if [ "$DO_SIGN" = true ] && [ -z "$DEVELOPER_ID_APP" ]; then
  cat >&2 <<'MSG'

error: no "Developer ID Application" certificate in the Keychain.

  An "Apple Development" certificate is NOT sufficient — it signs for local
  debugging only, and Apple will refuse to notarize anything signed with it.

  To get one:
    1. developer.apple.com -> Certificates -> + -> Developer ID Application
    2. download the .cer and double-click to install it
    3. verify with: security find-identity -v -p codesigning

  Or run without --sign to produce an unsigned build and DMG.
MSG
  exit 1
fi

# ---------------------------------------------------------------------------
step "Clean"
# ---------------------------------------------------------------------------
rm -rf "$DIST_DIR" "$BUILD_DIR"
mkdir -p "$DIST_DIR"

# ---------------------------------------------------------------------------
step "Build universal $CONFIGURATION"
# ---------------------------------------------------------------------------
# Signing is deliberately off here: the app is signed explicitly below so that
# the hardened runtime, entitlements and secure timestamp are applied in one
# auditable place rather than depending on Xcode's automatic settings.
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$BUILD_DIR" \
  ARCHS="$ARCHS_LIST" \
  VALID_ARCHS="$ARCHS_LIST" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  clean build | \
  grep -E "error:|warning:|BUILD" || true

BUILT_APP="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME"
[ -d "$BUILT_APP" ] || fail "build produced no app at $BUILT_APP"

# ---------------------------------------------------------------------------
step "Stage into dist/"
# ---------------------------------------------------------------------------
ditto "$BUILT_APP" "$APP_PATH"
# Finder metadata and quarantine flags break notarization; strip them.
xattr -cr "$APP_PATH"

echo "slices: $(lipo -archs "$APP_PATH/Contents/MacOS/DotQuit")"
for arch in $ARCHS_LIST; do
  lipo -archs "$APP_PATH/Contents/MacOS/DotQuit" | grep -qw "$arch" \
    || fail "missing $arch slice — not a universal binary"
done

# ---------------------------------------------------------------------------
step "Code signing"
# ---------------------------------------------------------------------------
# Signed inside-out: nested bundles first, the app last. Apple advises against
# `codesign --deep` for signing (it applies the app's entitlements to nested
# code and skips things it doesn't recognise); --deep is used only to VERIFY
# below, which is what it is actually for.
#
# --timestamp is mandatory for notarization. --options runtime turns on the
# hardened runtime, which is also mandatory.
sign_one() {
  local target="$1"; shift
  codesign --force --timestamp --options runtime \
    "$@" --sign "$DEVELOPER_ID_APP" "$target"
}

NESTED=()
while IFS= read -r line; do NESTED+=("$line"); done < <(
  find "$APP_PATH/Contents" \
    \( -name "*.framework" -o -name "*.bundle" -o -name "*.dylib" -o -name "*.appex" \) \
    -not -path "$APP_PATH/Contents/MacOS/*" | sort -r
)

if [ "$DO_SIGN" = true ]; then
  for nested in ${NESTED+"${NESTED[@]}"}; do
    echo "signing nested: ${nested#"$APP_PATH"/}"
    sign_one "$nested"
  done
  echo "signing app"
  sign_one "$APP_PATH" --entitlements "$ENTITLEMENTS"

  step "Verify signature"
  codesign --verify --deep --strict --verbose=2 "$APP_PATH"
  codesign -d --entitlements - --xml "$APP_PATH" | plutil -p -
  # Gatekeeper's verdict. Before notarization this reports "rejected"
  # (source=Unnotarized Developer ID) — that is expected at this stage.
  spctl --assess --type exec --verbose=4 "$APP_PATH" || true
else
  cat <<EOF
skipped (no --sign). The commands that would run:

  # nested code first, app last — never 'codesign --deep' to sign
$(for n in ${NESTED+"${NESTED[@]}"}; do
    echo "  codesign --force --timestamp --options runtime \\"
    echo "    --sign \"\$DEVELOPER_ID_APP\" \"${n#"$REPO_ROOT"/}\""
  done)
  codesign --force --timestamp --options runtime \\
    --entitlements "DotQuit/DotQuit.entitlements" \\
    --sign "\$DEVELOPER_ID_APP" "dist/$APP_NAME"

  codesign --verify --deep --strict --verbose=2 "dist/$APP_NAME"
EOF
fi

# ---------------------------------------------------------------------------
step "Package (zip)"
# ---------------------------------------------------------------------------
# notarytool only accepts .zip, .dmg or .pkg. The app is notarised from the
# zip first so the ticket can be stapled to the .app *before* it goes into the
# DMG — otherwise a user who drags the app out of the DMG gets an app with no
# ticket of its own, and Gatekeeper has to phone home to validate it.
ZIP_PATH="$DIST_DIR/DotQuit.zip"
# ditto --keepParent preserves the bundle structure and symlinks; `zip` does not.
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
echo "wrote $(du -h "$ZIP_PATH" | cut -f1) -> ${ZIP_PATH#"$REPO_ROOT"/}"

# ---------------------------------------------------------------------------
step "Notarize app"
# ---------------------------------------------------------------------------
if [ "$DO_NOTARIZE" = true ]; then
  xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"
  # Re-zip so the archive carries the stapled copy too.
  rm -f "$ZIP_PATH"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
else
  cat <<EOF
skipped (no --notarize). The commands that would run:

  xcrun notarytool submit "dist/DotQuit.zip" --keychain-profile "\$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/$APP_NAME"
  xcrun stapler validate "dist/$APP_NAME"
EOF
fi

# ---------------------------------------------------------------------------
step "Package (dmg)"
# ---------------------------------------------------------------------------
DMG_STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$DMG_STAGING"; mkdir -p "$DMG_STAGING"
ditto "$APP_PATH" "$DMG_STAGING/$APP_NAME"
# The /Applications alias is what makes the window a drag-to-install target.
ln -s /Applications "$DMG_STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$DMG_STAGING" \
  -fs HFS+ \
  -format UDZO \
  -quiet \
  "$DMG_PATH"
rm -rf "$DMG_STAGING"
echo "wrote $(du -h "$DMG_PATH" | cut -f1) -> ${DMG_PATH#"$REPO_ROOT"/}"

if [ "$DO_SIGN" = true ]; then
  # A signed DMG means the container itself is tamper-evident, not just the
  # app inside it.
  codesign --force --timestamp --sign "$DEVELOPER_ID_APP" "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH"
fi

# ---------------------------------------------------------------------------
step "Notarize dmg"
# ---------------------------------------------------------------------------
if [ "$DO_NOTARIZE" = true ]; then
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"

  step "Gatekeeper assessment"
  spctl --assess --type exec --verbose=4 "$APP_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
else
  cat <<EOF
skipped (no --notarize). The commands that would run:

  xcrun notarytool submit "dist/DotQuit.dmg" --keychain-profile "\$NOTARY_PROFILE" --wait
  xcrun stapler staple "dist/DotQuit.dmg"
  xcrun stapler validate "dist/DotQuit.dmg"

  # if a submission is rejected:
  xcrun notarytool log <submission-id> --keychain-profile "\$NOTARY_PROFILE"
EOF
fi

step "Done"
echo "app : ${APP_PATH#"$REPO_ROOT"/}"
echo "zip : ${ZIP_PATH#"$REPO_ROOT"/}"
echo "dmg : ${DMG_PATH#"$REPO_ROOT"/}"
