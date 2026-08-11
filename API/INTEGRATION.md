# iOS integration map

`openapi.yaml` is the source of truth for the Repbase backend. Authentication,
the current-week workout plan, and workout-session logging are now connected
through the generated client rather than a parallel local persistence model.

## Required boundary

```text
API/openapi.yaml
    -> local RepbaseAPI package
    -> generated Swift operations and DTOs
    -> HTTPS transport with Token authentication
    -> async repositories and DTO/domain mapping
    -> MainActor stores
    -> SwiftUI
```

The root `Package.swift` isolates generated code in a local `RepbaseAPI` module
and pins Apple's Swift OpenAPI Generator, Swift OpenAPI Runtime, URLSession
transport, and HTTP Types packages. Generated sources are committed under
`API/GeneratedSources` and refreshed with:

```bash
bash Scripts/generate-api-client.sh
```

This ahead-of-time CLI workflow avoids an Xcode 26.6 issue that links the build
plugin's host-only implementation into iOS builds. The script also derives a
temporary generation document by removing only
`application/x-www-form-urlencoded` and `multipart/form-data` request variants.
Those variants reuse JSON component schemas in a way that Swift OpenAPI
Generator cannot encode correctly. The canonical OAS remains unchanged, and
the iOS client intentionally uses its JSON variants. The generated result is
compiled on every app build. The OAS has no `servers` entry, so Release reads
`REPBASE_API_URL` from its generated Info.plist. Debug uses
`http://localhost:5000/` with an explicit loopback-only HTTP exception for the
Mac-hosted development backend; that exception cannot enable remote HTTP.

## Workout feature mapping

| App behavior | API operation/model |
| --- | --- |
| Load reusable workouts | Paginate `GET /api/v1/workouts/` (`WorkoutTemplate`) |
| Load calendar assignments | Paginate `GET /api/v1/schedules/` (`WorkoutSchedule`) |
| Show a day | Match the card's concrete date to `scheduled_date` |
| Assign a workout | `POST /api/v1/schedules/` with workout ID and date |
| Remove a day assignment | `DELETE /api/v1/schedules/{id}/` |
| Create a workout | Create `WorkoutTemplate`, then its `WorkoutExercise` rows |
| Edit planned targets | Update the relevant `WorkoutExercise` relation |
| Delete a template | `DELETE /api/v1/workouts/{id}/`; never infer this from unassigning a day |
| Start a session | Create `WorkoutSession`, then call its `start` action |
| Log/unlog a set | Create/delete the matching `SetEntry` |
| Finish a session | Call the `WorkoutSession` `end` action |

Workout creation is a multi-request flow: resolve or create catalog exercises,
create the workout template, create ordered workout-exercise relations, and
then create the schedule entry. The contract does not define a transaction or
idempotency key, so the UI must await each result and surface partial failure
recovery rather than dismissing optimistically.

## Implemented domain boundary

- Weekday tiles are a current-week presentation projection of literal
  `scheduled_date` values, not recurring backend assignments.
- Domain values retain integer schedule, template, exercise,
  workout-exercise, session, session-exercise, and set-entry IDs. UUIDs are
  used only for local draft/view identity.
- `target_sets` preserves nil and zero from the API. Reps and decimal-string
  kilogram weight are written on `SetEntry` records during live sessions.
- Editing from a scheduled day updates its reusable workout template; removing
  a day deletes only the schedule record.

## Authentication and loading

Login and registration return an opaque token. Store it in Keychain, prepend
`Token ` in the authorization header, and validate a restored token with
`GET /api/v1/me/`. Cookie authentication is not used by the iOS client.

The list APIs accept only `page`; schedules cannot currently be filtered by
date and child resources cannot be filtered by parent. Follow every trusted
`next` URL, then join and filter results locally until the backend adds filters.

## Remaining contract gaps

1. A production HTTPS origin still needs to be supplied at deployment time.
2. Error response status codes and bodies are absent from the OAS, so the app
   can only provide generic status-based errors.
3. Schedule uniqueness and timezone behavior are not specified.
4. Multi-request workout creation has no transaction or idempotency key. The
   app reports partial creation instead of pretending the operation rolled
   back.
