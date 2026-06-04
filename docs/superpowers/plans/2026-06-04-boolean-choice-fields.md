# Boolean Choice Fields Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let staff define per-event yes/no questions in Directus with translated labels and answer text; attendees answer at checkout and responses are persisted.

**Architecture:** Three new DB tables (`event_boolean_fields`, `event_boolean_field_translations`, `attendee_boolean_field_responses`) following the exact same pattern as `event_template_docs` and `attendee_template_doc_uploads`. The event serializer gains a `boolean_fields` attribute; the orders controller gains parse/validate/persist methods that slot in alongside the existing template-doc-upload logic.

**Tech Stack:** Rails 8, PostgreSQL, Alba serializers, RSpec + FactoryBot + shoulda-matchers, I18n (en + ro).

---

## File Map

| Action | Path |
|--------|------|
| Create (migration) | `db/migrate/..._create_event_boolean_fields.rb` |
| Create (migration) | `db/migrate/..._create_event_boolean_field_translations.rb` |
| Create (migration) | `db/migrate/..._create_attendee_boolean_field_responses.rb` |
| Create | `app/models/event_boolean_field.rb` |
| Create | `app/models/event_boolean_field_translation.rb` |
| Create | `app/models/attendee_boolean_field_response.rb` |
| Create | `spec/factories/event_boolean_fields.rb` |
| Create | `spec/factories/event_boolean_field_translations.rb` |
| Create | `spec/factories/attendee_boolean_field_responses.rb` |
| Create | `spec/models/event_boolean_field_spec.rb` |
| Create | `spec/models/attendee_boolean_field_response_spec.rb` |
| Modify | `app/models/event.rb` |
| Modify | `app/models/attendee.rb` |
| Modify | `app/serializers/event_serializer.rb` |
| Modify | `app/controllers/api/v1/orders_controller.rb` |
| Modify | `config/locales/en.yml` |
| Modify | `config/locales/ro.yml` |
| Modify | `spec/requests/api/v1/event_spec.rb` |
| Modify | `spec/requests/api/v1/orders_spec.rb` |

---

## Task 1: Migrations

**Files:**
- Create: `db/migrate/..._create_event_boolean_fields.rb`
- Create: `db/migrate/..._create_event_boolean_field_translations.rb`
- Create: `db/migrate/..._create_attendee_boolean_field_responses.rb`

- [ ] **Step 1: Generate three migrations**

```bash
bin/rails g migration CreateEventBooleanFields
bin/rails g migration CreateEventBooleanFieldTranslations
bin/rails g migration CreateAttendeeBooleanFieldResponses
```

- [ ] **Step 2: Replace the body of `CreateEventBooleanFields`**

```ruby
# frozen_string_literal: true

class CreateEventBooleanFields < ActiveRecord::Migration[8.1]
  def change
    create_table :event_boolean_fields do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.integer :sort,       null: false, default: 0
      t.boolean :required,   null: false, default: false
      t.string  :display_as, null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :event_boolean_fields, %i[event_id sort]
  end
end
```

- [ ] **Step 3: Replace the body of `CreateEventBooleanFieldTranslations`**

```ruby
# frozen_string_literal: true

class CreateEventBooleanFieldTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :event_boolean_field_translations do |t|
      t.references :event_boolean_field, null: false, foreign_key: { on_delete: :cascade }
      t.string :languages_code, null: false
      t.string :label,          null: false
      t.string :true_label,     null: false
      t.string :false_label,    null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :event_boolean_field_translations,
              %i[event_boolean_field_id languages_code],
              unique: true,
              name: 'idx_event_boolean_field_translations_unique'

    add_foreign_key :event_boolean_field_translations, :languages,
                    column: :languages_code,
                    primary_key: :code,
                    name: 'event_boolean_field_translations_languages_code_fk'
  end
end
```

- [ ] **Step 4: Replace the body of `CreateAttendeeBooleanFieldResponses`**

```ruby
# frozen_string_literal: true

class CreateAttendeeBooleanFieldResponses < ActiveRecord::Migration[8.1]
  def change
    create_table :attendee_boolean_field_responses do |t|
      t.references :attendee,            null: false, foreign_key: { on_delete: :cascade }
      t.references :event_boolean_field, null: false, foreign_key: { on_delete: :cascade }
      t.boolean    :value,               null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :attendee_boolean_field_responses,
              %i[attendee_id event_boolean_field_id],
              unique: true,
              name: 'idx_attendee_boolean_field_responses_unique'
  end
end
```

