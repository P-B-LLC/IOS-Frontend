# Grouped notification center — testing only, October 29, 2026

Approved design: [compact grouped activity](https://www.figma.com/design/FbMNgG8cuZfrRFzQTtIVCy/Rytivo-Connected-Flow?node-id=122-1562).

## What changed

- Smaller orange-bordered cards, overlapping actor profile photos, authorized
  photo/video thumbnails, and workout/meal/text fallbacks. The existing app
  typography, navigation, appearance preferences, and image cache are reused.
- No Posts/People filters. All activity is an ordinary section heading.
- One card per post, even across API pages/dates. Distinct people and counts
  of like/comment/repost notifications are calculated separately. The newest
  event determines the group's order and date section. Counts describe
  notification events, not guaranteed current live engagement totals.
- Tap a grouped card to inspect who did what; tap its thumbnail to open the
  post. Single avatars and follower cards open the corresponding profile.
  Follows, requests, approvals, and moderation notices remain separate.
- Only visible event IDs are acknowledged; arrivals outside that displayed
  snapshot remain unread. Loading, refresh, retry, account changes, concurrent
  reads, and block changes have scoped state rather than a shared feed error.
- Dynamic Type can grow cards; accessibility text removes the small trailing
  preview to leave room. Semantic surfaces support dark mode and the accent
  border strengthens with Increase Contrast. New copy covers all ten languages.

## Branches and compatibility

- iOS: `work/testflight-fixes-2026-10-27`,
  [draft PR #39](https://github.com/P-B-LLC/IOS-Frontend/pull/39).
- Backend: `work/testflight-calendar-sync-2026-10-28`,
  [draft PR #36](https://github.com/P-B-LLC/repbase/pull/36).
- Main, the live backend, and TestFlight are not changed by pushing these
  branches. Do not deploy or merge without separate approval.
- API additions are optional `post_preview` and `supports_scoped_read`.
  The backend validates recipient visibility and batches preview queries.
  The Swift client was generated on macOS from the checked-in OAS, not edited
  by hand. Generation evidence: [run 40941022760](https://github.com/P-B-LLC/IOS-Frontend/actions/runs/40941022760).
- On the unchanged live backend, avatars and grouping work but new thumbnails
  are unavailable. The app deliberately skips selective read writes when the
  capability is absent: the old endpoint would otherwise ignore the IDs and
  mark every notification read. Full preview/read testing requires the matching
  backend branch in a test environment.
- The existing iOS PR currently conflicts with newer main work. CI now permits
  manual dispatch of the same checks on a branch, with no additional permissions
  and no release step. A branch-only CI pass is not a merged-main validation.

## Validation

Windows checks: Swift syntax parsing, stable decoded IDs, matching iOS/backend
notification schemas, shell syntax, localization JSON/placeholder/plural checks,
and diff hygiene. These are not an Xcode build or rendered UI validation.

The first Mac build exposed a missing `import Vision` in the earlier barcode
scanner work on this shared branch. The one-line import is included so that the
complete branch can compile; barcode behavior is otherwise unchanged.

`NotificationActivityTests` covers grouping, distinct actors, deduplication,
latest ordering, missing previews, non-post events, legacy DTO decoding, scoped
read batches, retries, new arrivals, and read-state reset/reconciliation.
Run through `bash Scripts/test-account-safety.sh` on macOS.

To rebuild on the Mac, from the iOS checkout:

```sh
git fetch origin
git switch work/testflight-fixes-2026-10-27
git pull --ff-only
# Keep REPBASE_API_URL set to your configured HTTPS testing API origin.
INSTALL_SIMULATOR=1 bash Scripts/validate-social-refresh.sh
```

Open Social > bell. Before promotion verify:

1. Several people like/comment/repost one post: one card, separate correct
   action counts, distinct avatars, and a readable activity detail.
2. A post spanning Yesterday/Today appears once under its newest event.
3. Avatar, follower-card, activity-body, and post-thumbnail routes are correct.
4. Empty inbox, slow loading, failed refresh, failed read acknowledgement,
   missing/deleted media, photos, videos (thumbnail only), meals and workouts.
5. Refresh while a card remains visible: new represented events are marked,
   but off-screen activity is not. New arrivals during an acknowledgement stay
   unread. Older servers never receive the new selective write.
6. Private/follower-only, hidden, blocked, suspended, and held content stays
   unavailable; account switches and blocking do not retain old previews.
7. Light/dark, Increase Contrast, accessibility text, VoiceOver, long names,
   Arabic RTL, and scrolling above the persistent bottom navigation.

Simulator/device appearance and interaction checks must be performed against
real test accounts before release; Figma sample portraits are not app assets.
