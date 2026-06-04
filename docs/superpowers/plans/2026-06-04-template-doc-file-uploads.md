# Template Doc File Uploads Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow attendees to upload completed/signed template documents during checkout via a two-step flow: upload file to get a UUID, then reference that UUID per attendee in the order payload.

**Architecture:** A new public `POST /api/v1/uploads` endpoint proxies the file to Directus via `Net::HTTP` multipart and returns the `directus_files_id`. The `POST /api/v1/:lang/orders` endpoint is extended to accept `template_doc_uploads` per attendee, validate them, and persist them as `AttendeeTemplateDocUpload` records inside the existing order transaction.

**Tech Stack:** Rails 8, Net::HTTP (multipart), Alba serializers, RSpec + WebMock + FactoryBot, I18n (en + ro).

---

## File Map

| Action | Path |
|--------|------|
| Create | `app/models/directus_file.rb` |
| Create | `app/models/attendee_template_doc_upload.rb` |
| Create | `app/services/directus_upload_service.rb` |
| Create | `app/controllers/api/v1/uploads_controller.rb` |
| Create | `spec/factories/directus_files.rb` |
| Create | `spec/factories/event_template_docs.rb` |
| Create | `spec/factories/attendee_template_doc_uploads.rb` |
| Create | `spec/models/attendee_template_doc_upload_spec.rb` |
| Create | `spec/services/directus_upload_service_spec.rb` |
| Create | `spec/requests/api/v1/uploads_spec.rb` |
| Create | `spec/fixtures/files/test.pdf` |
| Migrate | `db/migrate/<timestamp>_create_attendee_template_doc_uploads.rb` |
| Modify | `app/models/attendee.rb` |
| Modify | `app/controllers/api/v1/orders_controller.rb` |
| Modify | `config/routes.rb` |
| Modify | `config/locales/en.yml` |
| Modify | `config/locales/ro.yml` |
| Modify | `spec/requests/api/v1/orders_spec.rb` |

---

## Task 1: DirectusFile model + factory

Needed by all subsequent tests that create `EventTemplateDoc` or `AttendeeTemplateDocUpload` records, both of which have FK constraints to `directus_files`.

**Files:**
- Create: `app/models/directus_file.rb`
- Create: `spec/factories/directus_files.rb`

- [ ] **Step 1: Create the model**

```ruby
# app/models/directus_file.rb
# frozen_string_literal: true

class DirectusFile < ApplicationRecord
  self.table_name = 'directus_files'
  self.primary_key = 'id'
end
```

- [ ] **Step 2: Create the factory**

```ruby
# spec/factories/directus_files.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :directus_file do
    id { SecureRandom.uuid }
    filename_download { 'test.pdf' }
    storage { 'local' }
  end
end
```

- [ ] **Step 3: Commit**

```bash
git add app/models/directus_file.rb spec/factories/directus_files.rb
git commit -m "Add DirectusFile model and factory for test support"
```

---

## Task 2: EventTemplateDoc factory

Needed by the orders_spec tests for template doc validation.

**Files:**
- Create: `spec/factories/event_template_docs.rb`

- [ ] **Step 1: Create the factory**

```ruby
# spec/factories/event_template_docs.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :event_template_doc do
    association :event
    directus_files_id { create(:directus_file).id }
    sort { 0 }
    required { false }
    age_from { nil }
    age_to { nil }
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add spec/factories/event_template_docs.rb
git commit -m "Add EventTemplateDoc factory"
```

---

## Task 3: Migration + AttendeeTemplateDocUpload model

**Files:**
- Create: `db/migrate/<timestamp>_create_attendee_template_doc_uploads.rb`
- Create: `app/models/attendee_template_doc_upload.rb`
- Modify: `app/models/attendee.rb`
- Create: `spec/factories/attendee_template_doc_uploads.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails g migration CreateAttendeeTemplateDocUploads
```

- [ ] **Step 2: Edit the generated migration file** (replace its body with):