- [ ] **Step 5: Run migrations**

```bash
bin/rails db:migrate
```

Expected output ends with: `CreateAttendeeBooleanFieldResponses: migrated`

- [ ] **Step 6: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Add migrations for boolean choice fields"
```

---

## Task 2: Models, associations, and factories

**Files:**
- Create: `app/models/event_boolean_field.rb`
- Create: `app/models/event_boolean_field_translation.rb`
- Create: `app/models/attendee_boolean_field_response.rb`
- Create: `spec/factories/event_boolean_fields.rb`
- Create: `spec/factories/event_boolean_field_translations.rb`
- Create: `spec/factories/attendee_boolean_field_responses.rb`
- Modify: `app/models/event.rb`
- Modify: `app/models/attendee.rb`

- [ ] **Step 1: Create `app/models/event_boolean_field.rb`**

```ruby
# frozen_string_literal: true

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

- [ ] **Step 2: Create `app/models/event_boolean_field_translation.rb`**

```ruby
# frozen_string_literal: true

class EventBooleanFieldTranslation < ApplicationRecord
  belongs_to :event_boolean_field
  belongs_to :language, foreign_key: :languages_code, primary_key: :code, optional: true

  validates :languages_code, presence: true
  validates :label,           presence: true
  validates :true_label,      presence: true
  validates :false_label,     presence: true
  validates :languages_code, uniqueness: { scope: :event_boolean_field_id }
end
```

- [ ] **Step 3: Create `app/models/attendee_boolean_field_response.rb`**

```ruby
# frozen_string_literal: true

class AttendeeBooleanFieldResponse < ApplicationRecord
  belongs_to :attendee
  belongs_to :event_boolean_field

  validates :value, inclusion: { in: [true, false] }
  validates :event_boolean_field_id, uniqueness: { scope: :attendee_id }
end
```

- [ ] **Step 4: Add association to `app/models/event.rb`**

After the `has_many :event_template_docs` line, add:

```ruby
has_many :event_boolean_fields, -> { order(:sort) }, dependent: :destroy, inverse_of: :event
```

- [ ] **Step 5: Add association to `app/models/attendee.rb`**

After the `has_many :attendee_template_doc_uploads` line, add:

```ruby
has_many :attendee_boolean_field_responses, dependent: :destroy
```

- [ ] **Step 6: Create `spec/factories/event_boolean_fields.rb`**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :event_boolean_field do
    association :event
    sort       { 0 }
    required   { false }
    display_as { 'checkbox' }
  end
end
```

- [ ] **Step 7: Create `spec/factories/event_boolean_field_translations.rb`**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :event_boolean_field_translation do
    association :event_boolean_field
    languages_code { 'ro-RO' }
    label       { 'Ești de acord?' }
    true_label  { 'Da' }
    false_label { 'Nu' }
  end
end
```

- [ ] **Step 8: Create `spec/factories/attendee_boolean_field_responses.rb`**

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :attendee_boolean_field_response do
    association :attendee
    association :event_boolean_field
    value { true }
  end
end
```

- [ ] **Step 9: Commit**

```bash
git add app/models/event_boolean_field.rb \
        app/models/event_boolean_field_translation.rb \
        app/models/attendee_boolean_field_response.rb \
        app/models/event.rb \
        app/models/attendee.rb \
        spec/factories/event_boolean_fields.rb \
        spec/factories/event_boolean_field_translations.rb \
        spec/factories/attendee_boolean_field_responses.rb
git commit -m "Add EventBooleanField, EventBooleanFieldTranslation, AttendeeBooleanFieldResponse models and factories"
```

---

## Task 3: Model specs

**Files:**
- Create: `spec/models/event_boolean_field_spec.rb`
- Create: `spec/models/attendee_boolean_field_response_spec.rb`

- [ ] **Step 1: Create `spec/models/event_boolean_field_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EventBooleanField, type: :model do
  subject(:field) { build(:event_boolean_field) }

  it { is_expected.to belong_to(:event) }
  it { is_expected.to have_many(:event_boolean_field_translations).dependent(:destroy) }
  it { is_expected.to validate_inclusion_of(:display_as).in_array(%w[toggle checkbox]) }

  describe '#label_for' do
    let!(:field) { create(:event_boolean_field) }

    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'ro-RO',
                                            label: 'Întrebare', true_label: 'Da', false_label: 'Nu')
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'en-US',
                                            label: 'Question', true_label: 'Yes', false_label: 'No')
    end

    it 'returns the label for an exact language match' do
      expect(field.label_for('en-US')).to eq('Question')
    end

    it 'falls back to ro-RO when the requested language has no translation' do
      expect(field.label_for('fr-FR')).to eq('Întrebare')
    end
  end

  describe '#true_label_for and #false_label_for' do
    let!(:field) { create(:event_boolean_field) }

    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'ro-RO',
                                            label: 'Întrebare', true_label: 'Da, accept', false_label: 'Nu accept')
    end

    it 'returns true_label for the language' do
      expect(field.true_label_for('ro-RO')).to eq('Da, accept')
    end

    it 'returns false_label for the language' do
      expect(field.false_label_for('ro-RO')).to eq('Nu accept')
    end
  end
