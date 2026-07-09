# Cancellation Reason & Admin Push Alert — Design Spec

## Goal

When a user cancels a booking (single attendee or full order), capture an optional reason from a predefined list plus optional free text, store it on the attendee record for reporting, and immediately notify all admin users via push notification.

## Architecture

Two columns added to `attendees` to store the reason. Both cancel endpoints in `BookingsController` accept the new optional params and write them to every attendee being cancelled. After writing, a background job (`SendCancellationAlertJob`) fires a direct FCM push to all admin users — no `PushNotification` DB record is created.

**Tech stack:** Rails migration, model constant, existing `FcmService.send_to_user`, new `ApplicationJob` subclass.

---

## Data Model

### `attendees` — two new nullable columns

| Column | Type | Notes |
|--------|------|-------|
| `cancellation_reason` | `string`, nullable | One of the preset keys below; `null` if user skipped |
| `cancellation_reason_text` | `text`, nullable | Free-form note; accepted with or without a preset |

Both columns are only meaningful when `payment_status = attendee_cancelled`. Old cancelled attendees retain `null` values — no backfill.

### Preset reason keys

Defined as `Attendee::CANCELLATION_REASONS` (array of strings):

| Key | Romanian label |
|-----|----------------|
| `cant_attend` | Nu pot participa |
| `health` | Motive de sănătate |
| `financial` | Motive financiare |
| `plans_changed` | Schimbare de planuri |
| `other` | Altele |

---

## API Changes

### `DELETE /api/v1/auth/me/bookings/:order_reference`
### `DELETE /api/v1/auth/me/bookings/:order_reference/attendees/:id`

Both endpoints gain two new **optional** body params:

| Param | Type | Validation |
|-------|------|------------|
| `reason` | string, optional | Must be one of `CANCELLATION_REASONS` if present; invalid value → `422 { error: "Invalid cancellation reason" }` |
| `reason_text` | string, optional | No validation; accepted with or without `reason` |

`reason` absent → `cancellation_reason` column stays `null` (no error).
`reason_text` absent → `cancellation_reason_text` stays `null`.

For `cancel_order` (cancels multiple attendees): the same `reason` and `reason_text` are written to all attendees cancelled in that call.

Both columns are set in the same `update_all` / `update!` call that flips `payment_status`, so no extra DB round-trip is needed.

---

## Push Notification

### New job: `SendCancellationAlertJob`

Fired with `perform_later` after the cancel write in both `cancel_order` and `cancel_attendee`. Arguments: `attendee_id` (single attendee that was just cancelled — for `cancel_order` use the first cancelled attendee).

**Recipients:** `User.where(role: 'admin')` — all admin accounts, regardless of their push preference settings.

**Delivery:** Calls `FcmService.send_to_user(preference: nil, ...)` for each admin — `preference: nil` bypasses the preference check so admins always receive operational alerts.

**Content:**

| Field | Value |
|-------|-------|
| Title | `"Anulare bilet — #{event_name}"` |
| Body | `"#{first_name} #{last_name} și-a anulat locul. Motiv: #{reason_label}"` |
| `reason_label` | Romanian label for the preset (e.g. `"Motive de sănătate"`), or `"Nespecificat"` if `cancellation_reason` is null |
| Link | `nil` (FCM service defaults to `/`) |
| Image | `nil` |
| Actions | `[]` |

No `PushNotification` record is created — this is an operational alert, not staff-authored broadcast content.

### Event name resolution

The job looks up the attendee's event and uses the `ro-RO` translation name (same pattern as `SendEmailsJob`).

---

## Files Created / Modified

| File | Action |
|------|--------|
| `db/migrate/…_add_cancellation_reason_to_attendees.rb` | Add `cancellation_reason` (string) and `cancellation_reason_text` (text) to `attendees` |
| `app/models/attendee.rb` | Add `CANCELLATION_REASONS` constant |
| `app/controllers/api/v1/auth/me/bookings_controller.rb` | Accept `reason` + `reason_text` in `cancel_order` and `cancel_attendee`; validate preset; enqueue `SendCancellationAlertJob` |
| `app/jobs/send_cancellation_alert_job.rb` | New job — sends FCM to all admins |
| `spec/models/attendee_spec.rb` | `CANCELLATION_REASONS` includes expected keys |
| `spec/requests/api/v1/auth/me/bookings_spec.rb` | reason stored on attendee; invalid reason → 422; no reason → nil; push job enqueued |
| `spec/jobs/send_cancellation_alert_job_spec.rb` | FCM called for each admin; reason label in body; "Nespecificat" when nil |

---

## Out of Scope

- Admin-facing UI to view cancellation reasons (Directus can query `attendees` directly)
- Cancellation reasons for staff-initiated cancellations (scan app / admin panel)
- Reason collection for already-cancelled attendees (no backfill)
- Push preference opt-out for admin operational alerts
