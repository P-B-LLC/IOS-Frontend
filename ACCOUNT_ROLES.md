# iOS administration entry

Settings → Roles & permissions presents the configured backend's HTTPS `/access/`
workspace inside SFSafariViewController. This is a backend-rendered administration
screen, not a new native role editor. It supports role assignment, analytics,
and report review after a separate authorized sign-in.

No app token is copied to a web view, cookie, JavaScript context, or URL. The
server owns the grants and checks each operation. A standard user who opens
this settings row cannot grant themself access. The portal shows the username
of its session so staff can verify which account they are administering from.
The portal session is separate from app sign-in, has a 30-minute expiry, and
has its own Sign out button. Done dismisses the browser but does not sign out.

Deploy the matching `repbase` and `rytivo-web` `feature/account-roles` branches
and their nginx `/access/` route first; see backend `deploy/ACCOUNT_ROLES.md`.
This iOS change makes no new JSON API calls, changes no OAS DTOs and requires
no generated-client changes. It adds only the secure in-app browser and settings
entry. The original worktree and unrelated edits were left untouched.

**Pending:** Xcode build and simulator/device validation. SSH to the configured
Mac closed the connection during implementation; no iOS build success is claimed.
No deployment, push, or real-account role changes have been performed.
