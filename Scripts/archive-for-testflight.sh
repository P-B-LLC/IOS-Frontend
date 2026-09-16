#!/bin/bash
#
# Build a signed Rytivo archive and export it for TestFlight.
#
# Everything this needs that cannot live in the repository is passed in:
#
#   DEVELOPMENT_TEAM   the ten-character Team ID from the Apple Developer
#                      account (Membership details). Not the Apple ID.
#   REPBASE_API_URL    the https backend this build talks to. There is no
#                      default on purpose: a build that silently pointed at
#                      the wrong server would be worse than one that refused.
#
# Optional:
#   BUILD_NUMBER       defaults to the commit count, which only ever goes up.
#                      App Store Connect refuses a build number it has seen
#                      before for the same version.
#   OUTPUT_DIR         defaults to .build/testflight
#   ALLOW_PROVISIONING_UPDATES
#                      "true" lets Apple issue a distribution certificate and
#                      an App Store profile when none exists, which is what a
#                      machine archiving this app for the first time needs.
#                      Off by default: it changes the developer account, and
#                      the certificate's private key stays in the login
#                      keychain of whichever machine asked for it. Run it on a
#                      machine you are willing to keep that key on.
#
# Usage:
#   DEVELOPMENT_TEAM=ABCDE12345 REPBASE_API_URL=https://api.rytivo.app/ \
#     bash Scripts/archive-for-testflight.sh
#
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
project="$repo/IOS Frontend/IOS Frontend.xcodeproj"
scheme="IOS Frontend"
output="${OUTPUT_DIR:-$repo/.build/testflight}"
archive="$output/Rytivo.xcarchive"

die() { echo "error: $*" >&2; exit 1; }

[ -n "${DEVELOPMENT_TEAM:-}" ] || die "DEVELOPMENT_TEAM is not set. It is the
  ten-character Team ID on https://developer.apple.com/account under
  Membership details, and it is what signs the build."

[ -n "${REPBASE_API_URL:-}" ] || die "REPBASE_API_URL is not set. A release
  build reads it from its own Info.plist and calls preconditionFailure
  without an https value, so it would install and then exit on launch."

case "$REPBASE_API_URL" in
  https://*) ;;
  *) die "REPBASE_API_URL must be https, got '$REPBASE_API_URL'. App Transport
  Security refuses plain http, and the app refuses to start without https." ;;
esac

build_number="${BUILD_NUMBER:-$(git -C "$repo" rev-list --count HEAD)}"

# A machine that has never signed this app has no provisioning profile, and
# xcodebuild says so in a way that does not say what to do next:
#
#     error: No profiles for 'com.pbllc.rytivo' were found
#
# Getting one means asking Apple to issue a distribution certificate and an
# App Store profile. That is a change to the developer account, and the
# certificate's private key stays in the login keychain of whichever machine
# asked -- so it is opt-in, not something this script does because it happened
# to run on a machine that was missing one.
# A plain string rather than an array: macOS still ships bash 3.2, where
# "${array[@]}" on an empty array is an unbound variable under `set -u`. The
# value is one literal word with no spaces, so leaving it unquoted below
# expands to nothing when it is empty and to the flag when it is not.
if [ "${ALLOW_PROVISIONING_UPDATES:-false}" = "true" ]; then
    provisioning="-allowProvisioningUpdates"
    signing_note="will ask Apple to issue a certificate/profile if none exists"
else
    provisioning=""
    signing_note="existing profiles only (ALLOW_PROVISIONING_UPDATES=true to issue)"
fi

echo "Team           $DEVELOPMENT_TEAM"
echo "Server         $REPBASE_API_URL"
echo "Build number   $build_number"
echo "Provisioning   $signing_note"
echo

rm -rf "$archive"
mkdir -p "$output"

xcodebuild archive \
  -project "$project" \
  -scheme "$scheme" \
  -configuration Release \
  -destination "generic/platform=iOS" \
  -archivePath "$archive" \
  $provisioning \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
  CODE_SIGN_STYLE=Automatic \
  CURRENT_PROJECT_VERSION="$build_number" \
  REPBASE_API_URL="$REPBASE_API_URL"

# Read the built app rather than trusting the command that built it. This is
# the check that would have caught release builds dying on launch: the value
# was passed in exactly like this, and never reached the bundle, because
# Info.plist did not name it.
plist="$archive/Products/Applications/Rytivo.app/Info.plist"
read_key() { /usr/libexec/PlistBuddy -c "Print :$1" "$plist" 2>/dev/null || true; }

got_url="$(read_key REPBASE_API_URL)"
[ "$got_url" = "$REPBASE_API_URL" ] || die "the archive carries REPBASE_API_URL
  '${got_url:-<missing>}'. This build would exit on launch. Check that
  'IOS Frontend/Info.plist' still spells \$(REPBASE_API_URL)."

got_name="$(read_key CFBundleName)"
[ "$got_name" = "Rytivo" ] || die "the archive calls itself
  '${got_name:-<missing>}' rather than Rytivo. That name reaches App Store
  Connect and the device's Settings."

got_build="$(read_key CFBundleVersion)"
[ "$got_build" = "$build_number" ] || die "the archive is build
  '${got_build:-<missing>}', not $build_number. App Store Connect rejects a
  build number it has already seen for this version."

cat > "$output/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>teamID</key>
	<string>$DEVELOPMENT_TEAM</string>
	<key>destination</key>
	<string>export</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>uploadSymbols</key>
	<true/>
	<key>manageAppVersionAndBuildNumber</key>
	<false/>
</dict>
</plist>
PLIST

# Written here rather than committed because it has to carry the literal Team
# ID: -exportOptionsPlist is read by xcodebuild, not by the build system, so
# a $(DEVELOPMENT_TEAM) in it would stay a dollar sign.
#
# manageAppVersionAndBuildNumber is false so Apple does not quietly renumber
# the build. Being handed a number nobody chose makes "which build is the
# tester on" unanswerable.

xcodebuild -exportArchive \
  -archivePath "$archive" \
  $provisioning \
  -exportOptionsPlist "$output/ExportOptions.plist" \
  -exportPath "$output"

echo
echo "Exported to $output"
ls -1 "$output"/*.ipa 2>/dev/null || true
echo
# Example values rather than <placeholders>: these lines get pasted, and the
# angle brackets are shell redirection, so a pasted <the .ipa> opens a file
# called "the" and reports nothing useful about why.
echo "To upload, either open Transporter.app and drop the .ipa in, or:"
echo "  xcrun altool --upload-app -f Rytivo.ipa -t ios \\"
echo "    --apiKey ABCD123456 --apiIssuer 11111111-2222-3333-4444-555555555555"
echo
echo "The API key comes from App Store Connect -> Users and Access -> Keys."
echo "Do not put it in this repository."
