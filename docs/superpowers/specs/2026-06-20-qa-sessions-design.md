# Q&A Sessions — API Design Spec

**Date:** 2026-06-20
**Scope:** Rails API only (`ct-events-api`). Frontend implementation is handled separately.

---

## Overview

Staff (admin role) can create multiple Q&A sessions for an event — one per talk, panel, or time slot. Each session has a short random code that forms a public URL. Anyone with that URL can submit questions. Admins can view and moderate questions from the webapp staff area.

---

## Data Model

### `qa_sessions`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `event_id` | bigint FK → events | cascade delete |
| `code` | string(8) | random alphanumeric, unique, indexed |
| `status` | integer enum | `open` (0) / `closed` (1), default: `open` |
| `voting_enabled` | boolean | default: `true` |
| `questions_public` | boolean | whether attendees see each other's questions, default: `true` |
| `created_by_user_id` | bigint FK → users | |
| `created_at` | datetime | |
| `updated_at` | datetime | |

### `qa_session_translations`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `qa_session_id` | bigint FK → qa_sessions | cascade delete |
| `languages_code` | string FK → languages | |
| `name` | string | not null |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Unique index on `(qa_session_id, languages_code)`.

### `qa_questions`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `qa_session_id` | bigint FK → qa_sessions | cascade delete |
| `body` | text | not null |
| `display_name` | string | nullable — null means posted anonymously |
| `user_id` | bigint FK → users | nullable — set when submitter is authenticated |
| `submitter_token` | string | nullable — UUID for anonymous submitters |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Index on `qa_session_id`.

### `qa_votes`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigint PK | |
| `qa_question_id` | bigint FK → qa_questions | cascade delete |
| `value` | integer | `+1` or `-1` |
| `user_id` | bigint | nullable |
| `voter_token` | string | nullable |
| `created_at` | datetime | |
| `updated_at` | datetime | |

Unique partial index on `(qa_question_id, user_id) WHERE user_id IS NOT NULL`.
Unique partial index on `(qa_question_id, voter_token) WHERE voter_token IS NOT NULL`.

---

## API Routes

### Admin endpoints

Require JWT with `role == 'admin'`. Implemented via a `require_admin!` before-action that checks `current_user.role == 'admin'` and returns `403` otherwise.

```
GET    /api/v1/admin/events/:event_slug/qa_sessions          # list sessions for an event
POST   /api/v1/admin/events/:event_slug/qa_sessions          # create session
PATCH  /api/v1/admin/qa_sessions/:code                       # update session (open/close, settings, name)
DELETE /api/v1/admin/qa_sessions/:code                       # delete session
GET    /api/v1/admin/qa_sessions/:code/questions             # list all questions (ranked by score)
DELETE /api/v1/admin/qa_sessions/:code/questions/:id         # remove any question
```

### Public endpoints

No authentication required. Identity resolved via `X-QA-Token` header (UUID) for anonymous callers, or JWT for authenticated users (JWT takes precedence when both are present).

```
GET    /api/v1/events/:event_slug/qa/:code                   # session info + questions
POST   /api/v1/events/:event_slug/qa/:code/questions         # submit a question
DELETE /api/v1/events/:event_slug/qa/:code/questions/:id     # delete own question
POST   /api/v1/events/:event_slug/qa/:code/questions/:id/vote  # cast or toggle vote
```

---

## Controller Structure

```
app/controllers/api/v1/
  admin/
    qa_sessions_controller.rb       # CRUD for sessions
    qa_questions_controller.rb      # list + delete (admin view)
  qa_sessions_controller.rb         # public show
  qa_questions_controller.rb        # public submit + delete own
  qa_votes_controller.rb            # public vote toggle

app/models/
  qa_session.rb
  qa_session_translation.rb
  qa_question.rb
  qa_vote.rb
```

---

## Identity Resolution

A `QaIdentifiable` concern on the base controller resolves the caller for public endpoints:

```ruby
def current_qa_identity
  if current_user
    { user_id: current_user.id, voter_token: nil }
  else
    { user_id: nil, voter_token: request.headers["X-QA-Token"].presence }
  end
end
```

`current_user` is resolved via the existing JWT logic (returns `nil` if no valid token). This means an authenticated user's actions are always tied to their account; an anonymous user is identified solely by their UUID token.

---

## Response Shapes

### Public session show — GET `/api/v1/events/:event_slug/qa/:code`

Query param `?lang=ro-RO` selects the translation for `name`. Falls back to the first available translation.

```json
{
  "code": "xk92p",
  "name": "Session 1",
  "status": "open",
  "voting_enabled": true,
  "questions_public": true,
  "questions": [
    {
      "id": 1,
      "body": "What time does it start?",
      "display_name": "Timo",
      "score": 3,
      "my_vote": 1,
      "can_delete": true,
      "created_at": "2026-06-20T10:00:00Z"
    }
  ]
}
```

- `questions` is an empty array if `questions_public: false`, **except** questions belonging to the current requester are always included.
- `my_vote` — `1`, `-1`, or `null`. Matched by `user_id` or `voter_token`.
- `can_delete` — `true` if the question belongs to this requester.
- `display_name` — the name the submitter chose, or `null` if posted anonymously.
- Questions ordered by `score` descending, then `created_at` ascending as tiebreaker.

### Public question submit — POST `/api/v1/events/:event_slug/qa/:code/questions`

Request body:
```json
{
  "body": "Will there be food?",
  "display_name": "Timo"
}
```

`display_name` is optional — omit or send `null` for anonymous. Returns the created question in the same shape as above (with `my_vote: null`, `can_delete: true`).

Returns `422` if the session is `closed`.

### Vote toggle — POST `/api/v1/events/:event_slug/qa/:code/questions/:id/vote`

Request body:
```json
{ "value": 1 }
```

Logic:
- No existing vote → create it. Returns `201`.
- Same value already exists → delete it (un-vote). Returns `200` with `{ "my_vote": null }`.
- Opposite value exists → update to new value. Returns `200` with `{ "my_vote": -1 }`.

Returns `422` if `voting_enabled: false` or session is `closed`.

### Admin session list — GET `/api/v1/admin/events/:event_slug/qa_sessions`

```json
[
  {
    "code": "xk92p",
    "status": "open",
    "voting_enabled": true,
    "questions_public": true,
    "question_count": 12,
    "translations": [
      { "languages_code": "ro-RO", "name": "Sesiunea 1" },
      { "languages_code": "en-US", "name": "Session 1" }
    ],
    "created_at": "2026-06-20T09:00:00Z"
  }
]
```

### Admin questions list — GET `/api/v1/admin/qa_sessions/:code/questions`

Same question shape as public, but:
- Always returns all questions regardless of `questions_public`.
- `display_name` shows the stored value (admin sees who submitted, or null for anonymous — frontend can display "Anonymous").
- Always includes `score`, `my_vote: null` (admin view, not voting).

---

## Business Rules

- **Session closed:** Submitting questions or voting on a closed session returns `422 Unprocessable Entity`.
- **Voting disabled:** Voting on a session where `voting_enabled: false` returns `422`.
- **Own question delete:** Public delete checks that `qa_question.user_id == current_user.id` (authenticated) or `qa_question.submitter_token == X-QA-Token header` (anonymous). Returns `403` if neither matches.
- **Admin delete:** No ownership check — any admin can delete any question.
- **Score:** Computed as `SUM(value)` across `qa_votes` for the question. Calculated at query time, not stored.
- **Code generation:** 8-character random alphanumeric string (`[A-Z0-9]`), regenerated on collision.