```ruby
# frozen_string_literal: true

class CreateAttendeeTemplateDocUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :attendee_template_doc_uploads do |t|
      t.references :attendee, null: false, foreign_key: { on_delete: :cascade }
      t.references :event_template_doc, null: false, foreign_key: { on_delete: :cascade }
      t.uuid :directus_files_id, null: false

      t.timestamps default: -> { 'CURRENT_TIMESTAMP' }
    end

    add_index :attendee_template_doc_uploads,
              %i[attendee_id event_template_doc_id],
              unique: true,
              name: 'idx_attendee_template_doc_uploads_unique'

    add_foreign_key :attendee_template_doc_uploads, :directus_files,
                    column: :directus_files_id,
                    name: 'attendee_template_doc_uploads_directus_files_id_fk'
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected output ends with: `CreateAttendeeTemplateDocUploads: migrated`

- [ ] **Step 4: Create the model**

```ruby
# app/models/attendee_template_doc_upload.rb
# frozen_string_literal: true

class AttendeeTemplateDocUpload < ApplicationRecord
  belongs_to :attendee
  belongs_to :event_template_doc

  validates :directus_files_id, presence: true
  validates :event_template_doc_id, uniqueness: { scope: :attendee_id }
end
```

- [ ] **Step 5: Add association to Attendee**

In `app/models/attendee.rb`, add after the `has_many :meal_stamps` line:

```ruby
has_many :attendee_template_doc_uploads, dependent: :destroy
```

- [ ] **Step 6: Create the factory**

```ruby
# spec/factories/attendee_template_doc_uploads.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :attendee_template_doc_upload do
    association :attendee
    association :event_template_doc
    directus_files_id { create(:directus_file).id }
  end
end
```

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/attendee_template_doc_upload.rb app/models/attendee.rb spec/factories/attendee_template_doc_uploads.rb
git commit -m "Add AttendeeTemplateDocUpload model and migration"
```

---

## Task 4: AttendeeTemplateDocUpload model spec

**Files:**
- Create: `spec/models/attendee_template_doc_upload_spec.rb`

- [ ] **Step 1: Write the spec**

```ruby
# spec/models/attendee_template_doc_upload_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AttendeeTemplateDocUpload, type: :model do
  subject(:upload) { build(:attendee_template_doc_upload) }

  it { is_expected.to belong_to(:attendee) }
  it { is_expected.to belong_to(:event_template_doc) }
  it { is_expected.to validate_presence_of(:directus_files_id) }
  it { is_expected.to validate_uniqueness_of(:event_template_doc_id).scoped_to(:attendee_id) }
end
```

- [ ] **Step 2: Run the spec**

```bash
bin/rspec spec/models/attendee_template_doc_upload_spec.rb
```

Expected: 4 examples, 0 failures

- [ ] **Step 3: Commit**

```bash
git add spec/models/attendee_template_doc_upload_spec.rb
git commit -m "Add AttendeeTemplateDocUpload model spec"
```

---

## Task 5: DirectusUploadService

Proxies a multipart file upload to Directus and returns the resulting UUID.

**Files:**
- Create: `app/services/directus_upload_service.rb`
- Create: `spec/services/directus_upload_service_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/directus_upload_service_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DirectusUploadService do
  let(:directus_url) { ENV.fetch('DIRECTUS_URL', 'http://localhost:8091') }
  let(:file) do
    instance_double(
      ActionDispatch::Http::UploadedFile,
      original_filename: 'consent.pdf',
      content_type: 'application/pdf',
      read: '%PDF-1.4 fake pdf content'
    )
  end

  describe '.upload' do
    context 'when Directus responds successfully' do
      before do
        stub_request(:post, "#{directus_url}/files")
          .to_return(
            status: 200,
            body: { data: { id: 'abc-0000-0000-0000-000000000000' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns the directus file UUID' do
        result = described_class.upload(file)
        expect(result).to eq('abc-0000-0000-0000-000000000000')
      end

      it 'sends a multipart POST to the Directus /files endpoint' do
        described_class.upload(file)
        expect(WebMock).to have_requested(:post, "#{directus_url}/files")
          .with(headers: { 'Content-Type' => /multipart\/form-data/ })
      end
    end

    context 'when Directus returns a non-2xx response' do
      before do
        stub_request(:post, "#{directus_url}/files")
          .to_return(status: 500, body: 'Internal Server Error')
      end

      it 'raises DirectusUploadService::UploadError' do
        expect { described_class.upload(file) }.to raise_error(DirectusUploadService::UploadError)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bin/rspec spec/services/directus_upload_service_spec.rb
```

Expected: fails with `uninitialized constant DirectusUploadService`

- [ ] **Step 3: Implement the service**

