# iOS integration map

`openapi.yaml` is the source of truth for the Repbase backend. The current app
is an empty, local workout-planning prototype; it must not be treated as the
backend data model.

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
transport, and HTTP Types packages. This keeps the app target's actor-isolation
settings from changing the generated wire code. Supply the server URL at
runtime because the OAS does not declare one.

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

Workout creation is a multi-request flow: resolve or create catalog exercises,
create the workout template, create ordered workout-exercise relations, and
then create the schedule entry. The contract does not define a transaction or
idempotency key, so the UI must await each result and surface partial failure
recovery rather than dismissing optimistically.

## Domain changes required before live workout data

- Replace recurring `[Weekday: Workout]` persistence with a date-based schedule.
  Weekday names remain presentation only.
- Preserve integer IDs for the schedule, workout template, exercise catalog
  record, and workout-exercise relation.
- Separate editable drafts from persisted domain objects and generated DTOs.
- Represent `target_sets`, `target_reps`, and `target_weight_kg` as optional;
  zero is permitted by the current contract.
- Decide whether editing a template from a day changes every scheduled use or
  clones the template. The API models templates as reusable.

## Authentication and loading

Login and registration return an opaque token. Store it in Keychain, prepend
`Token ` in the authorization header, and validate a restored token with
`GET /api/v1/me/`. Cookie authentication is not used by the iOS client.

The list APIs accept only `page`; schedules cannot currently be filtered by
date and child resources cannot be filtered by parent. Follow every trusted
`next` URL, then join and filter results locally until the backend adds filters.

## Contract gaps blocking live integration

1. The deployment HTTPS origin/base URL is not supplied.
2. Error response status codes and bodies are absent from the OAS.
3. Schedule uniqueness and timezone behavior are not specified.
4. Multi-request workout creation has no transactional or rollback contract.

The first safe live slice is authentication plus a read-only current-week view:
fetch every page of schedules and workouts, join them by workout ID, and map the
results into seven concrete dates. Enable remote create/edit/delete only after
the template-edit and partial-failure behavior above is decided.
