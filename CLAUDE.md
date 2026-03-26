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

| Route | Controller |
|-------|-----------|
| `GET /events/upcoming` | `Events::UpcomingController` — next 6 events |
| `GET /events/past` | `Events::PastController` |
| `GET /events/hero` | `Events::HeroController` — featured event |
| `GET /event/:slug` | `EventController` — single event detail |
| `GET /_healthcheck` | Health check |

### Multi-language Pattern

Events and tickets use separate translation tables (`events_translations`, `tickets_translations`). Controllers receive `languages_code` from the URL and filter translations accordingly. Models join translations scoped to the requested language.

### Serializers

Uses **Alba** gem for JSON serialization. Three event serializer tiers:
- `ThumbnailEventSerializer` — minimal fields for list views
- `HeroEventSerializer` — featured event with extra details
- `EventSerializer` — full detail including nested tickets

`ApplicationSerializer` is the Alba base class all serializers inherit from.

### Key Model: Event

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

### Environment Setup

Requires `.env` file (copy from `.env.example` if present) with:
```
DATABASE_PORT=5432
DATABASE_HOST=localhost
DATABASE_USERNAME=postgres
DATABASE_PASSWORD=postgres
```

Secrets (Sentry DSN, API docs auth, production DB password) are stored in Rails encrypted credentials (`config/credentials.yml.enc` + `config/master.key`).
