# Sunrise Home presentation

Approved Figma: [Sunrise review, light and dark](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=217-6964).
The light implementation follows `219:7032`; dark follows `219:7299`.

Scope: Home presentation only, on `work/testflight-fixes-2026-10-27`.
`backup/pre-sunrise-home-2026-11-01` preserves the layered Home at `80cdb01`.
`backup/pre-home-layered-ui-2026-11-01` preserves the earlier UI at `bd7a1c6`.
Training, Food, Calendar, Social, and Account require individual Figma review
before adopting these styles. No API, database, store, or navigation contract
changes are part of this work.

Home uses a warm Sunrise backdrop and subtle glow, a raised week dock, a rounded
foreground sheet, and focused cards with softly lifted bases. Next up has a
raised clock tile; the workout card has an exercise-count tile and full-width
green action. The glow and exercise tile use the original light/dark SVG assets
from Figma. The existing food, steps, agenda, and More sections retain their
presentation and behavior. Named light/dark assets and `RepbaseTactileDesign.swift` are
opt-in; the existing global palette and other screens are unchanged. Background
shapes cast the shadows without rasterizing each card's content. All displayed
steps, dates, workouts, food totals, goals, errors, and actions retain their
existing stores and routes. Personalization still determines section order.
The clock separates localized prefix or suffix day periods without changing the
original time. Twenty-four-hour times remain intact. Untimed and empty days do
not invent a due time. Cardio workouts show their activity rather than an empty
exercise count. At accessibility text sizes, the tiles become unrestricted text
and the cards stack vertically. The date dock retains 44-point day targets on
the narrow simulator. These cases have regression tests or native preview
fixtures, including Arabic, Japanese, and German.
The shared tab bar's compact labels use the existing text-size ceiling to avoid
overlap at accessibility sizes; destination content remains fully scalable and
VoiceOver retains the complete tab names. Normal-size tab styling is unchanged.

## Build and review

On the Mac, with an iPhone simulator booted:

```sh
cd ~/Documents/IOS-Frontend
git fetch origin
git switch work/testflight-fixes-2026-10-27
git pull --ff-only origin work/testflight-fixes-2026-10-27
open -a Simulator
INSTALL_SIMULATOR=1 bash Scripts/validate-home-refresh.sh
```

The shared validation path runs the account-safety regression suite, builds
Debug, installs over the existing app, and launches it. It reuses the installed
app's HTTPS API origin if `REPBASE_API_URL` is unset. A first install requires an
explicit configured HTTPS origin. It preserves the app's data.

After a Debug simulator build, `bash Scripts/capture-home-preview.sh APP_PATH`
captures disconnected illustrative fixtures in dedicated simulators. These
include light/dark, populated/empty, cardio, food progress, larger text, Arabic,
Japanese, German, and a narrow device when available. The script cleans up only
simulators it creates.
CI runs this capture when Home presentation changes and uploads `home-previews`.
These screenshots verify layout; they do not prove live account synchronization.

Before accepting the visual refresh, review real-account behavior on the Mac:

- Select another day and return to today; dates, agenda, and workout must match.
- Open View day, the workout action, Log food, and the profile; verify the tab.
- Log food, complete a workout, and return Home; confirm totals and celebrations.
- Check empty days, unavailable steps, active sessions, and retryable errors.
- Review larger text, Reduce Motion, VoiceOver, and the selected app language.

Native CI also builds Release, validates generated API parity and localization,
and runs the existing account-safety tests. A simulator build does not verify
signed device behavior or authorize a release.
