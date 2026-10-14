# Repbase API

The mobile API is versioned under `/api/v1/`. Interactive documentation is available at `/api/docs/`, and the OpenAPI document is served from `/api/schema/`.

## Authentication

Register or log in to receive an opaque API token. Store the token in the iOS Keychain and send it over HTTPS with every authenticated request:

```http
Authorization: Token <token>
```

Authentication endpoints:

- `POST /api/v1/auth/register/`
- `POST /api/v1/auth/login/`
- `POST /api/v1/auth/rotate-token/`
- `POST /api/v1/auth/logout/`
- `GET /api/v1/me/`
- `PATCH /api/v1/me/`

Token rotation invalidates the token used for the request and returns a replacement. After logout, the token can no longer be used.

## Main resources

- `/api/v1/users/` — limited public profile fields for authenticated users
- `/api/v1/exercises/` — shared and user-created exercises
- `/api/v1/workouts/` — reusable workout templates
- `/api/v1/workout-exercises/` — planned exercises and targets
- `/api/v1/schedules/` — workouts assigned to dates
- `/api/v1/sessions/` — workout sessions owned by the authenticated user
- `/api/v1/session-exercises/` — exercises performed during sessions
- `/api/v1/set-entries/` — actual weight and repetitions
- `/api/v1/body-weight/` — historical body-weight measurements
- `/api/v1/progress/exercises/{exercise_id}/` — exercise progress points

List responses are paginated with `count`, `next`, `previous`, and `results` fields.

## For You

The For You tab is ranked by the server (see `RECOMMENDATIONS.md` in the
backend repository). What the app does with it:

- `GET /api/v1/social/for-you/` without a cursor on open and on pull to
  refresh, then the `next` cursor as the last card appears. Each post carries
  `recommendation.label`, shown under the byline; `reason` is a plain string,
  so an unknown one still shows its label.
- `POST /api/v1/social/impressions/`: which For You cards were at least 60% on
  screen, for how long, and how far into a clip playback got. Batched by
  `Services/ImpressionTracker.swift` (at most 50 a request, sent every ten
  seconds, before every re-rank, and when the tab or app goes away). The
  server records which reason each post was shown for; the app never sends it.
- `POST`/`DELETE /api/v1/social/posts/{id}/not-interested/`: "Not interested"
  in a For You card's menu, undone from the line that replaces the card.
- `GET`/`PATCH /api/v1/social/for-you/preferences/` and
  `DELETE /api/v1/social/for-you/history/`: the Tune sheet -- what For You has
  picked up, hidden topics, personalisation off, start fresh.
- `GET /api/v1/social/suggested-people/` and
  `POST`/`DELETE /api/v1/social/suggested-people/{id}/dismiss/`: people worth
  following, on Discover before a search.

The Following tab is the chronological feed (`/api/v1/social/feed/`).

## Session lifecycle

Create a planned session:

```http
POST /api/v1/sessions/
Content-Type: application/json

{"workout": 1}
```

When a workout is supplied, its exercises are copied into the session. Start and end timestamps cannot be edited directly:

```http
POST /api/v1/sessions/{id}/start/
POST /api/v1/sessions/{id}/end/
```

Valid transitions are `planned → active → completed`. Repeating or skipping a transition returns HTTP `409 Conflict`.

## Data conventions

- Timestamps use ISO 8601 and UTC.
- Weight is stored in kilograms.
- Decimal weights are represented as JSON strings to avoid floating-point precision loss.
- The user's `unit_preference` controls client display, not stored values.
- Resource ownership is derived from the authentication token and cannot be assigned in request bodies.

The committed [OpenAPI schema](openapi.yaml) is the source of truth for request and response shapes.
