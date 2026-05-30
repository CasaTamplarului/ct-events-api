# Events Listing Page — Frontend Integration Guide

**Base URL:** `https://localhost:3000` / `https://api.casatamplarului.ro`

---

## Overview

Three endpoints are relevant to the events listing page:

| Purpose | Endpoint |
|---------|----------|
| Browse/listing page (filterable, paginated) | `GET /api/v1/:lang/events/listing` |
| Homepage upcoming strip (max 10) | `GET /api/v1/:lang/events/upcoming` |
| Homepage past strip (max 10) | `GET /api/v1/:lang/events/past` |

`:lang` is the language code, e.g. `ro-RO` or `en-US`.

---

## Listing Endpoint

```
GET /api/v1/:lang/events/listing
```

### Query Parameters

| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `filter` | `all` \| `upcoming` \| `past` | `all` | Time window. `upcoming` = start date in the future; `past` = start date in the past. |
| `search` | string | — | Searches event name and tag line. Case-insensitive. |
| `year` | integer | — | Filters by the year of the event's start date, e.g. `2026`. |
| `pricing` | `free` \| `paid` \| `both` | `both` | `free` includes events with no tickets or a zero-price ticket. `paid` includes events with at least one priced ticket. |
| `page` | integer | `1` | Page number (1-based). |
| `per_page` | integer | `12` | Results per page. Clamped to 1–100. |

Unknown values for `filter` and `pricing` fall back to their defaults silently — the page always renders something.

### Response

```json
{
  "events": [ /* array of Event objects, see below */ ],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 47,
    "per_page": 12
  }
}
```

`events` is an empty array `[]` when there are no results. `total_pages` is always at least `1`.

### Sort order

- `filter=upcoming` → sorted by `start_date` ascending (nearest event first)
- `filter=past` → sorted by `start_date` descending (most recent first)
- `filter=all` → sorted by `start_date` descending

---

## Homepage Endpoints

Both return a plain array (no `meta` wrapper) using the same Event object shape.

```
GET /api/v1/:lang/events/upcoming   → up to 10 events, start_date ASC
GET /api/v1/:lang/events/past       → up to 10 events, start_date DESC
```

The past endpoint omits pricing information (`starts_from` and `tickets` are `null`).

---

## Event Object

```json
{
  "name": "Conferința 2026",
  "tag_line": "O conferință pentru toți",
  "description": "Descriere completă a evenimentului.",
  "slug": "conferinta-2026",
  "start_date": "2026-06-18T10:00:00.000Z",
  "end_date": "2026-06-20T18:00:00.000Z",
  "location_name": "Casa Tâmplarului",
  "address": "Str. Exemplu 1, Cluj-Napoca",
  "embed_url": "https://...",
  "fully_booked": false,
  "starts_from": "150.0",
  "hero_image": "https://cdn.directus.io/...",
  "hero_portrait": "https://cdn.directus.io/...",
  "gallery_preview": "https://cdn.directus.io/...",
  "tickets": [ /* array of Ticket objects, see below */ ]
}
```

| Field | Type | Notes |
|-------|------|-------|
| `name` | string | Translated to the requested language |
| `tag_line` | string | Translated |
| `description` | string \| null | Translated |
| `slug` | string | Use this for the event detail URL |
| `start_date` | ISO 8601 datetime | UTC |
| `end_date` | ISO 8601 datetime | UTC |
| `location_name` | string \| null | |
| `address` | string \| null | |
| `embed_url` | string \| null | External embed, e.g. livestream |
| `fully_booked` | boolean | True when capacity is reached |
| `starts_from` | string (decimal) \| null | Minimum ticket price. `null` on the past endpoint and when there are no tickets. `"0.0"` for free events. |
| `hero_image` | URL \| null | Landscape image for card/banner |
| `hero_portrait` | URL \| null | Portrait image |
| `gallery_preview` | URL \| null | First gallery image |
| `tickets` | array \| null | Null on the past endpoint |

### Ticket Object

```json
{
  "id": 42,
  "name": "Adult",
  "description": "Includes all meals",
  "price": "150.0",
  "food_included": true
}
```

| Field | Type | Notes |
|-------|------|-------|
| `id` | integer | |
| `name` | string | Translated |
| `description` | string \| null | Translated |
| `price` | string (decimal) \| null | Null on the past endpoint |
| `food_included` | boolean | |

---

## Example Requests

**All upcoming events, page 1, 12 per page (default)**
```
GET /api/v1/ro-RO/events/listing?filter=upcoming
```

**Search for "tabara", year 2026, free only**
```
GET /api/v1/ro-RO/events/listing?search=tabara&year=2026&pricing=free
```

**Past events, page 2, 6 per page**
```
GET /api/v1/ro-RO/events/listing?filter=past&page=2&per_page=6
```

**Homepage upcoming strip**
```
GET /api/v1/ro-RO/events/upcoming
```

---

## Suggested UI Behaviour

- On initial load, call `filter=all` (or `filter=upcoming` if the default view shows only future events).
- Debounce the `search` input (~300ms) before firing a new request.
- When `filter` or any other param changes, reset `page` to `1`.
- Show a "no results" state when `meta.total_count === 0`.
- Disable the "next page" button when `meta.current_page === meta.total_pages`.
- Use `slug` to build the event detail link, e.g. `/events/conferinta-2026`.
- `starts_from === null` → no pricing badge. `starts_from === "0.0"` → "Free" badge. Otherwise show the formatted price.
