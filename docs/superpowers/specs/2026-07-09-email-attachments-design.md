# Email Broadcast Attachments — Design Spec

## Goal

Allow staff to attach one or more files to a broadcast email. Files can be uploaded directly or sourced from existing Directus assets. The Directus asset URL is also stored so staff can include a fallback download link in the email body for clients that block attachments.

## Architecture

Active Storage (already configured for S3 in production) stores all attachment blobs on `EmailBroadcast`. Directus files are fetched at request time and re-stored in S3 — the job reads from S3 only, with one download per file regardless of recipient count. No new model files are needed.

**Tech stack:** Rails Active Storage, S3 (production) / Disk (dev/test), SendGrid attachment API.

---

## Data Model

### `email_broadcasts` — two new columns

| Column | Type | Notes |
|--------|------|-------|
| `attachment_urls` | jsonb, default `[]` | `[{ "name": "file.pdf", "url": "https://…" }]` — Directus URL for Directus files, signed S3 URL for direct uploads. Used for fallback links in the email body. |

### Active Storage

```ruby
# app/models/email_broadcast.rb
has_many_attached :attachments
```

Tables `active_storage_blobs` and `active_storage_attachments` are created by `rails active_storage:install` (not yet run in this project).

---

## API Changes

### `POST /api/v1/admin/emails`

Changes from JSON to **multipart form data** to support file uploads.

**New optional params:**

| Param | Type | Notes |
|-------|------|-------|
| `attachments[]` | files | One or more files uploaded directly |
| `directus_file_ids[]` | strings | Directus file UUIDs to fetch and attach |

**Direct uploads:** attached to the broadcast via `has_many_attached`. A signed S3 URL is generated and stored in `attachment_urls`.

**Directus files:** Rails fetches each file from the Directus admin API:
```
GET /assets/:uuid?download=1
Authorization: Bearer <directus_admin_token>
```
The downloaded blob is attached via Active Storage. The Directus canonical asset URL is stored in `attachment_urls`. If a Directus fetch fails (invalid UUID, 404), the API returns `422` with an error — the send is aborted before any broadcast record is created.

**Test send** (when `to:` is present): same params accepted. Files are attached inline to the single SendGrid mail — no broadcast record, no S3 storage. Directus files are fetched on the fly.

**Size limit:** 10 MB per file, 25 MB total across all attachments per broadcast. Validated in the controller before any storage or send. Returns `422` on violation.

### `GET /api/v1/admin/emails` (broadcast history)

`broadcast_json` gains an `attachments` field:

```json
{
  "id": 5,
  "subject": "Important update",
  "attachments": [
    { "name": "programme.pdf", "url": "https://directus.example.com/assets/abc123" },
    { "name": "map.png", "url": "https://s3.eu-south-1.amazonaws.com/…" }
  ]
}
```

---

## SendGrid / Job Changes

### `SendgridService.send_broadcast`

Two new optional keyword params:

```ruby
def self.send_broadcast(
  to:,
  subject:,
  body_html:,
  unsubscribe_url: nil,
  is_romanian: true,
  attachments: [],       # [{ content: "<base64>", type: "application/pdf", filename: "file.pdf" }]
  attachment_urls: []    # [{ "name" => "file.pdf", "url" => "https://…" }]
)
```

**Attachment behaviour:**
- Each entry in `attachments` is added to the `SendGrid::Mail` object via `mail.add_attachment`.
- If `attachment_urls` is non-empty, a download-links HTML block is **appended to `body_html`** before sending — no SendGrid template change needed since `body_html` is already a dynamic template variable.

**Download links block (appended to both Romanian and English bodies):**
```html
<div style="margin-top:24px;padding-top:16px;border-top:1px solid #eee">
  <p style="margin:0 0 8px;font-size:14px;color:#555">
    Dacă nu poți vedea atașamentele, le poți descărca aici:
  </p>
  <ul style="margin:0;padding-left:20px">
    <li><a href="https://…">programme.pdf</a></li>
  </ul>
</div>
```

### `SendEmailsJob`

Attachments are loaded **once at job start**, not per recipient:

```ruby
broadcast   = EmailBroadcast.find(broadcast_id)
encoded     = broadcast.attachments.blobs.map do |b|
  { content: Base64.strict_encode64(b.download), type: b.content_type, filename: b.filename.to_s }
end
attach_urls = broadcast.attachment_urls
```

`encoded` and `attach_urls` are passed to `SendgridService.send_broadcast` for every recipient. One S3 download per file, regardless of recipient count.

---

## Error Handling

| Scenario | Behaviour |
|----------|-----------|
| Directus UUID not found | `422` returned before broadcast is created |
| File exceeds 10 MB | `422` returned, nothing stored |
| Total attachments exceed 25 MB | `422` returned, nothing stored |
| S3 blob download fails in job | Log error, send email without attachments (do not abort job) |
| SendGrid rejects attachment | Existing error logging, job continues to next recipient |

---

## Files Created / Modified

| File | Action |
|------|--------|
| `db/migrate/…_active_storage_tables.rb` | `rails active_storage:install` |
| `db/migrate/…_add_attachment_urls_to_email_broadcasts.rb` | Add `attachment_urls` jsonb column |
| `app/models/email_broadcast.rb` | Add `has_many_attached :attachments` |
| `app/controllers/api/v1/admin/emails_controller.rb` | Accept `attachments[]` + `directus_file_ids[]`, size validation, attach/fetch logic, updated `broadcast_json` |
| `app/services/sendgrid_service.rb` | Add `attachments:` + `attachment_urls:` params to `send_broadcast`, append download links block, add SendGrid attachment objects |
| `app/jobs/send_emails_job.rb` | Load + encode blobs once at job start, pass to service |
| `spec/services/sendgrid_service_spec.rb` | Attachment added to mail; download links appended to body |
| `spec/requests/api/v1/admin/emails_spec.rb` | Direct upload attach; directus_file_ids fetch and attach; size limit rejection |
| `spec/jobs/send_emails_job_spec.rb` | Blobs encoded once, passed to service |

---

## Out of Scope

- Attachment storage on `WhatsappBroadcast` (WhatsApp templates don't support file attachments)
- Per-recipient personalised attachments
- Attachment management UI (delete/replace attachments on an existing broadcast)