end
```

- [ ] **Step 2: Create `spec/models/attendee_boolean_field_response_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AttendeeBooleanFieldResponse, type: :model do
  subject(:response) { build(:attendee_boolean_field_response) }

  it { is_expected.to belong_to(:attendee) }
  it { is_expected.to belong_to(:event_boolean_field) }
  it { is_expected.to validate_inclusion_of(:value).in_array([true, false]) }
  it { is_expected.to validate_uniqueness_of(:event_boolean_field_id).scoped_to(:attendee_id) }
end
```

- [ ] **Step 3: Run the specs**

```bash
bin/rspec spec/models/event_boolean_field_spec.rb spec/models/attendee_boolean_field_response_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add spec/models/event_boolean_field_spec.rb spec/models/attendee_boolean_field_response_spec.rb
git commit -m "Add model specs for EventBooleanField and AttendeeBooleanFieldResponse"
```

---

## Task 4: EventSerializer — `boolean_fields` attribute (TDD)

**Files:**
- Modify: `spec/requests/api/v1/event_spec.rb`
- Modify: `app/serializers/event_serializer.rb`
- Modify: `app/models/event.rb` (already done in Task 2 — `has_many :event_boolean_fields`)

- [ ] **Step 1: Add failing specs to `spec/requests/api/v1/event_spec.rb`**

Append the following `context` block before the final `end` that closes the `RSpec.describe` block:

```ruby
  context 'boolean_fields' do
    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' }
    end

    it 'returns an empty array when the event has no boolean fields' do
      get_event
      expect(json['boolean_fields']).to eq([])
    end

    it 'returns boolean fields with translated label, true_label, false_label' do
      field = EventBooleanField.create!(event: event, sort: 0, required: true, display_as: 'checkbox')
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'ro-RO',
                                            label: 'Ești de acord?',
                                            true_label: 'Da, sunt de acord',
                                            false_label: 'Nu sunt de acord')

      get_event

      expect(json['boolean_fields'].length).to eq(1)
      bf = json['boolean_fields'].first
      expect(bf['id']).to eq(field.id)
      expect(bf['required']).to be true
      expect(bf['display_as']).to eq('checkbox')
      expect(bf['label']).to eq('Ești de acord?')
      expect(bf['true_label']).to eq('Da, sunt de acord')
      expect(bf['false_label']).to eq('Nu sunt de acord')
    end

    it 'falls back to ro-RO labels when the requested language has no translation' do
      create(:events_translation, event: event, languages_code: 'en-US', name: 'Tabara Impact EN',
             tag_line: 'A camp')
      field = EventBooleanField.create!(event: event, sort: 0, required: false, display_as: 'toggle')
      EventBooleanFieldTranslation.create!(event_boolean_field: field, languages_code: 'ro-RO',
                                            label: 'Ești de acord?', true_label: 'Da', false_label: 'Nu')

      get "/api/v1/en-US/event/#{event.slug}"

      expect(json['boolean_fields'].first['label']).to eq('Ești de acord?')
    end

    it 'returns boolean fields ordered by sort' do
      field1 = EventBooleanField.create!(event: event, sort: 1, required: false, display_as: 'checkbox')
      field2 = EventBooleanField.create!(event: event, sort: 0, required: false, display_as: 'toggle')
      EventBooleanFieldTranslation.create!(event_boolean_field: field1, languages_code: 'ro-RO',
                                            label: 'Second', true_label: 'Da', false_label: 'Nu')
      EventBooleanFieldTranslation.create!(event_boolean_field: field2, languages_code: 'ro-RO',
                                            label: 'First', true_label: 'Da', false_label: 'Nu')

      get_event

      expect(json['boolean_fields'].map { |f| f['label'] }).to eq(%w[First Second])
    end
  end
