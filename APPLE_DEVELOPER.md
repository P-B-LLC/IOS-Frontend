# Getting Rytivo onto a tester's phone

Everything an Apple Developer membership unlocks, in the order it has to
happen, with the parts that are slow marked as slow. Written 2026-09-13,
before the membership was bought, so the repository side is done and the
account side is not.

---

## 1. Buy the membership — and decide one thing first

$99 a year, at <https://developer.apple.com/programs/enroll/>. Two-factor
authentication has to be on for the Apple ID you enrol with.

The decision inside the purchase is **Individual or Organization**, because it
sets the seller name shown publicly on the listing and it is not a setting you
can flip afterwards — changing it later is an account transfer.

| | Individual | Organization |
|---|---|---|
| Seller name shown publicly | your legal name | `P B LLC` |
| What Apple asks for | an Apple ID and a card | a **D-U-N-S number** for the entity, and proof you can sign for it |
| How long | often same day, sometimes a few days | the D-U-N-S lookup alone can take up to five business days |

**This is the long pole in the whole beta.** If the LLC should be the seller,
look up or request the D-U-N-S number today, before paying for anything:
<https://developer.apple.com/enroll/duns-lookup/>. It is free, and it is the
step with a queue in front of it. Everything else here takes minutes.

## 2. Register two things

Once the membership is active, at <https://developer.apple.com/account>:

- **Team ID** — ten characters, under Membership details. Copy it; the archive
  script needs it and nothing in the repository stores it.
- **App ID** — Identifiers → +, bundle ID `com.pbllc.rytivo`. It has to match
  `PRODUCT_BUNDLE_IDENTIFIER` character for character.

On that App ID, enable **HealthKit**. `IOS Frontend.entitlements` asks for it,
and a device build refuses to sign if the App ID does not grant it. The
simulator does not enforce provisioning, which is why this has never come up.
Background location needs nothing here — it is declared in `Info.plist`.

Signing itself is automatic as long as Xcode on the build Mac is signed in to
this account. No certificate needs creating by hand.

## 3. Create the App Store Connect record

<https://appstoreconnect.apple.com> → My Apps → + → New App.

- Name: **Rytivo**. This is unique across the entire App Store, so check it is
  free before building anything around it. If it is taken, the name in the
  listing has to change; `CFBundleDisplayName` does not have to follow.
- Bundle ID: `com.pbllc.rytivo`. SKU: anything internal and stable.

**Internal testing** — up to 100 people who are members of your team — needs
nothing further. **External testing** — up to 10,000 by link — needs a Beta App
Review first, and that review needs:

- **App privacy answers.** Rytivo collects an email address, workouts,
  nutrition, planner entries, photos, location recorded during a session, and
  step counts read from HealthKit. Health and location data get asked about
  specifically; answer from `PrivacyInfo.xcprivacy` and the usage strings in
  `Info.plist`, which are the same claims.
- **A privacy policy URL that resolves.** `LegalDocuments.contactEmail` is
  `support@repbase.app`, and the privacy copy tells people to write there to
  have their data deleted. Somebody has to actually read that mailbox before a
  stranger is invited to use it.
- A beta description and a feedback email.

Export compliance is already answered: `ITSAppUsesNonExemptEncryption` is
`false` in `Info.plist`, so uploads stop asking.

## 4. What is already done here

Nothing in this list needs revisiting when the membership arrives.

- `PRODUCT_BUNDLE_IDENTIFIER` is `com.pbllc.rytivo`.
- `CFBundleDisplayName` and `CFBundleName` are both Rytivo, and CI reads the
  latter back out of a built Release app rather than trusting the setting.
- `IOS Frontend.entitlements` requests HealthKit read access, and nothing else.
- `PrivacyInfo.xcprivacy` is present.
- `ITSAppUsesNonExemptEncryption` is declared.
- `Scripts/archive-for-testflight.sh` archives, verifies and exports.

## 5. The first upload

```bash
DEVELOPMENT_TEAM=<ten characters> \
REPBASE_API_URL=https://<the deployed backend>/ \
  bash Scripts/archive-for-testflight.sh
```

It refuses to run without both, refuses a non-https URL, and after building it
reads the server, the name and the build number back out of the archive before
exporting. That readback is not ceremony: `REPBASE_API_URL` was passed to the
build exactly like this once before and never reached the bundle, and every
release build died on launch for a week without anything noticing.

The build number defaults to the commit count, which only ever goes up. App
Store Connect refuses a build number it has already seen for a version, and
that is the usual reason a second upload bounces.

Then drop the `.ipa` into Transporter, or use `xcrun altool --upload-app` with
an App Store Connect API key from Users and Access → Keys. The key does not go
in this repository.

**This step needs the backend deployed first** — blocker 4 in
[BETA_READINESS.md](BETA_READINESS.md). Until an https backend exists there is
no honest value for `REPBASE_API_URL`, and the script would rather stop than
produce an archive that installs and exits.

## 6. Two things worth deciding before they decide themselves

**Where the distribution certificate lives.** Automatic signing puts its
private key in the login keychain of whichever Mac archives the build. Today
that is a rented MacinCloud box administered by someone else, shared with
other users, and already unable to reach GitHub. A distribution certificate is
the credential that says a build is authentically yours. Archiving from a
machine you own is the better answer; if that is not available, the
certificate can be revoked and reissued from the portal at any time, so at
least know that it is there.

**Who the beta testers are.** Internal testers have to be members of the
developer team, which means giving them App Store Connect accounts and some
level of access to the account. External testers only need a link, but that
route goes through Beta App Review. For a handful of friends, external is
usually less to give away than internal.