```ruby
# app/services/directus_upload_service.rb
# frozen_string_literal: true

class DirectusUploadService
  DIRECTUS_URL = ENV.fetch('DIRECTUS_URL', 'http://localhost:8091')

  UploadError = Class.new(StandardError)

  def self.upload(file)
    new(file).upload
  end

  def initialize(file)
    @file = file
  end

  def upload
    uri = URI("#{DIRECTUS_URL}/files")
    boundary = "RailsBoundary#{SecureRandom.hex(8)}"

    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{admin_token}"
    req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
    req.body = build_multipart_body(boundary)

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') do |http|
      http.request(req)
    end

    raise UploadError, "Directus upload failed: #{res.code}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body).dig('data', 'id')
  end

  private

    def build_multipart_body(boundary)
      crlf = "\r\n"
      parts = [
        "--#{boundary}#{crlf}",
        "Content-Disposition: form-data; name=\"file\"; filename=\"#{@file.original_filename}\"#{crlf}",
        "Content-Type: #{@file.content_type}#{crlf}",
        crlf,
        @file.read,
        "#{crlf}--#{boundary}--#{crlf}"
      ]
      parts.map(&:b).join
    end

    def admin_token
      Rails.application.credentials.dig(:directus, :admin_token)
    end
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bin/rspec spec/services/directus_upload_service_spec.rb
```

Expected: 3 examples, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/services/directus_upload_service.rb spec/services/directus_upload_service_spec.rb
git commit -m "Add DirectusUploadService to proxy file uploads to Directus"
```

---

## Task 6: UploadsController + route

**Files:**
- Create: `app/controllers/api/v1/uploads_controller.rb`
- Create: `spec/requests/api/v1/uploads_spec.rb`
- Create: `spec/fixtures/files/test.pdf`
- Modify: `config/routes.rb`

- [ ] **Step 1: Create a minimal PDF fixture**

```bash
mkdir -p spec/fixtures/files
printf '%PDF-1.4 test' > spec/fixtures/files/test.pdf
```

- [ ] **Step 2: Write the failing request spec**

```ruby
# spec/requests/api/v1/uploads_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/uploads' do
  let(:pdf_file) do
    fixture_file_upload(Rails.root.join('spec/fixtures/files/test.pdf'), 'application/pdf')
  end

  before do
    allow(DirectusUploadService).to receive(:upload).and_return('new-uuid-0000-0000-000000000000')
  end

  describe 'success' do
    it 'returns 201 with directus_files_id' do
      post '/api/v1/uploads', params: { file: pdf_file }

      expect(response).to have_http_status(:created)
      expect(json['directus_files_id']).to eq('new-uuid-0000-0000-000000000000')
    end

    it 'calls DirectusUploadService.upload with the uploaded file' do
      post '/api/v1/uploads', params: { file: pdf_file }

      expect(DirectusUploadService).to have_received(:upload).once
    end
  end

  describe 'missing file' do
    it 'returns 400' do
      post '/api/v1/uploads', params: {}

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to be_present
    end
  end

  describe 'unsupported MIME type' do
    let(:txt_file) do
      fixture_file_upload(Rails.root.join('spec/fixtures/files/test.pdf'), 'text/plain')
    end

    it 'returns 400' do
      post '/api/v1/uploads', params: { file: txt_file }

      expect(response).to have_http_status(:bad_request)
      expect(json['error']).to be_present
    end
  end

  describe 'when Directus upload fails' do
    before do
      allow(DirectusUploadService).to receive(:upload)
        .and_raise(DirectusUploadService::UploadError, 'upstream error')
    end

    it 'returns 502' do
      post '/api/v1/uploads', params: { file: pdf_file }

      expect(response).to have_http_status(:bad_gateway)
    end
  end
end
```

- [ ] **Step 3: Run the spec to confirm it fails**

```bash
bin/rspec spec/requests/api/v1/uploads_spec.rb
```

Expected: fails with routing error (route not defined yet)

- [ ] **Step 4: Add the route**

In `config/routes.rb`, inside `namespace :v1 do`, add before the `namespace :scan` block:

```ruby
resources :uploads, only: :create
```

- [ ] **Step 5: Create the controller**

```ruby
# app/controllers/api/v1/uploads_controller.rb
# frozen_string_literal: true

