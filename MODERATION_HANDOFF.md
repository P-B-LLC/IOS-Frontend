# Moderation integration — 15 September 2026

## Release update — 14 October 2026

- iOS PR #28 merged to `main` at `949be5cf3519f781b0635e7c5b82b981d2e22421`.
  Native validation run 38432036335 passed. Changes are committed in
  `IOS Frontend/IOS Frontend/Stores/SocialStore.swift` and
  `IOS Frontend/IOS Frontend/Views/Social/PostModerationViews.swift`.
- Other users' post menu → Report post remains the entry point. Every reason now
  allows optional details (500 characters), with guidance not to include unnecessary
  personal information. Failures retain the form for retry; sending disables
  dismissal; success/duplicate feedback does not promise an outcome.
- Backend PR #28 is merged to main (`a806e48`); production was verified running
  `92ed275` with migration `0070_post_report_distinct_reasons` applied. Duplicate
  protection now includes the reason, allowing distinct violations on one post.
- Moderator workspace: Administration → Reports (`/access/reports/`) shows exact
  post context, media previews, shared snapshots and confidential report notes.
  Authorized moderators can keep content or remove it from the community with an
  audited decision reason. Unavailable media is not treated as reviewed.
- Existing status mapping remains pending/unreviewed, hidden/resolved, and
  no_action/dismissed; no new under-review assignment feature was introduced.
- Developers should pull main and rebuild. No new simulator/device install or
  TestFlight upload was performed by this release. Physical-device and end-to-end
  moderator testing remain necessary. Automated moderation and HTTPS hardening
  warnings remain open; see backend MODERATION_OPERATIONS.md for deployment facts.

The matching backend changes live in the `repbase` repository. Its
`MODERATION_OPERATIONS.md` is the operational release checklist, including human
review, provider activation and privacy requirements. This file records the iOS
integration; it is not an App Review approval or a closed beta gate.

## Included

- Per-submission permission before sending public text/photos for OpenAI review.
  Cancellation prevents the submission; permission is not reused across accounts.
- Public profile edits, photos, prompts, social handles, gym creation, registration,
  posts and comments use the permission flow. Private unshared logs are excluded.
- In-app reporting for comments/replies, with reason, optional detail, failure/retry
  state and a private moderator queue. Reporting does not require AI permission.
- Safety contact: `support@rytivo.app`, including the public legal documents. The
  generated Legal/*.html were stale and still carried a personal address; they are
  regenerated from LegalDocuments.swift, which is the only copy of the wording.
- Generated `socialCommentsReportCreate` client and matching OpenAPI contract.

## Deployment pairing

Deploy backend migration `0054_comment_moderation` through the normal release job
before distributing this build. The backend requires provider credentials and an
explicit operator disclosure gate. Never embed the provider key in the app.

The backend operator gate is not a per-user consent record. Do not enable provider
transmission for legacy builds that lack the permission flow. If any older clients
remain active, add server-enforced version/consent handling before activation.

Publish the generated `Legal/` pages. Confirm the inbox is monitored, assign a
moderator and backup, and schedule the backend overdue-report check with alerts.

## Verification still required on the release environment

- Physical-device acceptance/cancellation, including registration and photo upload.
- Allowed/rejected content and provider outages with controlled fixtures.
- Report retry, duplicate submission, moderator takedown and block/unblock using
  separate accounts; check replies, reposts and notifications.
- Privacy disclosures, hosted legal URLs, accessibility and light/dark appearance.

The unsigned iOS Simulator Release build passed on the validation Mac. That does
not verify device signing, TestFlight distribution or live provider behavior.
