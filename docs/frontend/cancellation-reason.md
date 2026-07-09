# Cancellation Reason — Frontend Integration Guide

**Date:** 2026-07-09 · **Auth:** JWT (user's own token)

---

## What changed

Both booking cancellation endpoints now accept two optional body params: a preset reason key and free-form text. Staff receive a push notification automatically — no FE action needed for that.

---

## Preset reason keys

| Key | Romanian label |
|---|---|
| `cant_attend` | Nu pot participa |
| `health` | Motive de sănătate |
| `financial` | Motive financiare |
| `plans_changed` | Schimbare de planuri |
| `other` | Altele |

---

## DELETE /api/v1/auth/me/bookings/:order_reference

Cancels all pending attendees on an order.

### New optional body params

| Param | Type | Notes |
|---|---|---|
| `reason` | string | One of the preset keys above. Omit to leave reason blank. |
| `reason_text` | string | Free-form text. Accepted with or without `reason`. |

### Request examples

**With preset + free text:**
```json
{
  "reason": "health",
  "reason_text": "Am o programare medicală în acea zi."
}
```

**Free text only (no preset selected):**
```json
{
  "reason_text": "Nu pot ajunge din motive personale."
}
```

**No reason (silent cancel):**
```json
{}
```
or send no body at all.

### Responses

| Status | When |
|---|---|
| `200 OK` | Cancel successful (same response as before) |
| `422` | `reason` value is not one of the valid preset keys |

**422 body:**
```json
{ "error": "Invalid cancellation reason" }
```

---

## DELETE /api/v1/auth/me/bookings/:order_reference/attendees/:id

Cancels a single attendee. Same new params, same validation rules.

### Request example

```json
{
  "reason": "plans_changed",
  "reason_text": "Am schimbat planurile pentru acel weekend."
}
```

---

## Suggested UI

### Cancel flow

Show a bottom sheet / modal with:

1. **Optional preset list** — radio buttons or chip group, one per key above. Include a "Skip" or "No reason" option that sends no `reason`.
2. **Optional free text field** — textarea below the presets, always visible. Label: *"Detalii suplimentare (opțional)"*
3. **Confirm button** — triggers the DELETE request with whichever fields the user filled in.

Both fields are optional — users can cancel with no reason at all. Never block the cancel flow on this step; always offer a way to skip.

### Sending the request

```js
// user selected a preset and typed some text
const body = {};
if (selectedReason) body.reason = selectedReason;         // e.g. "health"
if (reasonText.trim()) body.reason_text = reasonText.trim();

await fetch(`/api/v1/auth/me/bookings/${orderRef}`, {
  method: 'DELETE',
  headers: {
    'Authorization': `Bearer ${token}`,
    'Content-Type': 'application/json',
  },
  body: JSON.stringify(body),
});
```

### Error handling

The only new error is an invalid `reason` key (422). This should never appear in production if the preset list is hardcoded in the app — but guard it anyway:

```js
if (res.status === 422) {
  const { error } = await res.json();
  // show error to user, e.g. toast
}
```

---

## Notes

- Reason data is for **reporting only** — it is stored on the attendee record and visible to staff via the Directus admin panel. It is not shown anywhere in the app after submission.
- Both `reason` and `reason_text` are stored on **every attendee** cancelled in the call (for order-level cancels this means all pending attendees in the order get the same reason).
- Admins receive a push notification automatically when any user cancels — no FE action needed.
