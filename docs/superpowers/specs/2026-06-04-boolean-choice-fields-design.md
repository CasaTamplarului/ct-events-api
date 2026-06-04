# Boolean Choice Fields — Design Spec

**Date:** 2026-06-04

## Overview

Staff can add any number of per-event yes/no questions in Directus. Each question has a translated label and translated answer labels. The FE renders each question as either a toggle or a checkbox (staff-configurable). Attendees answer at checkout; required questions must be answered (either value is valid).

## Database

### New table: `event_boolean_fields`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigserial PK | |
| `event_id` | FK → events | cascade delete |
| `sort` | integer NOT NULL | default 0 |
| `required` | boolean NOT NULL | default false |
| `display_as` | string NOT NULL | `'toggle'` or `'checkbox'` |
| `created_at`, `updated_at` | timestamps | |

Index on `(event_id, sort)`.

### New table: `event_boolean_field_translations`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigserial PK | |
| `event_boolean_field_id` | FK → event_boolean_fields | cascade delete |
| `languages_code` | FK → languages (code) | |
| `label` | string NOT NULL | the question text |
| `true_label` | string NOT NULL | e.g. "Da, sunt de acord" |
| `false_label` | string NOT NULL | e.g. "Nu sunt de acord" |
| `created_at`, `updated_at` | timestamps | |

Unique index on `(event_boolean_field_id, languages_code)`.

### New table: `attendee_boolean_field_responses`

| Column | Type | Notes |
|--------|------|-------|
| `id` | bigserial PK | |
| `attendee_id` | FK → attendees | cascade delete |
| `event_boolean_field_id` | FK → event_boolean_fields | cascade delete |
| `value` | boolean NOT NULL | |
| `created_at`, `updated_at` | timestamps | |

Unique index on `(attendee_id, event_boolean_field_id)` — one response per field per attendee.

## Models

### `EventBooleanField`

```ruby
class EventBooleanField < ApplicationRecord
  belongs_to :event
  has_many :event_boolean_field_translations, dependent: :destroy

  validates :display_as, inclusion: { in: %w[toggle checkbox] }

  def label_for(languages_code)
    translation_for(languages_code)&.label
  end

  def true_label_for(languages_code)
    translation_for(languages_code)&.true_label
  end

  def false_label_for(languages_code)
    translation_for(languages_code)&.false_label
  end

  private

    def translation_for(languages_code)
      event_boolean_field_translations.find { |t| t.languages_code == languages_code } ||
        event_boolean_field_translations.find { |t| t.languages_code == 'ro-RO' }
    end
end
```

### `EventBooleanFieldTranslation`

```ruby
class EventBooleanFieldTranslation < ApplicationRecord
  belongs_to :event_boolean_field
  belongs_to :language, foreign_key: :languages_code, primary_key: :code, optional: true

  validates :languages_code, presence: true
  validates :label, presence: true
  validates :true_label, presence: true
  validates :false_label, presence: true
  validates :languages_code, uniqueness: { scope: :event_boolean_field_id }
end
```

### `AttendeeBooleanFieldResponse`

```ruby
class AttendeeBooleanFieldResponse < ApplicationRecord
  belongs_to :attendee
  belongs_to :event_boolean_field

  validates :value, inclusion: { in: [true, false] }
  validates :event_boolean_field_id, uniqueness: { scope: :attendee_id }
end
```

### `Event` model addition

```ruby
has_many :event_boolean_fields, -> { order(:sort) }, dependent: :destroy, inverse_of: :event
```

### `Attendee` model addition

```ruby
has_many :attendee_boolean_field_responses, dependent: :destroy
```

## API

### Event detail — EventSerializer

New `boolean_fields` attribute alongside existing `template_docs` and `attendee_fields`:

```json
"boolean_fields": [
  {
    "id": 1,
    "required": true,
    "display_as": "checkbox",
    "label": "Ești de acord cu regulamentul evenimentului?",
    "true_label": "Da, sunt de acord",
    "false_label": "Nu sunt de acord"
  }
]
```

Implementation:

```ruby
attribute :boolean_fields do |object|
  fields = object.event_boolean_fields.includes(:event_boolean_field_translations)
  fields.map do |f|
    {
      id:          f.id,
      required:    f.required,
      display_as:  f.display_as,
      label:       f.label_for(params[:languages_code]),
      true_label:  f.true_label_for(params[:languages_code]),
      false_label: f.false_label_for(params[:languages_code])
    }
  end
end
```

### Checkout — OrdersController

Each item's `attendee` gains an optional `boolean_field_responses` array:

```json
{
  "items": [{
    "event_slug": "conferinta-2026",
    "ticket_name": "General",
    "attendee": {
      "first_name": "Ion",
      "boolean_field_responses": [
        { "event_boolean_field_id": 1, "value": true }
      ]
    }
  }]
}
```

**New private methods on `OrdersController`:**

- `parse_boolean_field_responses(raw_attendee)` — extracts and coerces the array from params; returns `[]` when absent
- `validate_boolean_field_responses(event:, responses:)` — two checks:
  1. Each `event_boolean_field_id` must belong to the booked event → 400 with `orders.errors.invalid_boolean_field`
  2. All `required: true` boolean fields must have a response (any value) → 400 with `orders.errors.missing_required_boolean_fields` listing missing labels
- `persist_order` extended to call `AttendeeBooleanFieldResponse.create!` per response inside the existing transaction

**Validation** is called inside `resolve_items` alongside the existing `validate_template_doc_uploads`, breaking the loop on failure.

## I18n

Add to `config/locales/en.yml` under `orders.errors`:
```yaml
invalid_boolean_field: "Invalid question for this event"
missing_required_boolean_fields: "Missing required answer(s): %{fields}"
```

Add to `config/locales/ro.yml` under `orders.errors`:
```yaml
invalid_boolean_field: "Întrebare invalidă pentru acest eveniment"
missing_required_boolean_fields: "Răspunsuri obligatorii lipsă: %{fields}"
```

## New Files Summary

| File | Purpose |
|------|---------|
| `db/migrate/..._create_event_boolean_fields.rb` | Migration |
| `db/migrate/..._create_event_boolean_field_translations.rb` | Migration |
| `db/migrate/..._create_attendee_boolean_field_responses.rb` | Migration |
| `app/models/event_boolean_field.rb` | Model |
| `app/models/event_boolean_field_translation.rb` | Translation model |
| `app/models/attendee_boolean_field_response.rb` | Response model |

### Modified Files

| File | Change |
|------|--------|
| `app/models/event.rb` | Add `has_many :event_boolean_fields` |
| `app/models/attendee.rb` | Add `has_many :attendee_boolean_field_responses` |
| `app/serializers/event_serializer.rb` | Add `boolean_fields` attribute |
| `app/controllers/api/v1/orders_controller.rb` | Validate + persist boolean field responses |
| `config/locales/en.yml` | New error keys |
| `config/locales/ro.yml` | New error keys |
| `spec/factories/event_boolean_fields.rb` | Factory |
| `spec/factories/event_boolean_field_translations.rb` | Factory |
| `spec/factories/attendee_boolean_field_responses.rb` | Factory |
| `spec/models/event_boolean_field_spec.rb` | Model spec |
| `spec/models/attendee_boolean_field_response_spec.rb` | Model spec |
| `spec/requests/api/v1/event_spec.rb` | Serializer coverage |
| `spec/requests/api/v1/orders_spec.rb` | Checkout integration |
