# Event Teams — Design Spec

## Goal

Allow admin and volunteer users to create and manage teams within an event. Each team has an optional name, emoji icon, and colour. A score is tracked via a history of signed deltas so staff can see a full audit trail (e.g. +12, −4, +1).

---

## Data Model

### `event_teams`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `event_id` | bigint FK → `events` | not null |
| `name` | string | nullable |
| `icon` | string | nullable — single emoji character |
| `colour` | string | nullable — hex string e.g. `#FF5733` |
| `score` | integer | not null, default 0 — denormalised sum of all deltas |
| `created_at` / `updated_at` | timestamps | |

**Validation:** at least one of `name`, `icon`, `colour` must be present (non-blank). All three may be provided. Enforced at the model layer.

### `event_team_score_entries`

| Column | Type | Notes |
|---|---|---|
| `id` | bigint PK | |
| `event_team_id` | bigint FK → `event_teams` | not null |
| `delta` | integer | not null — positive = add, negative = subtract |
| `added_by_user_id` | bigint FK → `users` | not null |
| `created_at` | timestamp | |

`score` on `event_teams` is kept in sync by incrementing it by `delta` in the same transaction as the entry insert — no `SUM` query needed on read.

---

## Auth

Add `can_manage_teams: true` to both `admin` and `volunteer` in `User::ROLE_PERMISSIONS`. All team and score-entry endpoints are gated with `require_permission!(:can_manage_teams)`.

---

## API Endpoints

All routes are namespaced under `/api/v1/admin/events/:event_slug/teams`.

### Teams

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/v1/admin/events/:event_slug/teams` | List all teams for the event |
| `POST` | `/api/v1/admin/events/:event_slug/teams` | Create a team |
| `PATCH` | `/api/v1/admin/events/:event_slug/teams/:id` | Update name / icon / colour |
| `DELETE` | `/api/v1/admin/events/:event_slug/teams/:id` | Delete team and all its score entries |

### Score Entries

| Method | Path | Description |
|---|---|---|
| `POST` | `/api/v1/admin/events/:event_slug/teams/:id/score_entries` | Add a score delta |
| `GET` | `/api/v1/admin/events/:event_slug/teams/:id/score_entries` | List score history |

---

## Request / Response Shapes

### POST /teams

**Request:**
```json
{ "name": "Echipa Roșie", "icon": "🔥", "colour": "#FF5733" }
```
All three fields optional but at least one required. Missing fields stored as `null`.

**Response 201:**
```json
{ "id": 1, "name": "Echipa Roșie", "icon": "🔥", "colour": "#FF5733", "score": 0 }
```

**Response 422:**
```json
{ "error": "At least one of name, icon, or colour must be present" }
```

---

### PATCH /teams/:id

**Request:** any subset of `{ name, icon, colour }`. Only supplied fields are updated.

**Response 200:** same shape as POST response with updated values and current score.

**Response 404:** `{ "error": "Team not found" }` if team does not belong to the event.

---

### DELETE /teams/:id

**Response 204:** no body. Deletes team and all associated score entries.

**Response 404:** `{ "error": "Team not found" }`.

---

### GET /teams

**Response 200:**
```json
[
  { "id": 1, "name": "Echipa Roșie", "icon": "🔥", "colour": "#FF5733", "score": 15 },
  { "id": 2, "name": "Echipa Albastră", "icon": "💧", "colour": "#3399FF", "score": 8 }
]
```

Ordered by `created_at ASC`.

---

### POST /teams/:id/score_entries

**Request:**
```json
{ "delta": -4 }
```
`delta` must be a non-zero integer. Zero is rejected (no-op entries are meaningless).

**Response 201:**
```json
{
  "id": 7,
  "delta": -4,
  "score_after": 11,
  "added_by": { "first_name": "Ion", "last_name": "Pop" },
  "created_at": "2026-07-14T10:30:00.000Z"
}
```

`score_after` is the team's score after this entry was applied — lets the FE render the running total without a separate fetch.

**Response 422:** `{ "error": "Delta must be a non-zero integer" }`

---

### GET /teams/:id/score_entries

**Response 200:**
```json
[
  { "id": 1, "delta": 12, "added_by": { "first_name": "Ion", "last_name": "Pop" }, "created_at": "..." },
  { "id": 2, "delta": -4, "added_by": { "first_name": "Maria", "last_name": "Ionescu" }, "created_at": "..." },
  { "id": 3, "delta": 7,  "added_by": { "first_name": "Ion", "last_name": "Pop" }, "created_at": "..." }
]
```

Ordered by `created_at ASC`. No pagination — score histories are expected to be short.

---

## Files Created / Modified

| File | Action |
|---|---|
| `db/migrate/…_create_event_teams.rb` | Create `event_teams` table |
| `db/migrate/…_create_event_team_score_entries.rb` | Create `event_team_score_entries` table |
| `app/models/event_team.rb` | Model + validations |
| `app/models/event_team_score_entry.rb` | Model |
| `app/models/user.rb` | Add `can_manage_teams` permission |
| `app/controllers/api/v1/admin/event_teams_controller.rb` | CRUD controller |
| `app/controllers/api/v1/admin/event_team_score_entries_controller.rb` | Score entry controller |
| `config/routes.rb` | Nested routes |
| `spec/models/event_team_spec.rb` | Validation specs |
| `spec/requests/api/v1/admin/event_teams_spec.rb` | Request specs |
| `spec/requests/api/v1/admin/event_team_score_entries_spec.rb` | Score entry specs |

---

## Out of Scope

- Public-facing read endpoint for teams (not needed yet)
- Assigning attendees to teams
- Deleting individual score entries (history is append-only)
- Score entry editing
