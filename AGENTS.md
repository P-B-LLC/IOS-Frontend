# Repository instructions

## Backend API contract

- `API/openapi.yaml` is the canonical contract for every backend request and
  response. `API/API.md` is supporting prose; where they disagree, follow the
  OpenAPI document and record the discrepancy.
- Do not invent endpoints, fields, enum values, error bodies, pagination
  parameters, or ownership rules. Change the backend contract first when a
  feature cannot be represented by the OAS.
- Keep API DTOs separate from SwiftUI/domain models. Generate wire types and
  operation code from the committed OAS; never hand-edit generated output.
- Generated sources are committed under `API/GeneratedSources`. After any OAS
  or generator-config change, run `bash Scripts/generate-api-client.sh` on
  macOS and commit the complete regenerated diff. The command plugin is used
  ahead of time because Xcode 26.6 incorrectly links the build plugin's
  host-only implementation into iOS builds.
- Preserve the trailing slash on documented endpoint paths.

## iOS integration rules

- The OAS has no `servers` entry. Read an HTTPS API origin from environment or
  build configuration; never guess or hardcode a deployment host.
- Use token authentication on iOS. Store only the opaque token in Keychain and
  send `Authorization: Token <token>`. Never put credentials or tokens in
  source, logs, previews, `UserDefaults`, or fixtures.
- Treat backend resource IDs as integers. Local-only draft IDs may use UUIDs,
  but they must not replace or masquerade as server IDs.
- Decode decimal JSON strings through `Decimal`, not `Double`. Store weights in
  kilograms and convert only for display according to `unit_preference`.
- Treat `scheduled_date` as a literal `YYYY-MM-DD` calendar date. A schedule is
  a concrete date assignment, not a recurring weekday. Retain both schedule and
  workout IDs; deleting a schedule must not delete its workout template.
- A planned exercise combines an `Exercise` catalog record with a
  `WorkoutExercise` relation. Preserve both IDs and the relation's order and
  optional targets.
- Ownership fields are server-derived and must not be sent in request bodies.
- Follow paginated `next` links until exhausted, while requiring the configured
  API origin and HTTPS. Do not assume the first page is complete.
- Handle every undocumented non-2xx response with a generic fallback. The
  current OAS declares only success responses and no stable error schema.
- Perform network work asynchronously and expose explicit loading, saving,
  empty, and retryable error states to SwiftUI.

## Validation

- Validate that `API/openapi.yaml` still parses before committing contract
  changes.
- Regenerate and build the app on macOS after generator or API-boundary
  changes. Generated code is validated by the Xcode build, not by manually
  editing it.
