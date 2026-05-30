# Events Listing Endpoint — Design Spec

## Goal

Add a paginated, filterable events listing endpoint for a browse/listing page, and bump the existing homepage endpoints from 6 to 10 events.

---

## Existing Homepage Endpoints (small change)

Both controllers change only their `limit` call:

| Endpoint | Change |
|---|---|
| `GET /api/v1/:lang/events/upcoming` | `limit(6)` → `limit(10)`, sort `start_date ASC` |
| `GET /api/v1/:lang/events/past` | `limit(6)` → `limit(10)`, sort `start_date DESC` |

No other changes to these controllers.

---

## New Endpoint

```
GET /api/v1/:languages_code/events/listing
```

### Query Parameters

| Param | Type | Values | Default | Notes |
|---|---|---|---|---|
| `filter` | string | `all` / `upcoming` / `past` | `all` | Time window |
| `search` | string | any | — | ILIKE on name + tag_line |
| `year` | integer | e.g. `2026` | — | Matches `YEAR(start_date)` |
| `pricing` | string | `free` / `paid` / `both` | `both` | See definition below |
| `page` | integer | ≥ 1 | `1` | |
| `per_page` | integer | 1–100 | `12` | Clamped at 100 |

### Free / Paid Definition

Determined via `MIN(tickets.price)` per event (i.e. `Event#starts_from`):

- **free**: `starts_from IS NULL OR starts_from = 0`
- **paid**: `starts_from > 0`
- **both** (default): no pricing filter applied

### Sort Order

| `filter` | Sort |
|---|---|
| `upcoming` | `start_date ASC` |
| `past` | `start_date DESC` |
| `all` | `start_date DESC` |

### Keyword Search

`ILIKE '%query%'` on `events_translations.name` and `events_translations.tag_line` for the requested `languages_code`. Results match if either field matches.

### Response Shape

```json
{
  "events": [ /* ThumbnailEventSerializer objects */ ],
  "meta": {
    "current_page": 1,
    "total_pages": 5,
    "total_count": 47,
    "per_page": 12
  }
}
```

`events` uses the existing `ThumbnailEventSerializer` — same shape as homepage cards.

---

## Architecture

### Route

Added inside the existing `namespace :events` block in `config/routes.rb`:

```ruby
resources :listing, only: :index
```

### Controller

`app/controllers/api/v1/events/listing_controller.rb`

Inherits `ActionController::API`. Responsible for:
1. Parsing and validating params
2. Building the filtered/sorted/paginated scope via `Event` scopes
3. Rendering the response with `ThumbnailEventSerializer` + meta

### Scoping (on `Event` model)

New named scopes added to `Event`:

- `Event.by_filter(filter)` — applies time window (`upcoming` / `past` / `all`); no-op for `all`
- `Event.by_keyword(search, lang)` — `INNER JOIN events_translations` for the given language, `ILIKE '%search%'` on `name OR tag_line`; no-op when blank
- `Event.by_year(year)` — `WHERE EXTRACT(YEAR FROM start_date) = year`; no-op when blank
- `Event.by_pricing(pricing)` — `LEFT JOIN tickets` + `GROUP BY events.id` + `HAVING MIN(tickets.price) IS NULL OR MIN(tickets.price) = 0` for `free`; `HAVING MIN(tickets.price) > 0` for `paid`; no-op for `both`. Uses LEFT JOIN so events with no tickets correctly appear as free.
- `Event.sorted_for(filter)` — `start_date ASC` for upcoming, `start_date DESC` for past + all

All scopes are chainable. When `by_keyword` and `by_pricing` are both applied, the controller calls `.distinct` to prevent duplicate rows from the two joins.

### Pagination

No extra gem — implemented inline in the controller using `offset`/`limit` and `count`. Returns `total_count`, `total_pages`, `current_page`, `per_page` in a `meta` key.

---

## Error Handling

Invalid params are silently coerced to defaults (e.g. `per_page=0` → 1, `per_page=999` → 100, unknown `filter` → `all`, unknown `pricing` → `both`). No 4xx for bad filter values — the listing page should always render something.

---

## Testing

`spec/requests/api/v1/events/listing_spec.rb` — request specs covering:

- Returns only live events
- `filter=upcoming` returns only future events sorted ASC
- `filter=past` returns only past events sorted DESC
- `filter=all` returns both, sorted DESC
- `search=` filters by name and tag_line (case-insensitive)
- `year=` filters by start_date year
- `pricing=free` returns events with no tickets or zero-price tickets
- `pricing=paid` returns events with tickets priced > 0
- `per_page` and `page` pagination (meta counts correct, offset correct)
- `per_page` clamped to 100
- Empty result returns `{ events: [], meta: { total_count: 0, ... } }`

`spec/models/event_spec.rb` — unit tests for each new scope in isolation.
