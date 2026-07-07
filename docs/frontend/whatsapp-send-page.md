# WhatsApp Broadcast — Frontend Integration Guide

Admin-only feature. Requires a valid JWT for a user with `can_send_whatsapp: true` (admin role only).

All requests: `Authorization: Bearer <token>`, `Content-Type: application/json`.

---

## Concepts

**Template** — a saved Twilio content SID with a human name and a variable schema. Templates are reusable across sends. You manage them once and pick them from a list each time you send.

**Variable** — a named slot in the Twilio template (`{{1}}`, `{{2}}`, etc.). You define which recipient field fills each position. Available field names:

| Field name | Value at send time |
|---|---|
| `first_name` | Recipient's first name |
| `last_name` | Recipient's last name |
| `email` | Recipient's email address |
| `phone_number` | Recipient's phone number |
| `event_name` | Event name (Romanian) |
| `order_reference` | Order reference (e.g. `CT-2026-ABC123`) |

**Broadcast** — one send event. Created when you send to a real audience (not for test sends). Tracked in history so you can exclude those recipients from future sends.

---

## Page Flow

```
1. Pick / create a template
2. Choose audience (all users with phone OR event attendees)
3. (Optional) exclude recipients from a prior broadcast
4. Test send to your own number
5. Send to full audience
```

---

## API Reference

### Templates

#### List saved templates

```
GET /api/v1/admin/whatsapp_templates
```

Response `200`:
```json
[
  {
    "id": 1,
    "name": "Event Reminder",
    "content_sid": "HXabc123",
    "variables": [
      { "position": 1, "name": "first_name" },
      { "position": 2, "name": "event_name" }
    ],
    "created_at": "2026-07-07T10:00:00.000Z"
  }
]
```

Ordered newest first.

---

#### Save a new template

```
POST /api/v1/admin/whatsapp_templates
```

Body:
```json
{
  "name": "Event Reminder",
  "content_sid": "HXabc123",
  "variables": [
    { "position": 1, "name": "first_name" },
    { "position": 2, "name": "event_name" }
  ]
}
```

- `name` — required, human label shown in the UI
- `content_sid` — required, Twilio content SID (starts with `HX`)
- `variables` — ordered array. `position` maps to `{{1}}`, `{{2}}`, etc. in the Twilio template. `name` must be one of the field names in the table above.

Response `201`: same shape as list item.
Response `422`: `{ "error": "Name can't be blank" }`

---

### Broadcasts

#### List broadcast history

```
GET /api/v1/admin/whatsapp_broadcasts
```

Response `200` — last 50 sends, newest first:
```json
[
  {
    "id": 3,
    "template_id": 1,
    "template_name": "Event Reminder",
    "event_id": 26,
    "event_name": "Fara Regrete 2026",
    "recipient_count": 142,
    "sent_at": "2026-07-07T12:30:00.000Z"
  }
]
```

`recipient_count` is `0` while the job is still running; it updates when the job finishes.

---

#### Send (test or bulk)

```
POST /api/v1/admin/whatsapp_broadcasts
```

**Test send — to a single number:**

```json
{
  "template_id": 1,
  "to": "+40700123456",
  "variables": {
    "first_name": "Ion",
    "event_name": "Fara Regrete 2026"
  }
}
```

- `to` — E.164 phone number (must include country code, e.g. `+40…`)
- `variables` — key/value map of the field names used by the template, filled with preview values. Use this to see exactly what the recipient will receive before sending to everyone.
- No broadcast record is created. No tracking.

Response `200`:
```json
{ "sent_to": 1 }
```

Response `400` if `to` key is present but blank:
```json
{ "error": "to is required for test send" }
```

---

**Bulk send — to full audience:**

```json
{
  "template_id": 1,
  "event_id": 26,
  "exclude_broadcast_ids": [1, 2]
}
```

- `template_id` — required
- `event_id` — optional. When present, sends only to attendees of that event (registered users + unregistered attendees who have a phone number). When absent, sends to all users with a phone number.
- `exclude_broadcast_ids` — optional array. Phone numbers that received any of those prior broadcasts are skipped. Use this for re-sends (e.g. to people who registered after the first send).

Sends are queued via Solid Queue. The response returns immediately with an estimate.

Response `200`:
```json
{
  "broadcast_id": 3,
  "queued_for": 147
}
```

`queued_for` is an upper-bound estimate. The actual `recipient_count` on the broadcast record is set accurately after the job finishes.

Response `404` if template not found:
```json
{ "error": "Template not found" }
```

---

## Suggested UI

### Template selector

- Dropdown listing all saved templates (from `GET /api/v1/admin/whatsapp_templates`)
- Each option shows: name + content SID preview
- "Add new template" inline form: name + content SID + variable builder (add rows of position → field name)
- After saving, select the new template automatically

### Audience section

- Toggle: "All users" / "Event attendees"
- If "Event attendees": event picker (same events dropdown used by the email send page)
- "Exclude prior broadcasts" multi-select from `GET /api/v1/admin/whatsapp_broadcasts` (show name + date + recipient count)

### Variable preview

Once a template is selected, show a read-only table of its variables:

| Position | Field | Example value |
|---|---|---|
| 1 | first_name | Ion |
| 2 | event_name | Fara Regrete 2026 |

No input needed — values are filled automatically per recipient at send time.

### Test send

- Phone number input (E.164 format)
- "Preview variables" section: editable key/value fields pre-filled with defaults (e.g. `first_name = "Test"`) so the admin can see a realistic message
- "Send test" button → `POST` with `to` + `variables`

### Send button

- Disabled until template is selected
- On click → `POST` without `to`
- Show: "Queued for ~{queued_for} recipients"
- Poll or push (via the broadcast history) to show final `recipient_count` once the job finishes

---

## Notes

- `recipient_count` will be `0` immediately after sending — it updates when the Solid Queue job completes (usually within seconds to a few minutes depending on audience size).
- `queued_for` can slightly overcount: unregistered attendees who share a phone with a registered user are deduplicated by the job but counted separately in the estimate.
- Phone numbers must be stored in E.164 format on the user/attendee record for sends to work. Numbers without a country prefix will be rejected by Twilio.
- The unsubscribe link is not part of WhatsApp utility messages — no opt-out UI needed on this page.
