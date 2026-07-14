# Event Teams Real-Time — Design Spec

## Goal

Broadcast all team mutations (create, update, delete, score change) over Action Cable so every connected admin/volunteer sees the teams scoreboard update instantly without polling.

## Architecture

Follows the existing `QaQuestionsChannel` + `QaBroadcastable` pattern exactly.

- One Action Cable channel (`EventTeamsChannel`) per event, keyed by `event_slug`
- One broadcastable concern (`EventTeamBroadcastable`) included in both team controllers
- Controllers call broadcast methods after every successful mutation

## Channel

**File:** `app/channels/event_teams_channel.rb`

Clients subscribe with:
```json
{ "channel": "EventTeamsChannel", "event_slug": "concert-summer-2026" }
```

On `subscribed`:
1. Reject if `event_slug` param is blank
2. Reject if `Event.find_by(slug: event_slug)` is nil
3. Reject if `current_user` is nil (no valid JWT)
4. Reject if `current_user` lacks `can_manage_teams` permission
5. Otherwise: `stream_from "event_teams_#{event_slug}"`

Stream key: `event_teams_#{event_slug}`

**Connection auth:** existing `ApplicationCable::Connection` reads `?token=<jwt>` from the WebSocket URL and sets `current_user` (nil if missing/invalid). No changes needed to the connection class.

## Broadcastable Concern

**File:** `app/controllers/concerns/event_team_broadcastable.rb`

Private methods, one per mutation type:

### `broadcast_team_created(team)`
```json
{
  "type": "team_created",
  "team": { "id": 1, "name": "Echipa Roșie", "icon": "🔥", "colour": "#FF5733", "score": 0 }
}
```

### `broadcast_team_updated(team)`
```json
{
  "type": "team_updated",
  "team": { "id": 1, "name": "Echipa Roșie", "icon": "🔥", "colour": "#E63946", "score": 0 }
}
```

### `broadcast_team_deleted(team)`
```json
{
  "type": "team_deleted",
  "team_id": 1
}
```

### `broadcast_score_updated(team, entry)`
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

Note: `score_after` is not included in the broadcast entry payload — the `team.score` field carries the updated total. The `score_after` field remains only in the REST create response.

All four methods broadcast to `event_teams_#{team.event.slug}`.

## Controller Changes

### `EventTeamsController`

Include `EventTeamBroadcastable`. Call after successful write:

| Action | Broadcast call |
|---|---|
| `create` (201) | `broadcast_team_created(@team)` |
| `update` (200) | `broadcast_team_updated(@team)` |
| `destroy` (204) | `broadcast_team_deleted(@team)` |

Broadcast is called after `render` — fire-and-forget, no effect on the HTTP response.

### `EventTeamScoreEntriesController`

Include `EventTeamBroadcastable`. Call after successful write:

| Action | Broadcast call |
|---|---|
| `create` (201) | `broadcast_score_updated(@team, entry)` |

Called inside or after the transaction, after `render`.

## Message Types Summary

| `type` | Triggered by | Key fields |
|---|---|---|
| `team_created` | POST /teams | `team` object |
| `team_updated` | PATCH /teams/:id | `team` object |
| `team_deleted` | DELETE /teams/:id | `team_id` |
| `score_updated` | POST /teams/:id/score_entries | `team` object, `entry` object |

## Files Created / Modified

| File | Action |
|---|---|
| `app/channels/event_teams_channel.rb` | Create |
| `app/controllers/concerns/event_team_broadcastable.rb` | Create |
| `app/controllers/api/v1/admin/event_teams_controller.rb` | Modify — include concern, add broadcast calls |
| `app/controllers/api/v1/admin/event_team_score_entries_controller.rb` | Modify — include concern, add broadcast call |

No migration needed. No changes to `config/cable.yml`, `ApplicationCable::Connection`, or routes.

## Out of Scope

- Broadcasting to unauthenticated or non-admin/volunteer clients
- Sending initial state on subscribe (client fetches via REST on mount)
- Presence tracking (who is connected)
- Broadcasting team index order changes (order is creation time, immutable)