module Api
  module V1
    class UploadsController < ActionController::API
      ALLOWED_TYPES = %w[application/pdf image/jpeg image/png].freeze

      def create
        file = params[:file]
        return render json: { error: 'file is required' }, status: :bad_request if file.blank?

        unless ALLOWED_TYPES.include?(file.content_type)
          return render json: { error: 'unsupported file type' }, status: :bad_request
        end

        uuid = DirectusUploadService.upload(file)
        render json: { directus_files_id: uuid }, status: :created
      rescue DirectusUploadService::UploadError => e
        Rails.logger.error("Directus upload failed: #{e.message}")
        render json: { error: 'file upload failed' }, status: :bad_gateway
      end
    end
  end
end
```

- [ ] **Step 6: Run the spec to confirm it passes**

```bash
bin/rspec spec/requests/api/v1/uploads_spec.rb
```

Expected: 5 examples, 0 failures

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/uploads_controller.rb config/routes.rb spec/requests/api/v1/uploads_spec.rb spec/fixtures/files/test.pdf
git commit -m "Add POST /api/v1/uploads endpoint for template doc file uploads"
```

---

## Task 7: I18n error strings

New error messages needed by the orders controller for template doc validation failures.

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`

- [ ] **Step 1: Add to en.yml**

Under `orders:` → `errors:` in `config/locales/en.yml`, add:

```yaml
      invalid_template_doc: "Invalid template document for this event"
      missing_required_docs: "Missing required document(s): %{docs}"
```

- [ ] **Step 2: Add to ro.yml**

Under `orders:` → `errors:` in `config/locales/ro.yml`, add:

```yaml
      invalid_template_doc: "Document template invalid pentru acest eveniment"
      missing_required_docs: "Documente obligatorii lipsă: %{docs}"
```

- [ ] **Step 3: Commit**

```bash
git add config/locales/en.yml config/locales/ro.yml
git commit -m "Add I18n strings for template doc upload validation errors"
```

---

## Task 8: OrdersController integration

Validate and persist `template_doc_uploads` per attendee.

**Files:**
- Modify: `app/controllers/api/v1/orders_controller.rb`
- Modify: `spec/requests/api/v1/orders_spec.rb`

- [ ] **Step 1: Write the failing specs**

Add the following context block to `spec/requests/api/v1/orders_spec.rb`, after the existing `describe` blocks (before the final `end`):

```ruby
  describe 'template doc uploads' do
    let!(:directus_file) { create(:directus_file) }
    let!(:template_doc) { create(:event_template_doc, event: event) }

    let(:item_with_upload) do
      valid_item.deep_merge(attendee: {
        template_doc_uploads: [
          { event_template_doc_id: template_doc.id, directus_files_id: directus_file.id }
        ]
      })
    end

    it 'creates AttendeeTemplateDocUpload records' do
      post_order([item_with_upload])

      expect(response).to have_http_status(:created)
      expect(AttendeeTemplateDocUpload.count).to eq(1)
      expect(AttendeeTemplateDocUpload.last.event_template_doc).to eq(template_doc)
      expect(AttendeeTemplateDocUpload.last.directus_files_id).to eq(directus_file.id)
    end

    it 'ignores template_doc_uploads when none provided' do
      post_order([valid_item])

      expect(response).to have_http_status(:created)
      expect(AttendeeTemplateDocUpload.count).to eq(0)
    end

    context 'when event_template_doc_id belongs to a different event' do
      let!(:other_event) { create(:event, status: :live) }
      let!(:other_doc) { create(:event_template_doc, event: other_event) }

      it 'returns 400' do
        item = valid_item.deep_merge(attendee: {
          template_doc_uploads: [
            { event_template_doc_id: other_doc.id, directus_files_id: directus_file.id }
          ]
        })
        post_order([item])

        expect(response).to have_http_status(:bad_request)
        expect(json['error']).to be_present
      end
    end

    context 'when a required template doc has no upload' do
      let!(:template_doc) { create(:event_template_doc, event: event, required: true, age_from: nil, age_to: nil) }
      let!(:doc_translation) do
        EventTemplateDocTranslation.create!(
          event_template_doc: template_doc,
          languages_code: language_code,
          label: 'Formular de consimțământ'
        )
      end

      it 'returns 400 and mentions the missing doc label' do
        post_order([valid_item])

        expect(response).to have_http_status(:bad_request)
        expect(json['error']).to include('Formular de consimțământ')
      end
    end

    context 'when a required template doc has an age range' do
      let!(:template_doc) { create(:event_template_doc, event: event, required: true, age_from: 13, age_to: 17) }

      it 'does not require upload for attendee outside the age range' do
        post_order([valid_item.deep_merge(attendee: { age: 25 })])

        expect(response).to have_http_status(:created)
      end

      it 'requires upload for attendee within the age range' do
        post_order([valid_item.deep_merge(attendee: { age: 15 })])

        expect(response).to have_http_status(:bad_request)
      end

      it 'does not require upload when attendee has no age set' do
        post_order([valid_item])

        expect(response).to have_http_status(:created)
      end
    end
  end
