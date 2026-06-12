# Ticket Valid Date Range — Design

## Goal

Allow staff to configure a date range (`valid_from`, `valid_to`) on each ticket in Directus so that day-tickets or multi-day sub-tickets can only be used to check in on their valid days. Check-in outside the range is a hard block.

## Data Layer

Add two nullable `date` columns to the `tickets` table:

- `valid_from` — first day the ticket is valid (inclusive), nullable
- `valid_to`   — last day the ticket is valid (inclusive), nullable

No model validations are needed. Null on either column means that bound is unrestricted. Both null = valid any day (backwards-compatible default for existing tickets).

## Directus Registration

A Rails migration inserts rows into `directus_fields` for the `tickets` collection using `interface: 'datetime'` (Directus renders date-only columns as a date picker). Both fields are editable (`readonly: false`, `hidden: false`), `width: 'half'` so they appear side by side.

Pattern: `DELETE` existing rows first (prevent duplicates), then `INSERT`. Restart Directus after running.

## Check-in Validation

In `OrdersController#update_attendee_checkins`, before setting `checked_in: true`:

1. Load attendees with `.includes(:ticket)` so the ticket is available.
2. If the ticket has `valid_from` or `valid_to` set, compare `Date.current` against the range (both bounds inclusive).
3. If today is outside the range, return `{ error: I18n.t('scan.errors.invalid_checkin_date') }` from the method and render 422 in the action.
4. Un-checking (`checked_in: false`) is never blocked by date.
5. If no date is set on the ticket, allow check-in on any day.

The locale key `scan.errors.invalid_checkin_date` is added to both `en.yml` and `ro.yml`. The scan controller already includes `LocaleSetter` (via `before_action :set_locale`… wait — it does not currently; locale is English by default for scan). The error string is rendered in whatever locale `I18n.locale` is set to at request time.

## Scan Response

`ScanSerialisable#serialise_attendee` includes `valid_from` and `valid_to` so the scan UI can display the valid window to staff when they look up an order. The ticket is already eager-loaded in both the `show` and `update` paths via `serialise_order`.

## Out of Scope

- No validation that `valid_from <= valid_to` (staff responsibility).
- No changes to the public event or bookings APIs.
- No changes to meal stamp validation (meal slots already scope to specific dates).
