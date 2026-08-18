# 📱 App Roadmap

> Living document — fill this in together, edit freely. Claude can turn any section
> into concrete tasks/milestones. Last updated: 2026-08-09

---

## 1. The Idea (one paragraph)
_What is the app, in plain language? If you had 15 seconds to pitch it to a stranger, what would you say?_

<!-- write here -->

## 2. The Problem / Why
_What problem does it solve, or what does it make easier/more fun? Who feels this problem?_

<!-- write here -->

## 3. Who It's For (target users)
_Who is the ideal first user? Be specific — "college students who X" beats "everyone."_

<!-- write here -->

## 4. Core Features (the must-haves)
_The 3–5 things the app MUST do to be worth using. Keep it ruthless — everything else is "later."_

- [ ]
- [ ]
- [ ]

## 5. Nice-to-Haves (later / v2)
_Cool ideas that are NOT needed for the first version. Park them here so you don't forget._

- [ ]
- [ ]

## 6. Screens / Flow (rough)
_List the main screens and how a user moves between them. Sketch-level is fine._

1. **Launch / Home** →
2.
3.

## 7. Data & Backend (what needs to be stored?)
_What information does the app remember? Accounts? A database? External APIs? (Note: this repo is the **frontend** — decide where the backend/data lives.)_

<!-- write here -->

## 8. Milestones (the roadmap)
_Break the build into phases. Rough order below — adjust as you go._

- [ ] **M0 — Setup** ✅ Repo + Windows↔GitHub↔Mac/Xcode pipeline working
- [ ] **M1 — Skeleton** App builds with core screens navigable (no real data)
- [ ] **M2 — Core feature #1** (name it): _______________
- [ ] **M3 — Core feature #2** (name it): _______________
- [ ] **M4 — Data/persistence** wired in
- [ ] **M5 — Polish** (design, icons, edge cases)
- [ ] **M6 — TestFlight / first real users**

## 9. Roles & Ownership
_Who's doing what? (Frontend / design / backend / testing.)_

| Area | Owner |
|------|-------|
| Frontend (SwiftUI) | |
| Design / UI | |
| Backend / data | |
| Testing | |

## 10. Open Questions / Decisions to Make
_Anything you're unsure about — dump it here so it's not lost._

- [ ] Is a day's "workout" one **named group of many exercises** (e.g. "Push" = Bench + OHP + …)? (Confirm Workout → Exercise → Set hierarchy.)
- [ ] "Plates on each side" math: what **bar weight** to assume, and **lb or kg**?
- [ ] **Local-first** (SwiftData) now vs. **backend** from the start? (Multiplayer + social force a backend eventually.)
- [ ] **Accounts / auth** — needed for co-op + social; defer until then?

## 11. Tracking Workout Workflow (from handwritten notes, 2026-08-10)

**Pages**
- **Home** — compact weekly schedule strip (7 days across the top). Tap → Workouts. ✅ *(widget built)*
- **Workouts** — tap a day to assign a workout. "Add Workout" = name → add exercises, each with a set count.
- **Progress** — progression graphs (weight × reps, weight × time), fed from logged sessions by date.
- **Session (live tracking)** — the core loop:
  1. Open a day's workout → **Start Session** → entry fields cleared/prepared.
  2. Per exercise/set, log **weight + reps**; option to enter **plates-per-side** instead of total weight (app computes total).
  3. **Log** → push to backend → progression graphs update live.
  4. Entered weights **persist as defaults** until the next Start Session.
  5. **End Session** → save, note weight improvements.
  6. **Invite to Session** → co-op: both users see each other's entries in real time.
  7. *Future:* auto social post highlighting weight improvements.

**Data model direction:** `Workout` = name + `[Exercise]` (each with a target set count); `Session` = date + workout + logged `SetEntry`s (weight or plates-per-side, reps); Progress derived from Session history. Suggested approach: build the frontend **local-first with SwiftData**, stub the sync boundary, wire a backend later so we're never blocked.

---

### Notes
- Anyone can edit this file, commit, and push — it syncs across both machines.
- When ready, tell Claude "turn the roadmap into tasks" and it'll break milestones into concrete steps.
