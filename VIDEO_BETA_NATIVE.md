# Native limited video beta

Implementation branch: `feat/video-beta`. Backend: repbase `feat/video-processing`.
These branches preserve existing main and live account-control work; they are
not silently merged into the release branches.

## Build on the Mac

First check `git status --short`. Preserve any local Xcode/project edits before
switching branches; do not discard them. Once the checkout is clean:

```sh
git fetch origin
git switch feat/video-beta
git pull --ff-only
REPBASE_API_URL=https://rytivo.app INSTALL_SIMULATOR=1 bash Scripts/validate-video-beta.sh
```

Boot a simulator first when using `INSTALL_SIMULATOR=1`. Omit that variable
to build and test without installing. This is simulator validation, not a
signed TestFlight build or actual-device playback test.

## Device checklist

- Attach a supported H.264/HEVC MP4/MOV from Photos. Check portrait/landscape,
  light/dark mode, VoiceOver labels, iCloud-backed selection and picker cancel.
- Reject >15 MiB, >30 seconds, >1080p and >60fps before creating a post.
- Post a private clip. It should show processing, then ready after Refresh.
- Confirm playback starts only on a tap, native controls work, loading/errors
  are clear, and scrolling away/backgrounding/logout stops the player.
- Disconnect during upload and retry: the saved post ID must be reused, and
  a lost response must not replace an already queued or ready clip.
- After processing fails, use Choose another video on your own post. Other
  accounts must not see this control or gain replacement permission.
- Test public/follower/private permissions, blocking and takedown during
  playback. The backend rechecks each newly requested asset, including Range.
- Inspect actual deployed nginx 206/HEAD behavior and bandwidth logs. A
  simulator build and isolated encoder tests do not prove this end to end.

Large video bytes remain files during import and upload. HTTPBody reads pull
64 KiB chunks and fails if file length changes. Transcoding is server-side;
AVPlayer is not created for every feed row. Approved/ready URLs are refreshed
before playback rather than relying on an expired feed URL.

Temporary moderation bypass is confined to the explicitly authorized limited
beta; this is not a declaration that unreviewed UGC meets public launch rules.

## Camera-first posting

Every existing post entry point uses the same media-first composer. On a device
with a camera it requests camera access and opens system photo/video capture.
Camera roll is available from capture and from the fallback screen. Selecting
media continues to the existing framing, caption, logged source and visibility
controls; fixed meal/workout/planner references are preserved. Media remains
optional via an explicit Continue without media action.

The simulator has no camera: use Choose from camera roll there. A microphone
denial leaves photo capture available; video capture requires microphone access.
Captured videos are copied to the owned draft directory before camera dismissal,
then pass the same file-size/codec/duration/resolution checks as library videos.
Posting is disabled during imports and photo framing. Failed imports have an
explicit remove/continue path; video upload retries keep the saved post ID.

Validation still required for this change: Xcode build, simulator library
selection/crop/cancel, and physical-device photo/video capture, permission denial,
camera-roll switching, front/rear camera, backgrounding and repeated opens.
Windows source checks and plist parsing are not native compile/runtime results.
