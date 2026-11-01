# Layered Home presentation

Approved Figma: [Home review, light and dark](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy?node-id=191-5518).
The light implementation follows `191:5636`; dark follows `191:6047`.

Scope: Home presentation only, on `work/testflight-fixes-2026-10-27`.
`backup/pre-home-layered-ui-2026-11-01` preserves the preceding UI at `bd7a1c6`.
Training, Food, Calendar, Social, and Account require individual Figma review
before adopting these styles. No API, database, store, or navigation contract
changes are part of this work.

Home uses a sage week backdrop in light mode and a warm dark backdrop, a rounded
foreground sheet, full-width cards, raised action labels, and recessed live
progress indicators. Named light/dark assets and `RepbaseTactileDesign.swift` are
opt-in; the existing global palette and other screens are unchanged. Background
shapes cast the shadows without rasterizing each card's content. All displayed
steps, dates, workouts, food totals, goals, errors, and actions retain their
existing stores and routes. Personalization still determines section order.
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
include light/dark, populated/empty, food progress, larger text, Arabic, and a
narrow device when available. The script cleans up only simulators it creates.
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
