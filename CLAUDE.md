# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
# Development
bin/rails s                    # Start server (Puma, port 3000)
docker-compose up -d           # Start PostgreSQL + Directus

# Database
bin/rails db:prepare           # Create + migrate + seed
bin/rails db:migrate

# Testing
bin/rails test                 # Run all tests
bin/rspec spec/models/event_spec.rb  # Run a single spec file

# Linting
bin/rubocop                    # Lint Ruby code
bin/rubocop -a                 # Auto-fix offenses

# Combined (default rake task)
rake                           # Runs test + test:system + rubocop
```

## Architecture

Rails 7.1 API-only app (no HTML views) serving event data for a multi-language venue website. The same PostgreSQL database is shared with a **Directus headless CMS** instance — Directus manages content, this API serves it to the frontend.

### Request Flow

```
GET /api/v1/:languages_code/events/upcoming
  → Api::V1::Events::UpcomingController
  → Event.upcoming scope (with translations join for language_code)
  → ThumbnailEventSerializer (Alba)
  → JSON response
```

### API Endpoints

All routes are namespaced under `/api/v1/:languages_code` where `languages_code` matches `[a-zA-Z]{2}-[a-zA-Z]{2}` (e.g., `en-US`, `ro-RO`):

**Public events:**

| Route | Controller |
|-------|-----------|
| `GET /events/upcoming` | `Events::UpcomingController` — next 6 events |
| `GET /events/past` | `Events::PastController` |
| `GET /events/hero` | `Events::HeroController` — featured event |
| `GET /event/:slug` | `EventController` — single event detail |
| `GET /_healthcheck` | Health check |

**Authenticated bookings** (`/api/v1/auth/me/bookings/*` — requires JWT):

| Route | Action |
|-------|--------|
| `GET /upcoming` | User's upcoming bookings |
| `GET /past` | User's past bookings |
| `POST /check` | Check if user has bookings for given slugs |
| `DELETE /:order_reference` | Cancel all pending attendees on an order |
| `DELETE /:order_reference/attendees/:id` | Cancel a single attendee |
| `GET /:order_reference/wallet/google` | Google Wallet pass for user's attendee (order-level) |
| `GET /:order_reference/attendees/:id/wallet/google` | Google Wallet pass for a specific attendee |

**Scan** (`/api/v1/scan/*` — requires `can_check_in_attendees` permission):

| Route | Action |
|-------|--------|
| `GET /events` | List upcoming events |
| `GET /orders/:order_reference` | Look up order + attendees |
| `PATCH /orders/:order_reference` | Check in / update payment status |
| `GET /search` | Search by order_ref, name, email, phone |

### Multi-language Pattern

Events and tickets use separate translation tables (`events_translations`, `tickets_translations`). Controllers receive `languages_code` from the URL and filter translations accordingly. Models join translations scoped to the requested language.

### Serializers

Uses **Alba** gem for JSON serialization. Three event serializer tiers:
- `ThumbnailEventSerializer` — minimal fields for list views
- `HeroEventSerializer` — featured event with extra details
- `EventSerializer` — full detail including nested tickets

`ApplicationSerializer` is the Alba base class all serializers inherit from.

### Key Models

**Event:**
```ruby
# Enums
status: { draft: "draft", live: "live", cancelled: "cancelled", deleted: "deleted" }

# Boolean flags
hero: boolean  # marks the featured/hero event

# Key scopes
Event.upcoming  # future live events
Event.past      # past live events
Event.hero      # the featured event
```

**Order:**
```ruby
belongs_to :user, optional: true   # user who created the order
has_many :attendees

order_reference  # "CT-YYYY-XXXXXX" — 6 random [A-Z0-9] chars, generated after create
payment_status   # computed from attendees (not stored): paid/payment_pending/partial/refunded/attendee_cancelled
```

**Attendee:**
```ruby
belongs_to :event
belongs_to :user, optional: true   # set when attendee email matches a user account
belongs_to :order, optional: true

# Enums
payment_status: { payment_pending: 0, paid: 1, refunded: 2, attendee_cancelled: 3 }

# QR code
attendee.qr_code  # → "CT-YYYY-XXXXXX-<attendee.id>" — used for wallet passes and in-app tickets
```

### Google Wallet

`GoogleWalletService` generates per-attendee passes. Takes `attendee:` and `language:`.

- One `EventTicketClass` per event (shared by all attendees)
- One `EventTicketObject` per attendee — wallet object ID and QR barcode value are both the attendee's `qr_code`
- Endpoint: `GET /auth/me/bookings/:order_reference/attendees/:id/wallet/google`

**QR code format:** `CT-YYYY-XXXXXX-<attendee_id>` (e.g. `CT-2026-ABC123-42`). The scan backend resolves by order ref — frontend parses the QR by splitting on the last `-` to get the order ref, then uses the attendee ID to highlight the right row.

### Environment Setup

Requires `.env` file (copy from `.env.example` if present) with:
```
DATABASE_PORT=5432
DATABASE_HOST=localhost
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
```

Secrets (Sentry DSN, API docs auth, production DB password) are stored in Rails encrypted credentials (`config/credentials.yml.enc` + `config/master.key`).