```

- [ ] **Step 2: Run specs to confirm they fail**

```bash
bin/rspec spec/requests/api/v1/event_spec.rb
```

Expected: new boolean_fields examples fail with `NoMethodError` or key not present in JSON.

- [ ] **Step 3: Add `boolean_fields` attribute to `app/serializers/event_serializer.rb`**

After the `attribute :template_docs` block (lines 49–58), add:

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

- [ ] **Step 4: Run specs to confirm they pass**

```bash
bin/rspec spec/requests/api/v1/event_spec.rb
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Run rubocop**

```bash
bin/rubocop app/serializers/event_serializer.rb
```

Fix any offenses before committing.

- [ ] **Step 6: Commit**

```bash
git add app/serializers/event_serializer.rb spec/requests/api/v1/event_spec.rb
git commit -m "Add boolean_fields attribute to EventSerializer"
```

---

## Task 5: I18n error strings

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`

- [ ] **Step 1: Add to `config/locales/en.yml`**

Under `orders:` → `errors:`, append after the `missing_required_docs` line:

```yaml
      invalid_boolean_field: "Invalid question for this event"
      missing_required_boolean_fields: "Missing required answer(s): %{fields}"
```

- [ ] **Step 2: Add to `config/locales/ro.yml`**

Under `orders:` → `errors:`, append after the `missing_required_docs` line:

```yaml
      invalid_boolean_field: "Întrebare invalidă pentru acest eveniment"
      missing_required_boolean_fields: "Răspunsuri obligatorii lipsă: %{fields}"
```

- [ ] **Step 3: Verify YAML is valid**

```bash
bin/rails runner "puts I18n.t('orders.errors.invalid_boolean_field')"
bin/rails runner "puts I18n.t('orders.errors.missing_required_boolean_fields', fields: 'test')"
```

Expected output: the English strings without errors.

- [ ] **Step 4: Commit**

```bash
git add config/locales/en.yml config/locales/ro.yml
git commit -m "Add I18n strings for boolean field validation errors"
```

---

## Task 6: OrdersController integration (TDD)

**Files:**
- Modify: `spec/requests/api/v1/orders_spec.rb`
- Modify: `app/controllers/api/v1/orders_controller.rb`

- [ ] **Step 1: Add failing specs to `spec/requests/api/v1/orders_spec.rb`**

Append the following `describe` block before the final `end` that closes the `RSpec.describe` block:

```ruby
  describe 'boolean field responses' do
    let!(:boolean_field) { create(:event_boolean_field, event: event, required: false) }
    let!(:boolean_field_translation) do
      EventBooleanFieldTranslation.create!(
        event_boolean_field: boolean_field,
        languages_code: language_code,
        label: 'Ești de acord?',
        true_label: 'Da',
        false_label: 'Nu'
      )
    end

    let(:item_with_response) do
      valid_item.deep_merge(attendee: {
        boolean_field_responses: [
          { event_boolean_field_id: boolean_field.id, value: true }
        ]
      })
    end

    it 'creates AttendeeBooleanFieldResponse records' do
      post_order([item_with_response])

      expect(response).to have_http_status(:created)
      expect(AttendeeBooleanFieldResponse.count).to eq(1)
      expect(AttendeeBooleanFieldResponse.last.event_boolean_field).to eq(boolean_field)
      expect(AttendeeBooleanFieldResponse.last.value).to be true
    end

    it 'accepts false as a valid response value' do
      item = valid_item.deep_merge(attendee: {
        boolean_field_responses: [{ event_boolean_field_id: boolean_field.id, value: false }]
      })
      post_order([item])

      expect(response).to have_http_status(:created)
      expect(AttendeeBooleanFieldResponse.last.value).to be false
    end

    it 'ignores boolean_field_responses when none are provided' do
      post_order([valid_item])

      expect(response).to have_http_status(:created)
      expect(AttendeeBooleanFieldResponse.count).to eq(0)
    end

    context 'when event_boolean_field_id belongs to a different event' do
      let!(:other_event) { create(:event, status: :live) }
      let!(:other_field)  { create(:event_boolean_field, event: other_event) }

      it 'returns 400' do
        item = valid_item.deep_merge(attendee: {
          boolean_field_responses: [{ event_boolean_field_id: other_field.id, value: true }]
        })
        post_order([item])

        expect(response).to have_http_status(:bad_request)
        expect(json['error']).to be_present
      end
    end

    context 'when a required boolean field has no response' do
      let!(:boolean_field) { create(:event_boolean_field, event: event, required: true) }
      let!(:required_translation) do
        EventBooleanFieldTranslation.create!(
          event_boolean_field: boolean_field,
          languages_code: language_code,
          label: 'Ești de acord?',
          true_label: 'Da',
          false_label: 'Nu'
        )
      end

      it 'returns 400 and includes the missing field label in the error' do
        post_order([valid_item])

        expect(response).to have_http_status(:bad_request)
        expect(json['error']).to include('Ești de acord?')
      end
    end
  end
