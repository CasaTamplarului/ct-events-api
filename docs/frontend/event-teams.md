# Event Teams API

Admin and volunteer users can create teams for an event, track scores via signed deltas, and view the full score history.

**Auth:** `Authorization: Bearer <jwt>` — requires `can_manage_teams` permission (`admin` and `volunteer` roles only).

**Base path:** `/api/v1/admin/events/:event_slug/teams`

---

## Teams

### GET `/api/v1/admin/events/:event_slug/teams`

List all teams for the event, ordered by creation time ascending.

**Response 200**
```json
[
  { "id": 1, "name": "Echipa Roșie", "icon": "🔥", "colour": "#FF5733", "score": 15 },
  { "id": 2, "name": "Echipa Albastră", "icon": "💧", "colour": "#3399FF", "score": 8 }
]
```

---

### POST `/api/v1/admin/events/:event_slug/teams`

Create a team. At least one of `name`, `icon`, or `colour` must be provided. Missing fields are stored as `null`.

**Request**
```json
{ "name": "Echipa Roșie", "icon": "🔥", "colour": "#FF5733" }
```

**Response 201**
```json
{ "id": 1, "name": "Echipa Roșie", "icon": "🔥", "colour": "#FF5733", "score": 0 }
```

**Response 422**
```json
{ "error": "At least one of name, icon, or colour must be present" }
```

---

### PATCH `/api/v1/admin/events/:event_slug/teams/:id`

Update a team. Send only the fields you want to change.

**Request**
```json
{ "colour": "#E63946" }
```

**Response 200** — updated team object (same shape as POST 201)

**Response 404**
```json
{ "error": "Team not found" }
```

---

### DELETE `/api/v1/admin/events/:event_slug/teams/:id`

Delete a team and all its score entries. Permanent.

**Response 204** — no body

**Response 404**
```json
{ "error": "Team not found" }
```

---

## Score Entries

Score is tracked as append-only deltas. The `score` field on a team object is always the current total.

### POST `/api/v1/admin/events/:event_slug/teams/:event_team_id/score_entries`

Add a score delta. Positive to add, negative to subtract. Zero is rejected.

**Request**
```json
{ "delta": -4 }
```

**Response 201** — includes `score_after` so you can update the displayed score without a separate fetch
```json
{
  "id": 7,
  "delta": -4,
  "score_after": 11,
  "added_by": { "first_name": "Ion", "last_name": "Pop" },
  "created_at": "2026-07-14T10:30:00.000Z"
}
```

**Response 422**
```json
{ "error": "Delta must be a non-zero integer" }
```

---

### GET `/api/v1/admin/events/:event_slug/teams/:event_team_id/score_entries`

Full score history for a team, ordered oldest first. Use this to render a running breakdown like `+12, −4, +7`.

**Response 200** — `score_after` is absent from history entries (only present on the create response)
```json
[
  { "id": 1, "delta": 12, "added_by": { "first_name": "Ion", "last_name": "Pop" }, "created_at": "2026-07-14T09:00:00.000Z" },
  { "id": 2, "delta": -4, "added_by": { "first_name": "Maria", "last_name": "Ionescu" }, "created_at": "2026-07-14T09:45:00.000Z" },
  { "id": 3, "delta": 7,  "added_by": { "first_name": "Ion", "last_name": "Pop" }, "created_at": "2026-07-14T10:30:00.000Z" }
]
```

---

## Real-Time Updates (Action Cable)

All team mutations are broadcast over WebSocket so every connected admin/volunteer sees changes instantly.

### Connecting

```js
const cable = createConsumer(`wss://your-api/cable?token=${jwt}`)
```

Subscribe to an event's team channel:

```js
const subscription = cable.subscriptions.create(
  { channel: 'EventTeamsChannel', event_slug: 'concert-summer-2026' },
  { received(data) { handleMessage(data) } }
)
```

The connection rejects if the JWT is missing/invalid or the user lacks `can_manage_teams`.

### Message types

All messages arrive as parsed objects with a `type` string field.

**`team_created`** — a new team was added

```json
{
  "type": "team_created",
  "team": { "id": 3, "name": "Echipa Verde", "icon": "🌿", "colour": "#16A34A", "score": 0 }
}
```

**`team_updated`** — name, icon, or colour changed

```json
{
  "type": "team_updated",
  "team": { "id": 3, "name": "Echipa Verde", "icon": "🌿", "colour": "#15803D", "score": 0 }
}
```

**`team_deleted`** — team and all its score entries removed

```json
{
  "type": "team_deleted",
  "team_id": 3
}
```

**`score_updated`** — a score delta was applied; `team.score` is the new total

```json
{
  "type": "score_updated",
  "team": { "id": 1, "name": "Echipa Roșie", "icon": "🔥", "colour": "#FF5733", "score": 11 },
  "entry": {
    "id": 7,
    "delta": -4,
    "added_by": { "first_name": "Ion", "last_name": "Pop" },
    "created_at": "2026-07-14T10:30:00.000Z"
  }
}
```

Note: `score_after` is absent from the broadcast entry — use `team.score` instead.

### Suggested handler

```js
function handleMessage(data) {
  switch (data.type) {
    case 'team_created':
      addTeam(data.team)
      break
    case 'team_updated':
      updateTeam(data.team)
      break
    case 'team_deleted':
      removeTeam(data.team_id)
      break
    case 'score_updated':
      updateTeam(data.team)   // replaces the whole team object — score is already updated
      appendScoreEntry(data.team.id, data.entry)
      break
  }
}
```

Fetch the initial team list via REST on mount; the WebSocket keeps it live after that.

---

## Error Reference

| Status | When |
|--------|------|
| `401` | Missing or invalid JWT |
| `403` | User role lacks `can_manage_teams` (`attendee`, `leader`, `staff`) |
| `404` | Event slug not found, or team ID doesn't belong to this event |
| `422` | Validation failure — see error message in body |

---

## Notes

- **`icon`** — store a single emoji. No server-side validation; enforce the format client-side.
- **`colour`** — hex string with `#` prefix e.g. `#FF5733`. No server-side format validation.
- **`score_after`** — only present in the POST score entry response. Use it to update the UI; no need to re-fetch the team.
- **`:event_team_id`** — the score entry routes use `event_team_id` (not `id`) for the team segment. The value is the same integer from the team object.
- **Score history is append-only.** Individual entries cannot be deleted. Deleting the team deletes all its entries.
