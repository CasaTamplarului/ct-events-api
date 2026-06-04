# Template Doc File Uploads — Design Spec

**Date:** 2026-06-04

## Overview

Attendees must be able to upload a completed/signed version of each required template document (e.g. consent forms) as part of the checkout flow. Uploads are stored in Directus/MinIO and referenced in the order submission.

## Flow

Two-step process:

1. **Upload step** — frontend sends the file to Rails; Rails proxies it to Directus and returns a `directus_files_id` UUID.
2. **Checkout step** — frontend includes `template_doc_uploads` per attendee in the order payload, referencing the UUID(s) from step 1. Rails creates `AttendeeTemplateDocUpload` records in the same transaction as the attendee.

## Database

### New table: `attendee_template_doc_uploads`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigserial PK | |
| `attendee_id` | FK → attendees | cascade delete |
| `event_template_doc_id` | FK → event_template_docs | cascade delete |
| `directus_files_id` | UUID FK → directus_files | the uploaded file |
| `created_at`, `updated_at` | timestamps | |

Unique index on `(attendee_id, event_template_doc_id)` — one upload per doc per attendee.

No changes to `attendees`, `orders`, or `event_template_docs`.

## Upload Endpoint

**Route:** `POST /api/v1/uploads`

- Outside the language scope (`/:languages_code`)
- No authentication required — attendee may not be logged in during checkout

**Request:** multipart form data with a single `file` field.

**Allowed MIME types:** `application/pdf`, `image/jpeg`, `image/png`

**Response (201):**
```json
{ "directus_files_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" }
```

**Error responses:**
- 400 — file missing or invalid MIME type
- 502 — Directus upload failed

### Implementation

- `DirectusUploadService` — streams the file to Directus `POST /files` via `Net::HTTP` multipart, authenticated with `DIRECTUS_ADMIN_TOKEN` from Rails encrypted credentials. Returns the UUID string on success, raises on failure.
- `Api::V1::UploadsController` — calls `DirectusUploadService`, renders the UUID or an error.

Orphaned uploads (uploaded but never referenced in an order) are left in Directus — volume is negligible.

## Checkout Integration

### Updated request shape

```json
{
  "items": [{
    "event_slug": "conferinta-2026",
    "ticket_name": "General",
    "attendee": {
      "first_name": "Ion",
      "age": 16,
      "template_doc_uploads": [
        { "event_template_doc_id": 3, "directus_files_id": "uuid-here" }
      ]
    }
  }]
}
```

### Validation (in `OrdersController`, before persisting)

1. Each `event_template_doc_id` in `template_doc_uploads` must belong to the event being booked — 400 if not.
2. All `required: true` template docs that apply to the attendee's age must have an upload — 400 listing the missing doc labels in the request language.

**Age-range applicability:** a doc applies to an attendee if:
- Both `age_from` and `age_to` are nil (applies to all ages), OR
- The attendee's age falls within `[age_from, age_to]` (inclusive).

If the attendee has no `age` set, required docs with an age range are not enforced (can't enforce what we don't know).

### Persisting

Inside the existing `ActiveRecord::Base.transaction` in `persist_order`:

```
order.attendees.create!(...)
# then, for each template_doc_upload in the item:
AttendeeTemplateDocUpload.create!(attendee:, event_template_doc_id:, directus_files_id:)
```

### New model: `AttendeeTemplateDocUpload`

```ruby
class AttendeeTemplateDocUpload < ApplicationRecord
  belongs_to :attendee
  belongs_to :event_template_doc
  validates :event_template_doc_id, uniqueness: { scope: :attendee_id }
  validates :directus_files_id, presence: true
end
```

## New Files Summary

| File | Purpose |
|------|---------|
| `db/migrate/..._create_attendee_template_doc_uploads.rb` | Migration |
| `app/models/attendee_template_doc_upload.rb` | Model |
| `app/services/directus_upload_service.rb` | Proxies multipart upload to Directus |
| `app/controllers/api/v1/uploads_controller.rb` | Upload endpoint |

### Modified Files

| File | Change |
|------|--------|
| `config/routes.rb` | Add `post 'uploads'` route |
| `app/controllers/api/v1/orders_controller.rb` | Validate + persist template doc uploads |

## Credentials

`DIRECTUS_ADMIN_TOKEN` added to Rails encrypted credentials (`config/credentials.yml.enc`). Used only by `DirectusUploadService`.

## Error Handling

- Invalid MIME type → 400 before hitting Directus
- Directus unreachable or returns error → 502 from uploads endpoint
- Unknown `event_template_doc_id` at checkout → 400
- Missing required upload at checkout → 400 with I18n message listing missing doc labels
- DB constraint violation on duplicate upload → caught by model validation, surfaced as 400