```

- [ ] **Step 2: Run specs to confirm they fail**

```bash
bin/rspec spec/requests/api/v1/orders_spec.rb
```

Expected: the new examples fail; all existing examples still pass.

- [ ] **Step 3: Update `app/controllers/api/v1/orders_controller.rb`**

Replace the entire file content with:

```ruby
# frozen_string_literal: true

module Api
  module V1
    class OrdersController < ActionController::API
      PERMITTED_ATTENDEE_FIELDS = %w[first_name last_name email_address phone_number dietary_preference church_name
                                     city age].freeze

      before_action :set_locale
      before_action :set_current_user

      def create
        items = params[:items]
        return render json: { error: t('orders.errors.items_blank') }, status: :bad_request if items.blank?

        resolved = resolve_items(items)
        return if performed?

        check_capacity(resolved)
        return if performed?

        order = persist_order(resolved)
        SendgridService.send_booking_confirmation(order: order, language: params[:languages_code])
        render json: { order_reference: order.order_reference }, status: :created
      rescue StandardError
        render json: { error: t('orders.errors.internal_error') }, status: :internal_server_error
      end

      private

        def set_current_user
          token = request.headers['Authorization']&.split&.last
          return if token.blank?

          user_id = JwtService.decode(token)
          @current_user = User.active.find_by(id: user_id)
        rescue JWT::DecodeError
          nil
        end

        def resolve_items(items)
          items.each_with_object([]) do |item, result|
            event = Event.find_by(slug: item[:event_slug])
            unless event
              render json: { error: t('orders.errors.unknown_event', slug: item[:event_slug]) }, status: :bad_request
              break
            end

            ticket = event.tickets
                          .joins(:tickets_translations)
                          .where(tickets_translations: { name: item[:ticket_name],
                                                         languages_code: params[:languages_code] })
                          .first
            unless ticket
              render json: { error: t('orders.errors.unknown_ticket', name: item[:ticket_name]) }, status: :bad_request
              break
            end

            attrs     = attendee_attrs(item[:attendee])
            uploads   = parse_template_doc_uploads(item[:attendee])
            responses = parse_boolean_field_responses(item[:attendee])

            break unless template_doc_uploads_valid?(event: event, attendee_attrs: attrs, uploads: uploads)
            break unless boolean_field_responses_valid?(event: event, responses: responses)

            result << { event: event, ticket: ticket, attendee_attrs: attrs,
                        template_doc_uploads: uploads, boolean_field_responses: responses }
          end
        end

        def check_capacity(resolved)
          resolved.group_by { |i| i[:event] }.each do |event, items_for_event|
            next unless event.max_number_of_people

            if event.attendees.count + items_for_event.size > event.max_number_of_people
              render json: { error: t('orders.errors.fully_booked') }, status: :conflict
              break
            end
          end
        end

        def persist_order(resolved)
          order = nil
          ActiveRecord::Base.transaction do
            order = Order.create!(user: @current_user)
            resolved.each do |item|
              email = item[:attendee_attrs][:email_address]
              linked_user = email.present? ? User.active.find_by('LOWER(email) = LOWER(?)', email) : nil
              attendee = order.attendees.create!(
                event: item[:event],
                ticket: item[:ticket],
                user: linked_user,
                **item[:attendee_attrs]
              )

              item[:template_doc_uploads].each do |upload|
                AttendeeTemplateDocUpload.create!(
                  attendee: attendee,
                  event_template_doc_id: upload[:event_template_doc_id],
                  directus_files_id: upload[:directus_files_id]
                )
              end

              item[:boolean_field_responses].each do |response|
                AttendeeBooleanFieldResponse.create!(
                  attendee: attendee,
                  event_boolean_field_id: response[:event_boolean_field_id],
                  value: response[:value]
                )
              end
            end
          end
          order
        end

        def parse_template_doc_uploads(raw_attendee)
          return [] if raw_attendee.blank?

          Array(raw_attendee[:template_doc_uploads]).map do |u|
            {
              event_template_doc_id: u[:event_template_doc_id].to_i,
              directus_files_id: u[:directus_files_id].to_s
            }
          end
        end

        def parse_boolean_field_responses(raw_attendee)
          return [] if raw_attendee.blank?

          Array(raw_attendee[:boolean_field_responses]).map do |r|
            {
              event_boolean_field_id: r[:event_boolean_field_id].to_i,
              value: r[:value]
            }
          end
        end

        def template_doc_uploads_valid?(event:, attendee_attrs:, uploads:)
          return false unless uploads_belong_to_event?(event, uploads)

          missing = missing_required_doc_labels(event, attendee_attrs, uploads)
          if missing.any?
            render json: { error: t('orders.errors.missing_required_docs', docs: missing.join(', ')) },
                   status: :bad_request
            return false
          end

          true
        end

        def uploads_belong_to_event?(event, uploads)
          event_doc_ids = event.event_template_docs.map(&:id)
          uploads.each do |upload|
            next if event_doc_ids.include?(upload[:event_template_doc_id])

            render json: { error: t('orders.errors.invalid_template_doc') }, status: :bad_request
            return false
          end
          true
        end

        def missing_required_doc_labels(event, attendee_attrs, uploads)
          uploaded_ids = uploads.pluck(:event_template_doc_id)
          attendee_age = attendee_attrs[:age]&.to_i

          event.event_template_docs.filter_map do |doc|
            next unless required_upload_missing?(doc, attendee_age, uploaded_ids)

            doc.label_for(params[:languages_code]) || doc.id.to_s
          end
        end

        def required_upload_missing?(doc, attendee_age, uploaded_ids)
          doc.required && doc_applies_to_age?(doc, attendee_age) && uploaded_ids.exclude?(doc.id)
        end

        def doc_applies_to_age?(doc, attendee_age)
          return true if doc.age_from.nil? && doc.age_to.nil?
          return false if attendee_age.nil?

          (doc.age_from.nil? || attendee_age >= doc.age_from) &&
            (doc.age_to.nil? || attendee_age <= doc.age_to)
        end

        def boolean_field_responses_valid?(event:, responses:)
          return false unless boolean_fields_belong_to_event?(event, responses)

          missing = missing_required_boolean_field_labels(event, responses)
          if missing.any?
            render json: { error: t('orders.errors.missing_required_boolean_fields', fields: missing.join(', ')) },
                   status: :bad_request
            return false
          end

          true
        end

        def boolean_fields_belong_to_event?(event, responses)
          event_field_ids = event.event_boolean_fields.map(&:id)
          responses.each do |response|
            next if event_field_ids.include?(response[:event_boolean_field_id])

            render json: { error: t('orders.errors.invalid_boolean_field') }, status: :bad_request
            return false
          end
          true
        end

        def missing_required_boolean_field_labels(event, responses)
          responded_ids = responses.pluck(:event_boolean_field_id)

          event.event_boolean_fields.filter_map do |field|
            next unless field.required
            next if responded_ids.include?(field.id)

            field.label_for(params[:languages_code]) || field.id.to_s
          end
        end

        def attendee_attrs(raw)
          raw.to_unsafe_h.slice(*PERMITTED_ATTENDEE_FIELDS).symbolize_keys
        end

        def set_locale
          lang = params[:languages_code].to_s.split('-').first.to_sym
          I18n.locale = I18n.available_locales.include?(lang) ? lang : I18n.default_locale
        end

        def t(key, **)
          I18n.t(key, **)
        end
    end
  end
end
```

- [ ] **Step 4: Run orders specs**

```bash
bin/rspec spec/requests/api/v1/orders_spec.rb
```

Expected: all examples pass (existing + new), 0 failures.

- [ ] **Step 5: Run full suite**

```bash
bin/rspec
```

Expected: 0 failures.

- [ ] **Step 6: Run rubocop**

```bash
bin/rubocop app/controllers/api/v1/orders_controller.rb
```

Fix any offenses before committing.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/orders_controller.rb spec/requests/api/v1/orders_spec.rb
git commit -m "Extend orders controller to validate and persist boolean field responses"
```
