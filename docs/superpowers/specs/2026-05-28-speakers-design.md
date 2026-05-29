# Speakers Feature Design

## Overview

Add per-event speakers to the API. Each event can have zero or more speakers, ordered by a sort field. Speakers have a photo, name, and a call-to-action link. Description and action label are translatable per language; name, image, and action URL are language-agnostic.

## Data Model

### `event_speakers` table

| Column       | Type    | Notes                              |
|--------------|---------|------------------------------------|
| id           | bigint  | PK                                 |
| event_id     | bigint  | FK → events, NOT NULL, cascade delete |
| name         | string  | NOT NULL                           |
| image        | uuid    | FK → directus_files, nullable      |
| action_url   | string  | nullable                           |
| sort         | integer | default 0, NOT NULL                |
| created_at   | datetime| NOT NULL                           |
| updated_at   | datetime| NOT NULL                           |

Index: `event_id, sort`

### `event_speakers_translations` table

| Column           | Type   | Notes                                      |
|------------------|--------|--------------------------------------------|
| id               | bigint | PK                                         |
| event_speaker_id | bigint | FK → event_speakers, NOT NULL, cascade delete |
| languages_code   | string | FK → languages(code), NOT NULL             |
| description      | text   | nullable                                   |
| action_label     | string | nullable                                   |
| created_at       | datetime | NOT NULL                                 |
| updated_at       | datetime | NOT NULL                                 |

## Rails

### Models

**`EventSpeaker`**
- `belongs_to :event`
- `has_many :event_speakers_translations, dependent: :destroy, inverse_of: :event_speaker`
- `def translations(language_code)` — finds translation by languages_code (same pattern as Ticket)

**`EventSpeakerTranslation`**
- `belongs_to :event_speaker`

**`Event`** gains:
- `has_many :event_speakers, -> { order(:sort) }, dependent: :destroy, inverse_of: :event`

### Serializer

**`EventSpeakerSerializer < ApplicationSerializer`**

| Attribute    | Source                                      |
|--------------|---------------------------------------------|
| name         | `object.name`                               |
| image        | `ApplicationSerializer.asset_url(object.image)` |
| action_url   | `object.action_url`                         |
| description  | `object.translations(languages_code)&.description` |
| action_label | `object.translations(languages_code)&.action_label` |

**`EventSerializer`** gains:
```ruby
attribute :speakers do |object|
  next nil if object.event_speakers.empty?
  EventSpeakerSerializer.new(object.event_speakers, params: { languages_code: params[:languages_code] })
end
```

## Migrations

1. `create_event_speakers` — creates the table with indexes and foreign keys
2. `create_event_speakers_translations` — creates the translations table with foreign keys

## Directus

Two new collections to be configured manually in Directus:

- **`event_speakers`** related to `events` (many-to-one on `event_id`); `image` field as a file relation to `directus_files`; `sort` field enabled for drag-and-drop ordering
- **`event_speakers_translations`** related to `event_speakers` (many-to-one on `event_speaker_id`); `languages_code` as a relation to `languages`

This mirrors the existing tickets / tickets_translations setup.

## Out of Scope

- No API endpoint changes — speakers are returned nested inside the existing `GET /event/:slug` response via `EventSerializer`
- No speaker-level endpoints
- No admin/auth layer changes