```

- [ ] **Step 2: Run the specs to confirm they fail**

```bash
bin/rspec spec/requests/api/v1/orders_spec.rb
```

Expected: the new examples fail (AttendeeTemplateDocUpload not created, no 400 returned for invalid docs).

- [ ] **Step 3: Implement the changes in OrdersController**

Replace the full content of `app/controllers/api/v1/orders_controller.rb` with:

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

            attrs   = attendee_attrs(item[:attendee])
            uploads = parse_template_doc_uploads(item[:attendee])

            valid = validate_template_doc_uploads(event: event, attendee_attrs: attrs, uploads: uploads)
            break unless valid

            result << { event: event, ticket: ticket, attendee_attrs: attrs, template_doc_uploads: uploads }
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

        def validate_template_doc_uploads(event:, attendee_attrs:, uploads:)
          event_doc_ids = event.event_template_docs.map(&:id)

          uploads.each do |upload|
            unless event_doc_ids.include?(upload[:event_template_doc_id])
              render json: { error: t('orders.errors.invalid_template_doc') }, status: :bad_request
              return false
            end
          end

          uploaded_ids   = uploads.map { |u| u[:event_template_doc_id] }
          attendee_age   = attendee_attrs[:age]&.to_i
          missing_labels = []

          event.event_template_docs.each do |doc|
            next unless doc.required
            next unless doc_applies_to_age?(doc, attendee_age)
            next if uploaded_ids.include?(doc.id)

            label = doc.label_for(params[:languages_code]) || doc.id.to_s
            missing_labels << label
          end

          if missing_labels.any?
            render json: { error: t('orders.errors.missing_required_docs', docs: missing_labels.join(', ')) },
                   status: :bad_request
            return false
          end

          true
        end

        def doc_applies_to_age?(doc, attendee_age)
          return true if doc.age_from.nil? && doc.age_to.nil?
          return false if attendee_age.nil?

          (doc.age_from.nil? || attendee_age >= doc.age_from) &&
            (doc.age_to.nil? || attendee_age <= doc.age_to)
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

- [ ] **Step 4: Run all orders specs**

```bash
bin/rspec spec/requests/api/v1/orders_spec.rb
```

Expected: all examples pass (including the original ones — the new logic is additive).

- [ ] **Step 5: Run the full spec suite**

```bash
bin/rspec
```

Expected: 0 failures.

- [ ] **Step 6: Run rubocop**

```bash
bin/rubocop app/controllers/api/v1/orders_controller.rb app/controllers/api/v1/uploads_controller.rb app/services/directus_upload_service.rb app/models/attendee_template_doc_upload.rb
```

Fix any offenses before committing.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/orders_controller.rb spec/requests/api/v1/orders_spec.rb
git commit -m "Extend orders controller to validate and persist template doc uploads"
```

---

## Task 9: Add Directus admin token to credentials

The `DirectusUploadService` reads `Rails.application.credentials.dig(:directus, :admin_token)`. This needs to be set in the encrypted credentials file before the upload endpoint works in any real environment.

**Files:**
- Modify: `config/credentials.yml.enc` (via `rails credentials:edit`)

- [ ] **Step 1: Edit credentials**

```bash
EDITOR=nano bin/rails credentials:edit
```

Add under an existing or new `directus:` key:

```yaml
directus:
  admin_token: <your-directus-admin-static-token>
```

Save and close. Rails will re-encrypt the file automatically.

- [ ] **Step 2: Commit the updated credentials file**

```bash
git add config/credentials.yml.enc
git commit -m "Add Directus admin token to encrypted credentials"
```

---

## Done

At this point:
- `POST /api/v1/uploads` accepts PDF/JPEG/PNG, proxies to Directus, returns a UUID
- `POST /api/v1/:lang/orders` accepts `template_doc_uploads` per attendee, validates them, and creates `AttendeeTemplateDocUpload` records inside the order transaction
- Required docs (with optional age ranges) are enforced with localised error messages
