# Email Broadcast Attachments — Frontend Integration Guide

**Date:** 2026-07-09 · **Auth:** `can_send_emails` (admin only)

---

## What changed

`POST /api/v1/admin/emails` must now be sent as **`multipart/form-data`** when including attachments. JSON still works for sends with no attachments.

Two attachment sources are supported:
- **Direct upload** — files from the device, sent as multipart fields (`attachments[]`)
- **Directus assets** — files already in the CMS, referenced by UUID (`directus_file_ids[]`)

The email body automatically gets a Romanian download-links block appended when attachments are present.

---

## POST /api/v1/admin/emails — updated

### New parameters

| Parameter | Type | Description |
|---|---|---|
| `attachments[]` | `file[]` | One or more files. Each ≤ 10 MB; total ≤ 25 MB. |
| `directus_file_ids[]` | `string[]` | Directus asset UUIDs. Any invalid UUID returns 422 before the broadcast record is created. |

All existing parameters (`subject`, `body`, `channel`, `to`, etc.) are unchanged.

### Content-Type

Send as `multipart/form-data`. **Do not set `Content-Type: application/json`** — let the browser or HTTP client set the multipart boundary automatically.

### Example (browser / React)

```js
const form = new FormData();
form.append('subject', 'Important update');
form.append('body', '<p>Hello {{first_name}}</p>');
form.append('channel', 'marketing_emails');

for (const file of selectedFiles) {
  form.append('attachments[]', file);
}

for (const uuid of selectedDirectusIds) {
  form.append('directus_file_ids[]', uuid);
}

const res = await fetch('/api/v1/admin/emails', {
  method: 'POST',
  headers: { Authorization: `Bearer ${token}` },
  // Do NOT set Content-Type here
  body: form,
});
```

### Size limits

- Per file: **10 MB**
- Total across all direct uploads: **25 MB**

Validate client-side before submitting:

```js
const MAX_PER_FILE = 10 * 1024 * 1024;
const MAX_TOTAL    = 25 * 1024 * 1024;

function validateFiles(files) {
  let total = 0;
  for (const f of files) {
    if (f.size > MAX_PER_FILE) return `${f.name} exceeds the 10 MB per-file limit`;
    total += f.size;
  }
  if (total > MAX_TOTAL) return 'Total attachments exceed 25 MB';
  return null;
}
```

### Success responses

Unchanged from before:

```json
// Bulk send
{ "broadcast_id": 42, "queued_for": 1248 }

// Test send (to: present)
{ "sent_to": 1 }
```

---

## GET /api/v1/admin/emails — updated

Each broadcast now includes an `attachments` field:

```json
{
  "id": 42,
  "subject": "Important update",
  "channel": "marketing_emails",
  "recipient_count": 1248,
  "sent_at": "2026-07-09T10:00:00.000Z",
  "attachments": [
    { "name": "programme.pdf", "url": "https://s3.eu-south-1.amazonaws.com/..." },
    { "name": "guide.pdf",     "url": "https://cms.casatamplarului.ro/assets/uuid-abc" }
  ]
}
```

> **Note:** Signed S3 URLs (direct uploads) expire after **7 days**. Directus asset URLs are permanent. Show a "link may have expired" note for broadcasts older than 7 days.

---

## Error reference

| Status | When | Body |
|---|---|---|
| `422` | File exceeds 10 MB | `{"error": "filename.pdf exceeds the 10 MB per-file limit"}` |
| `422` | Total exceeds 25 MB | `{"error": "Total attachments exceed the 25 MB limit"}` |
| `422` | Directus UUID not found | `{"error": "Directus file <uuid> not found"}` |
| `422` | Directus file exceeds 10 MB | `{"error": "Directus file <uuid> exceeds the 10 MB per-file limit"}` |
| `400` | Missing `subject` or `body` | `{"error": "subject is required"}` |

---

## Mobile notes

### iOS (Swift)
Use `URLSession` with `Alamofire`'s `multipartFormData` or build the body manually. Do not set `Content-Type` — `URLSession` sets the boundary automatically.

### Android (Kotlin)
Use OkHttp `MultipartBody` with `addFormDataPart` for each file. Let OkHttp set the boundary.

### React Native
Use `FormData` exactly as the browser example above. With Axios, do not pass `Content-Type` in headers — Axios detects `FormData` and sets the boundary automatically.

---

## Suggested UI behaviour

**Attachment picker**
- Two input paths: "Upload file" (native picker) + "Choose from CMS" (Directus browser)
- Show each attachment as a removable chip with filename and size
- Validate size client-side and show inline errors before submit

**Test send**
- Attachments are included — staff receives the actual file in the preview email
- No broadcast record or S3 storage is created during a test send

**Broadcast history**
- Show a paperclip indicator on rows where `attachments.length > 0`
- Render each entry as a download link (`attachments[n].name` / `attachments[n].url`)
- For broadcasts older than 7 days, note that direct-upload links may have expired
