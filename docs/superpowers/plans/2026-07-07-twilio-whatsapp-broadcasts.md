# Twilio WhatsApp Broadcasts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Admin-only API to send Twilio WhatsApp utility messages (via content template SIDs) to event attendees and/or all users with phone numbers, with per-recipient variable substitution and full broadcast tracking.

**Architecture:** Mirrors the existing email broadcast system — three new DB tables (`whatsapp_templates`, `whatsapp_broadcasts`, `whatsapp_broadcast_recipients`), a `TwilioService` wrapper, a `SendWhatsappJob` Solid Queue job, and two admin controllers. Controller logic is a near-direct port of `Api::V1::Admin::EmailsController`.

**Tech Stack:** Rails 7.1, `twilio-ruby` gem, Solid Queue, PostgreSQL, RSpec.

## Global Constraints

- Rails 7.1 API-only app — no HTML views, no CSRF.
- All admin routes require a valid JWT and `can_send_whatsapp` permission (enforced via the existing `Authenticatable` concern + `require_permission!`).
- `DISABLE_EMAILS=true` env var also disables WhatsApp sending (reused flag).
- Test framework: RSpec. Run specs with `bin/rspec <path>`. No Minitest.
- Run `bin/rubocop -a` after each task to avoid linting failures.
- PostgreSQL-specific SQL (DISTINCT ON, functional indexes) is acceptable — this app runs only on Postgres.
- Factories live in `spec/factories/`. Existing: `:user`, `:event`, `:events_translation`, `:attendee`, `:order`.
- `ROLE_PERMISSIONS` in `app/models/user.rb` must include every key for every role — missing keys cause `nil != true` failures.
- Twilio credentials are stored in Rails encrypted credentials under `twilio: { account_sid:, auth_token:, whatsapp_from: }`. `whatsapp_from` already has the `whatsapp:` prefix (e.g. `whatsapp:+40700000000`).

---

## File Map

| File | Action |
|------|--------|
| `Gemfile` | Add `gem 'twilio-ruby', '~> 7.0'` |
| `app/services/twilio_service.rb` | New — wraps Twilio REST client |
| `spec/services/twilio_service_spec.rb` | New |
| `db/migrate/20260707100000_create_whatsapp_tables.rb` | New — all 3 tables + indexes |
| `app/models/whatsapp_template.rb` | New |
| `app/models/whatsapp_broadcast.rb` | New |
| `app/models/whatsapp_broadcast_recipient.rb` | New |
| `spec/models/whatsapp_template_spec.rb` | New |
| `app/models/user.rb` | Add `can_send_whatsapp` to `ROLE_PERMISSIONS` |
| `config/routes.rb` | Add `whatsapp_templates` + `whatsapp_broadcasts` under `admin` namespace |
| `app/controllers/api/v1/admin/whatsapp_templates_controller.rb` | New |
| `spec/requests/api/v1/admin/whatsapp_templates_spec.rb` | New |
| `app/jobs/send_whatsapp_job.rb` | New |
| `spec/jobs/send_whatsapp_job_spec.rb` | New — stubs `TwilioService` |
| `app/controllers/api/v1/admin/whatsapp_broadcasts_controller.rb` | New |
| `spec/requests/api/v1/admin/whatsapp_broadcasts_spec.rb` | New |
| `spec/factories/whatsapp_templates.rb` | New |
| `spec/factories/whatsapp_broadcasts.rb` | New |

---

## Task 1: `twilio-ruby` gem + `TwilioService`

**Files:**
- Modify: `Gemfile`
- Create: `app/services/twilio_service.rb`
- Create: `spec/services/twilio_service_spec.rb`

**Interfaces:**
- Produces: `TwilioService.send_whatsapp(to: String, content_sid: String, content_variables: Hash) → void`
- `to` is a plain E.164 number (e.g. `+40700123456`); the service adds the `whatsapp:` prefix.
- `content_variables` is a Ruby Hash with string keys and string values: `{"1" => "Ion", "2" => "Fara Regrete"}`.

- [ ] **Step 1: Add the gem**

In `Gemfile`, after the `sendgrid-ruby` line:

```ruby
gem 'twilio-ruby', '~> 7.0'
```

- [ ] **Step 2: Install**

```bash
bundle install
```

Expected: `twilio-ruby` appears in `Gemfile.lock`.

- [ ] **Step 3: Write the failing spec**

Create `spec/services/twilio_service_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe TwilioService do
  let(:twilio_messages) { double('twilio_messages') }
  let(:twilio_client)   { double('twilio_client', messages: twilio_messages) }

  before do
    allow(Twilio::REST::Client).to receive(:new)
      .with('ACtest', 'authtest')
      .and_return(twilio_client)
    allow(twilio_messages).to receive(:create)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :account_sid).and_return('ACtest')
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :auth_token).and_return('authtest')
    allow(Rails.application.credentials).to receive(:dig).with(:twilio, :whatsapp_from).and_return('whatsapp:+14155238886')
  end

  describe '.send_whatsapp' do
    subject(:call) do
      described_class.send_whatsapp(
        to: '+40700123456',
        content_sid: 'HXabc123',
        content_variables: { '1' => 'Ion', '2' => 'Fara Regrete' }
      )
    end

    it 'creates a Twilio message with the correct parameters' do
      call
      expect(twilio_messages).to have_received(:create).with(
        from:              'whatsapp:+14155238886',
        to:                'whatsapp:+40700123456',
        content_sid:       'HXabc123',
        content_variables: '{"1":"Ion","2":"Fara Regrete"}'
      )
    end

    context 'when DISABLE_EMAILS is true' do
      it 'does not call Twilio' do
        with_env('DISABLE_EMAILS', 'true') { call }
        expect(twilio_messages).not_to have_received(:create)
      end
    end

    context 'when Twilio raises a REST error' do
      before do
        allow(twilio_messages).to receive(:create).and_raise(
          Twilio::REST::RestError.new('test error', double(status_code: 400, body: '{}'))
        )
      end

      it 'logs the error and does not re-raise' do
        allow(Rails.logger).to receive(:error)
        expect { call }.not_to raise_error
        expect(Rails.logger).to have_received(:error).with(/TwilioService WhatsApp error/)
      end
    end
  end

  describe '.whatsapp_enabled?' do
    it 'returns true when DISABLE_EMAILS is unset' do
      expect(described_class.whatsapp_enabled?).to be true
    end

    it 'returns false when DISABLE_EMAILS=true' do
      with_env('DISABLE_EMAILS', 'true') do
        expect(described_class.whatsapp_enabled?).to be false
      end
    end
  end
end
```

Add the `with_env` helper to `spec/support/` if it doesn't exist, or use a simpler inline approach in the spec:

```ruby
# In spec/support/helpers.rb (create if absent):
module Helpers
  def with_env(key, value)
    old = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old
  end
end

RSpec.configure { |c| c.include Helpers }
```

- [ ] **Step 4: Run the spec — expect failure**

```bash
bin/rspec spec/services/twilio_service_spec.rb
```

Expected: `NameError: uninitialized constant TwilioService` (or similar load error).

- [ ] **Step 5: Implement `TwilioService`**

Create `app/services/twilio_service.rb`:

```ruby
# frozen_string_literal: true

class TwilioService
  WHATSAPP_PREFIX = 'whatsapp:'

  def self.whatsapp_enabled?
    ENV['DISABLE_EMAILS'].to_s.downcase != 'true'
  end

  def self.send_whatsapp(to:, content_sid:, content_variables:)
    return unless whatsapp_enabled?

    account_sid = Rails.application.credentials.dig(:twilio, :account_sid)
    auth_token  = Rails.application.credentials.dig(:twilio, :auth_token)
    from_number = Rails.application.credentials.dig(:twilio, :whatsapp_from)

    if account_sid.blank? || auth_token.blank? || from_number.blank?
      Rails.logger.error('TwilioService: missing credentials — skipping send')
      return
    end

    client = Twilio::REST::Client.new(account_sid, auth_token)
    client.messages.create(
      from:              from_number,
      to:                "#{WHATSAPP_PREFIX}#{to}",
      content_sid:       content_sid,
      content_variables: content_variables.to_json
    )
  rescue Twilio::REST::RestError => e
    Rails.logger.error("TwilioService WhatsApp error: #{e.message}")
  end
end
```

- [ ] **Step 6: Run the spec — expect pass**

```bash
bin/rspec spec/services/twilio_service_spec.rb
```

Expected: All examples pass. If the `DISABLE_EMAILS` context test fails due to missing `with_env`, ensure the support helper is included in `rails_helper.rb`:

```ruby
# spec/rails_helper.rb — add inside the RSpec.configure block or near the Dir.glob line:
Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }
```

- [ ] **Step 7: Rubocop + commit**

```bash
bin/rubocop -a app/services/twilio_service.rb
git add Gemfile Gemfile.lock app/services/twilio_service.rb spec/services/twilio_service_spec.rb spec/support/helpers.rb
git commit -m "feat: add TwilioService for WhatsApp sends"
```

---

## Task 2: Migration + Models + Permission + Routes

**Files:**
- Create: `db/migrate/20260707100000_create_whatsapp_tables.rb`
- Create: `app/models/whatsapp_template.rb`
- Create: `app/models/whatsapp_broadcast.rb`
- Create: `app/models/whatsapp_broadcast_recipient.rb`
- Create: `spec/models/whatsapp_template_spec.rb`
- Create: `spec/factories/whatsapp_templates.rb`
- Create: `spec/factories/whatsapp_broadcasts.rb`
- Modify: `app/models/user.rb` — add `can_send_whatsapp` to every role in `ROLE_PERMISSIONS`
- Modify: `config/routes.rb` — add two new admin resources

**Interfaces:**
- Produces:
  - `WhatsappTemplate` model with `name`, `content_sid`, `variables` (jsonb array)
  - `WhatsappBroadcast` model with `whatsapp_template_id`, `event_id`, `sent_by_user_id`, `recipient_count`
  - `WhatsappBroadcastRecipient` model (no primary key) with `whatsapp_broadcast_id`, `user_id`, `phone_number`
  - `User#can?(:can_send_whatsapp)` returns `true` for admin, `false` for all others
  - Routes: `GET/POST /api/v1/admin/whatsapp_templates`, `GET/POST /api/v1/admin/whatsapp_broadcasts`

- [ ] **Step 1: Write failing model spec**

Create `spec/models/whatsapp_template_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WhatsappTemplate, type: :model do
  it 'is valid with name and content_sid' do
    expect(build(:whatsapp_template)).to be_valid
  end

  it 'is invalid without name' do
    expect(build(:whatsapp_template, name: nil)).not_to be_valid
  end

  it 'is invalid without content_sid' do
    expect(build(:whatsapp_template, content_sid: nil)).not_to be_valid
  end

  it 'defaults variables to an empty array' do
    t = create(:whatsapp_template, variables: nil)
    expect(t.reload.variables).to eq([])
  end
end
```

Create `spec/factories/whatsapp_templates.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :whatsapp_template do
    name        { 'Event Reminder' }
    content_sid { 'HXabc1234567890' }
    variables   { [{ 'position' => 1, 'name' => 'first_name' }, { 'position' => 2, 'name' => 'event_name' }] }
  end
end
```

Create `spec/factories/whatsapp_broadcasts.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :whatsapp_broadcast do
    association :whatsapp_template
    association :sent_by_user, factory: :user, role: 'admin'
    recipient_count { 0 }
  end
end
```

- [ ] **Step 2: Run spec — expect failure**

```bash
bin/rspec spec/models/whatsapp_template_spec.rb
```

Expected: `NameError: uninitialized constant WhatsappTemplate`.

- [ ] **Step 3: Create the migration**

Create `db/migrate/20260707100000_create_whatsapp_tables.rb`:

```ruby
# frozen_string_literal: true

class CreateWhatsappTables < ActiveRecord::Migration[7.1]
  def change
    create_table :whatsapp_templates do |t|
      t.string :name,        null: false
      t.string :content_sid, null: false
      t.jsonb  :variables,   null: false, default: []
      t.timestamps
    end

    create_table :whatsapp_broadcasts do |t|
      t.bigint  :whatsapp_template_id, null: false
      t.bigint  :event_id
      t.bigint  :sent_by_user_id,      null: false
      t.integer :recipient_count,      null: false, default: 0
      t.timestamps
    end

    add_index :whatsapp_broadcasts, :whatsapp_template_id
    add_index :whatsapp_broadcasts, :event_id
    add_index :whatsapp_broadcasts, :sent_by_user_id

    create_table :whatsapp_broadcast_recipients, id: false do |t|
      t.bigint :whatsapp_broadcast_id, null: false
      t.bigint :user_id
      t.string :phone_number, null: false
    end

    execute <<~SQL
      CREATE UNIQUE INDEX idx_whatsapp_broadcast_recipients_broadcast_phone
        ON whatsapp_broadcast_recipients (whatsapp_broadcast_id, LOWER(phone_number))
    SQL

    add_index :whatsapp_broadcast_recipients, :user_id,
              where: 'user_id IS NOT NULL',
              name: 'idx_whatsapp_broadcast_recipients_user_id'
  end
end
```

- [ ] **Step 4: Run the migration on dev and production**

```bash
bin/rails db:migrate
```

Also run on the production database (port 5433):

```bash
DATABASE_PORT=5433 DATABASE_PASSWORD=cTeventsPostgres2024! bin/rails db:migrate
```

Expected: Migration status shows `up` for `20260707100000`.

- [ ] **Step 5: Create the models**

Create `app/models/whatsapp_template.rb`:

```ruby
# frozen_string_literal: true

class WhatsappTemplate < ApplicationRecord
  validates :name,        presence: true
  validates :content_sid, presence: true
end
```

Create `app/models/whatsapp_broadcast.rb`:

```ruby
# frozen_string_literal: true

class WhatsappBroadcast < ApplicationRecord
  belongs_to :whatsapp_template
  belongs_to :event, optional: true
  belongs_to :sent_by_user, class_name: 'User', foreign_key: :sent_by_user_id

  has_many :whatsapp_broadcast_recipients, dependent: :delete_all
end
```

Create `app/models/whatsapp_broadcast_recipient.rb`:

```ruby
# frozen_string_literal: true

class WhatsappBroadcastRecipient < ApplicationRecord
  self.primary_key = nil

  belongs_to :whatsapp_broadcast
  belongs_to :user, optional: true
end
```

- [ ] **Step 6: Run model spec — expect pass**

```bash
bin/rspec spec/models/whatsapp_template_spec.rb
```

Expected: All 4 examples pass.

- [ ] **Step 7: Add `can_send_whatsapp` to `User::ROLE_PERMISSIONS`**

In `app/models/user.rb`, replace the entire `ROLE_PERMISSIONS` constant with:

```ruby
ROLE_PERMISSIONS = {
  'admin' => { can_check_in_attendees: true, can_scan_food_stamp: true, can_send_push_notifications: true,
               can_manage_bracelets: true, can_send_emails: true, can_send_whatsapp: true }.freeze,
  'volunteer' => { can_check_in_attendees: true, can_scan_food_stamp: true, can_send_push_notifications: false,
                   can_manage_bracelets: false, can_send_emails: false, can_send_whatsapp: false }.freeze,
  'attendee' => { can_check_in_attendees: false, can_scan_food_stamp: false, can_send_push_notifications: false,
                  can_manage_bracelets: false, can_send_emails: false, can_send_whatsapp: false }.freeze,
  'leader' => { can_check_in_attendees: false, can_scan_food_stamp: false, can_send_push_notifications: false,
                can_manage_bracelets: false, can_send_emails: false, can_send_whatsapp: false }.freeze,
  'staff' => { can_check_in_attendees: false, can_scan_food_stamp: false, can_send_push_notifications: false,
               can_manage_bracelets: false, can_send_emails: false, can_send_whatsapp: false }.freeze
}.freeze
```

- [ ] **Step 8: Add routes**

In `config/routes.rb`, inside the `namespace :admin` block, after the `resources :emails` entry:

```ruby
resources :whatsapp_templates,  only: %i[index create]
resources :whatsapp_broadcasts, only: %i[index create]
```

The block should look like:

```ruby
namespace :admin do
  resources :push_notifications, only: :create
  resources :emails, only: %i[index create] do
    collection { get :variables }
  end
  resources :whatsapp_templates,  only: %i[index create]
  resources :whatsapp_broadcasts, only: %i[index create]
  # ...rest of admin routes
end
```

- [ ] **Step 9: Verify routes**

```bash
bin/rails routes | grep whatsapp
```

Expected output includes:
```
api_v1_admin_whatsapp_templates GET  /api/v1/admin/whatsapp_templates(.:format)
                                POST /api/v1/admin/whatsapp_templates(.:format)
api_v1_admin_whatsapp_broadcasts GET  /api/v1/admin/whatsapp_broadcasts(.:format)
                                 POST /api/v1/admin/whatsapp_broadcasts(.:format)
```

- [ ] **Step 10: Rubocop + commit**

```bash
bin/rubocop -a app/models/whatsapp_template.rb app/models/whatsapp_broadcast.rb app/models/whatsapp_broadcast_recipient.rb app/models/user.rb config/routes.rb
git add db/migrate/20260707100000_create_whatsapp_tables.rb app/models/whatsapp_template.rb app/models/whatsapp_broadcast.rb app/models/whatsapp_broadcast_recipient.rb app/models/user.rb config/routes.rb spec/models/whatsapp_template_spec.rb spec/factories/whatsapp_templates.rb spec/factories/whatsapp_broadcasts.rb
git commit -m "feat: add WhatsApp tables, models, permission, routes"
```

---

## Task 3: `WhatsappTemplatesController`

**Files:**
- Create: `app/controllers/api/v1/admin/whatsapp_templates_controller.rb`
- Create: `spec/requests/api/v1/admin/whatsapp_templates_spec.rb`

**Interfaces:**
- Consumes: `WhatsappTemplate` model (Task 2), `Authenticatable` concern, `:can_send_whatsapp` permission.
- Produces:
  - `GET /api/v1/admin/whatsapp_templates` → `[{id, name, content_sid, variables, created_at}]`
  - `POST /api/v1/admin/whatsapp_templates` → `{id, name, content_sid, variables, created_at}` (201) or `{error}` (422)

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/api/v1/admin/whatsapp_templates_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin WhatsApp Templates' do
  let(:admin)   { create(:user, role: 'admin') }
  let(:token)   { JwtService.encode(admin.id) }
  let(:headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } }

  describe 'GET /api/v1/admin/whatsapp_templates' do
    before { create_list(:whatsapp_template, 2) }

    it 'returns all templates' do
      get '/api/v1/admin/whatsapp_templates', headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).size).to eq(2)
    end

    it 'returns id, name, content_sid, variables, created_at' do
      get '/api/v1/admin/whatsapp_templates', headers: headers
      parsed = JSON.parse(response.body).first
      expect(parsed.keys).to include('id', 'name', 'content_sid', 'variables', 'created_at')
    end

    context 'with a non-admin JWT' do
      let(:token) { JwtService.encode(create(:user, role: 'attendee').id) }

      it 'returns 403' do
        get '/api/v1/admin/whatsapp_templates', headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end

    context 'without a JWT' do
      it 'returns 401' do
        get '/api/v1/admin/whatsapp_templates', headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/admin/whatsapp_templates' do
    let(:valid_params) do
      {
        name:        'Event Reminder',
        content_sid: 'HXabc123',
        variables:   [{ position: 1, name: 'first_name' }, { position: 2, name: 'event_name' }]
      }
    end

    it 'creates a template and returns 201' do
      expect do
        post '/api/v1/admin/whatsapp_templates', params: valid_params.to_json, headers: headers
      end.to change(WhatsappTemplate, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed['name']).to eq('Event Reminder')
      expect(parsed['content_sid']).to eq('HXabc123')
      expect(parsed['variables'].first['name']).to eq('first_name')
    end

    it 'returns 422 when name is missing' do
      post '/api/v1/admin/whatsapp_templates',
           params: valid_params.merge(name: nil).to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 when content_sid is missing' do
      post '/api/v1/admin/whatsapp_templates',
           params: valid_params.merge(content_sid: nil).to_json,
           headers: headers
      expect(response).to have_http_status(:unprocessable_content)
    end

    context 'with a non-admin JWT' do
      let(:token) { JwtService.encode(create(:user, role: 'attendee').id) }

      it 'returns 403' do
        post '/api/v1/admin/whatsapp_templates', params: valid_params.to_json, headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec — expect failure**

```bash
bin/rspec spec/requests/api/v1/admin/whatsapp_templates_spec.rb
```

Expected: Routing error — `ActionController::RoutingError`.

- [ ] **Step 3: Implement the controller**

Create `app/controllers/api/v1/admin/whatsapp_templates_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Admin
      class WhatsappTemplatesController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_send_whatsapp) }

        def index
          templates = WhatsappTemplate.order(created_at: :desc)
          render json: templates.map { |t| template_json(t) }
        end

        def create
          variables = parse_variables(params[:variables])

          template = WhatsappTemplate.new(
            name:        params[:name].presence,
            content_sid: params[:content_sid].presence,
            variables:   variables
          )

          if template.save
            render json: template_json(template), status: :created
          else
            render json: { error: template.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        private

          def parse_variables(raw)
            Array(raw).map do |v|
              v.respond_to?(:to_unsafe_h) ? v.to_unsafe_h.slice('position', 'name') : v.slice('position', 'name')
            end
          end

          def template_json(t)
            {
              id:          t.id,
              name:        t.name,
              content_sid: t.content_sid,
              variables:   t.variables,
              created_at:  t.created_at
            }
          end
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec — expect pass**

```bash
bin/rspec spec/requests/api/v1/admin/whatsapp_templates_spec.rb
```

Expected: All examples pass.

- [ ] **Step 5: Rubocop + commit**

```bash
bin/rubocop -a app/controllers/api/v1/admin/whatsapp_templates_controller.rb
git add app/controllers/api/v1/admin/whatsapp_templates_controller.rb spec/requests/api/v1/admin/whatsapp_templates_spec.rb
git commit -m "feat: add WhatsApp templates admin endpoint"
```

---

## Task 4: `SendWhatsappJob`

**Files:**
- Create: `app/jobs/send_whatsapp_job.rb`
- Create: `spec/jobs/send_whatsapp_job_spec.rb`

**Interfaces:**
- Consumes: `TwilioService.send_whatsapp` (Task 1), `WhatsappTemplate` (Task 2), `WhatsappBroadcast` (Task 2), `WhatsappBroadcastRecipient` (Task 2), `User`, `Attendee`, `Event`, `Order`.
- Produces: `SendWhatsappJob.perform_later(template_id:, user_ids:, broadcast_id:, event_id: nil, exclude_broadcast_ids: nil)`

Variable resolution logic:
- `variables` on the template is an array of `{"position" => N, "name" => "field_key"}`.
- `content_variables` sent to Twilio is `{"1" => "Ion", "2" => "Fara Regrete"}` — position (as string) → resolved value.
- Field keys: `first_name`, `last_name`, `email`, `phone_number`, `event_name`, `order_reference`.
- Unregistered attendees always use Romanian context (no language field).

- [ ] **Step 1: Create spec directory**

```bash
mkdir -p spec/jobs
```

- [ ] **Step 2: Write the failing spec**

Create `spec/jobs/send_whatsapp_job_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendWhatsappJob, type: :job do
  let(:event)    { create(:event) }
  let!(:trans)   { create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Fara Regrete') }
  let(:order)    { create(:order) }
  let(:user)     { create(:user, first_name: 'Ion', last_name: 'Pop', phone_number: '+40700111222') }
  let!(:attendee) do
    create(:attendee, event: event, user: user, order: order,
                      first_name: 'Ion', last_name: 'Pop',
                      email_address: user.email, phone_number: user.phone_number,
                      payment_status: :paid)
  end

  let(:template) do
    create(:whatsapp_template,
           content_sid: 'HXtest',
           variables: [{ 'position' => 1, 'name' => 'first_name' },
                       { 'position' => 2, 'name' => 'event_name' }])
  end

  let(:broadcast) { create(:whatsapp_broadcast, whatsapp_template: template, event: event) }

  before { allow(TwilioService).to receive(:send_whatsapp) }

  def perform(extra = {})
    described_class.new.perform(
      template_id: template.id, user_ids: [user.id], broadcast_id: broadcast.id,
      event_id: event.id, **extra
    )
  end

  it 'calls TwilioService with correct content_variables' do
    perform
    expect(TwilioService).to have_received(:send_whatsapp).with(
      to:                user.phone_number,
      content_sid:       'HXtest',
      content_variables: { '1' => 'Ion', '2' => 'Fara Regrete' }
    )
  end

  it 'records recipients in whatsapp_broadcast_recipients' do
    expect { perform }.to change(WhatsappBroadcastRecipient, :count).by(1)
  end

  it 'updates recipient_count on the broadcast' do
    perform
    expect(broadcast.reload.recipient_count).to eq(1)
  end

  context 'when exclude_broadcast_ids is given' do
    let!(:prior_broadcast) { create(:whatsapp_broadcast, whatsapp_template: template) }

    before do
      WhatsappBroadcastRecipient.insert_all(
        [{ whatsapp_broadcast_id: prior_broadcast.id, user_id: user.id, phone_number: user.phone_number.downcase }]
      )
    end

    it 'skips users whose phone was already sent' do
      perform(exclude_broadcast_ids: [prior_broadcast.id])
      expect(TwilioService).not_to have_received(:send_whatsapp)
    end
  end

  context 'with unregistered attendees (no user account)' do
    let(:unregistered) do
      create(:attendee, event: event, user: nil, order: order,
                        first_name: 'Ana', last_name: 'Ionescu',
                        email_address: 'ana@example.com',
                        phone_number: '+40700999888',
                        payment_status: :paid)
    end

    before { unregistered }

    it 'sends to unregistered attendees' do
      perform(user_ids: [])
      expect(TwilioService).to have_received(:send_whatsapp).with(
        hash_including(to: '+40700999888')
      )
    end
  end

  context 'when user has no phone_number' do
    before { user.update!(phone_number: nil) }

    it 'skips that user' do
      perform
      expect(TwilioService).not_to have_received(:send_whatsapp)
    end
  end
end
```

- [ ] **Step 3: Run the spec — expect failure**

```bash
bin/rspec spec/jobs/send_whatsapp_job_spec.rb
```

Expected: `NameError: uninitialized constant SendWhatsappJob`.

- [ ] **Step 4: Implement `SendWhatsappJob`**

Create `app/jobs/send_whatsapp_job.rb`:

```ruby
# frozen_string_literal: true

class SendWhatsappJob < ApplicationJob
  queue_as :default

  def perform(template_id:, user_ids:, broadcast_id:, event_id: nil, exclude_broadcast_ids: nil)
    template = WhatsappTemplate.find_by(id: template_id)
    unless template
      Rails.logger.error("SendWhatsappJob: WhatsappTemplate #{template_id} not found")
      return
    end

    event      = event_id ? Event.includes(:events_translations).find_by(id: event_id) : nil
    event_name = event&.events_translations&.find { |t| t.languages_code == 'ro-RO' }&.name.to_s

    order_refs      = batch_order_refs(user_ids, event_id)
    excluded_phones = previously_sent_phones(exclude_broadcast_ids)
    sent_recipients = []

    User.where(id: user_ids).where.not(phone_number: [nil, '']).find_each do |user|
      next if excluded_phones.include?(user.phone_number.downcase)

      vars = build_vars(user.first_name.to_s, user.last_name.to_s, user.email.to_s,
                        user.phone_number.to_s, event_name, order_refs[user.id].to_s)
      content_variables = resolve_content_variables(template.variables, vars)

      TwilioService.send_whatsapp(
        to:                user.phone_number,
        content_sid:       template.content_sid,
        content_variables: content_variables
      )

      sent_recipients << { user_id: user.id, phone_number: user.phone_number.downcase }
    end

    unregistered = event_id.present? ? send_to_unregistered_attendees(
      template, event_name, event_id,
      sent_recipients.map { |r| r[:phone_number] }.to_set | excluded_phones
    ) : []

    record_recipients(broadcast_id, sent_recipients, unregistered)
  end

  private

    def previously_sent_phones(broadcast_ids)
      return Set.new if broadcast_ids.blank?

      WhatsappBroadcastRecipient.where(whatsapp_broadcast_id: Array(broadcast_ids))
                                .pluck(:phone_number)
                                .map(&:downcase)
                                .to_set
    end

    def send_to_unregistered_attendees(template, event_name, event_id, skip_phones)
      recipients = []

      Attendee.joins(:order)
              .where(event_id: event_id, user_id: nil)
              .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
              .where.not(phone_number: [nil, ''])
              .select('DISTINCT ON (LOWER(attendees.phone_number)) attendees.*, orders.order_reference AS order_ref')
              .order(Arel.sql('LOWER(attendees.phone_number), attendees.id'))
              .each do |attendee|
        next if skip_phones.include?(attendee.phone_number.downcase)

        vars = build_vars(attendee.first_name.to_s, attendee.last_name.to_s,
                          attendee.email_address.to_s, attendee.phone_number.to_s,
                          event_name, attendee.order_ref.to_s)
        content_variables = resolve_content_variables(template.variables, vars)

        TwilioService.send_whatsapp(
          to:                attendee.phone_number,
          content_sid:       template.content_sid,
          content_variables: content_variables
        )

        recipients << { user_id: nil, phone_number: attendee.phone_number.downcase }
      end

      recipients
    end

    def build_vars(first_name, last_name, email, phone_number, event_name, order_reference)
      {
        'first_name'      => first_name,
        'last_name'       => last_name,
        'email'           => email,
        'phone_number'    => phone_number,
        'event_name'      => event_name,
        'order_reference' => order_reference
      }
    end

    def resolve_content_variables(variable_definitions, vars)
      variable_definitions.each_with_object({}) do |vd, h|
        h[vd['position'].to_s] = vars.fetch(vd['name'].to_s, '')
      end
    end

    def record_recipients(broadcast_id, registered, unregistered)
      all = registered + unregistered
      return if all.empty?

      rows = all.map { |r| r.merge(whatsapp_broadcast_id: broadcast_id) }
      WhatsappBroadcastRecipient.insert_all(
        rows,
        unique_by: :idx_whatsapp_broadcast_recipients_broadcast_phone
      )
      WhatsappBroadcast.where(id: broadcast_id).update_all(recipient_count: all.size)
    end

    def batch_order_refs(user_ids, event_id)
      return {} unless event_id

      Attendee
        .joins(:order)
        .where(event_id: event_id, user_id: user_ids)
        .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
        .select('DISTINCT ON (attendees.user_id) attendees.user_id, orders.order_reference')
        .order('attendees.user_id')
        .each_with_object({}) { |a, h| h[a.user_id] = a.order_reference }
    end
end
```

- [ ] **Step 5: Run the spec — expect pass**

```bash
bin/rspec spec/jobs/send_whatsapp_job_spec.rb
```

Expected: All examples pass.

- [ ] **Step 6: Rubocop + commit**

```bash
bin/rubocop -a app/jobs/send_whatsapp_job.rb
git add app/jobs/send_whatsapp_job.rb spec/jobs/send_whatsapp_job_spec.rb
git commit -m "feat: add SendWhatsappJob for bulk WhatsApp sends"
```

---

## Task 5: `WhatsappBroadcastsController`

**Files:**
- Create: `app/controllers/api/v1/admin/whatsapp_broadcasts_controller.rb`
- Create: `spec/requests/api/v1/admin/whatsapp_broadcasts_spec.rb`

**Interfaces:**
- Consumes: `WhatsappTemplate`, `WhatsappBroadcast`, `WhatsappBroadcastRecipient`, `TwilioService`, `SendWhatsappJob`, `User`, `Attendee`, `Authenticatable`.
- Produces:
  - `GET /api/v1/admin/whatsapp_broadcasts` → `[{id, template_id, template_name, event_id, event_name, recipient_count, sent_at}]`
  - `POST /api/v1/admin/whatsapp_broadcasts` with `to:` → `{sent_to: 1}` (test send, no DB record)
  - `POST /api/v1/admin/whatsapp_broadcasts` without `to:` → `{broadcast_id:, queued_for:}` (bulk send)

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/api/v1/admin/whatsapp_broadcasts_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin WhatsApp Broadcasts' do
  let(:admin)    { create(:user, role: 'admin', phone_number: '+40700111000') }
  let(:token)    { JwtService.encode(admin.id) }
  let(:headers)  { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" } }
  let(:template) { create(:whatsapp_template) }

  before { allow(TwilioService).to receive(:send_whatsapp) }

  describe 'GET /api/v1/admin/whatsapp_broadcasts' do
    before { create(:whatsapp_broadcast, whatsapp_template: template, sent_by_user: admin, recipient_count: 5) }

    it 'returns last 50 broadcasts' do
      get '/api/v1/admin/whatsapp_broadcasts', headers: headers
      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed.size).to eq(1)
      expect(parsed.first.keys).to include('id', 'template_id', 'template_name', 'event_id', 'recipient_count', 'sent_at')
    end

    context 'without JWT' do
      it 'returns 401' do
        get '/api/v1/admin/whatsapp_broadcasts', headers: { 'Content-Type' => 'application/json' }
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/admin/whatsapp_broadcasts' do
    context 'test send (to: present)' do
      it 'calls TwilioService and returns sent_to: 1 without creating a broadcast' do
        expect do
          post '/api/v1/admin/whatsapp_broadcasts',
               params: {
                 template_id: template.id,
                 to: '+40700999888',
                 variables: { 'first_name' => 'Ion', 'event_name' => 'Fara Regrete' }
               }.to_json,
               headers: headers
        end.not_to change(WhatsappBroadcast, :count)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)).to eq('sent_to' => 1)
        expect(TwilioService).to have_received(:send_whatsapp).with(
          hash_including(to: '+40700999888', content_sid: template.content_sid)
        )
      end
    end

    context 'bulk send (no to:)' do
      let(:user_with_phone) { create(:user, phone_number: '+40700111222') }
      let(:event)           { create(:event) }

      before do
        create(:attendee, event: event, user: user_with_phone, payment_status: :paid)
      end

      it 'creates a broadcast and enqueues the job' do
        expect do
          post '/api/v1/admin/whatsapp_broadcasts',
               params: { template_id: template.id, event_id: event.id }.to_json,
               headers: headers
        end.to have_enqueued_job(SendWhatsappJob)
           .and change(WhatsappBroadcast, :count).by(1)

        expect(response).to have_http_status(:ok)
        parsed = JSON.parse(response.body)
        expect(parsed['broadcast_id']).to be_present
        expect(parsed['queued_for']).to be >= 1
      end

      it 'returns 404 when template not found' do
        post '/api/v1/admin/whatsapp_broadcasts',
             params: { template_id: 999_999 }.to_json,
             headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'with a non-admin JWT' do
      let(:token) { JwtService.encode(create(:user, role: 'attendee').id) }

      it 'returns 403' do
        post '/api/v1/admin/whatsapp_broadcasts',
             params: { template_id: template.id, to: '+40700000000' }.to_json,
             headers: headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec — expect failure**

```bash
bin/rspec spec/requests/api/v1/admin/whatsapp_broadcasts_spec.rb
```

Expected: Routing error or `NameError`.

- [ ] **Step 3: Implement the controller**

Create `app/controllers/api/v1/admin/whatsapp_broadcasts_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Admin
      class WhatsappBroadcastsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action { require_permission!(:can_send_whatsapp) }

        def index
          broadcasts = WhatsappBroadcast.includes(:whatsapp_template, :event)
                                        .order(created_at: :desc)
                                        .limit(50)
          render json: broadcasts.map { |b| broadcast_json(b) }
        end

        def create
          template = WhatsappTemplate.find_by(id: params[:template_id])
          return render json: { error: 'Template not found' }, status: :not_found unless template

          if params[:to].present?
            variables = (params[:variables].respond_to?(:to_unsafe_h) ? params[:variables].to_unsafe_h : {})
                          .stringify_keys
            content_variables = resolve_content_variables(template.variables, variables)
            TwilioService.send_whatsapp(
              to:                params[:to],
              content_sid:       template.content_sid,
              content_variables: content_variables
            )
            return render json: { sent_to: 1 }, status: :ok
          end

          user_ids           = resolve_user_ids
          unregistered_count = unregistered_attendee_count

          broadcast = WhatsappBroadcast.create!(
            whatsapp_template_id: template.id,
            event_id:             params[:event_id].presence,
            sent_by_user_id:      current_user.id,
            recipient_count:      0
          )

          SendWhatsappJob.perform_later(
            template_id:           template.id,
            user_ids:              user_ids,
            broadcast_id:          broadcast.id,
            event_id:              params[:event_id].presence,
            exclude_broadcast_ids: Array(params[:exclude_broadcast_ids]).presence
          )

          render json: { broadcast_id: broadcast.id, queued_for: user_ids.size + unregistered_count }, status: :ok
        end

        private

          def resolve_content_variables(variable_definitions, vars)
            variable_definitions.each_with_object({}) do |vd, h|
              h[vd['position'].to_s] = vars.fetch(vd['name'].to_s, '')
            end
          end

          def resolve_user_ids
            scope = User.active.where.not(phone_number: [nil, ''])

            if params[:event_id].present?
              scope = scope.joins(:attendees)
                           .where(attendees: { event_id: params[:event_id] })
                           .where.not(attendees: { payment_status: Attendee.payment_statuses[:attendee_cancelled] })
                           .distinct
            end

            if params[:exclude_broadcast_ids].present?
              already_sent_phones = WhatsappBroadcastRecipient
                                      .where(whatsapp_broadcast_id: Array(params[:exclude_broadcast_ids]))
                                      .pluck(:phone_number)
                                      .map(&:downcase)
              scope = scope.where.not("LOWER(users.phone_number) IN (?)", already_sent_phones) if already_sent_phones.any?
            end

            scope.pluck(:id)
          end

          def unregistered_attendee_count
            return 0 if params[:event_id].blank?

            Attendee.where(event_id: params[:event_id], user_id: nil)
                    .where.not(payment_status: Attendee.payment_statuses[:attendee_cancelled])
                    .where.not(phone_number: [nil, ''])
                    .select(:phone_number)
                    .distinct
                    .count
          end

          def broadcast_json(broadcast)
            event_name = broadcast.event&.events_translations
                                  &.find { |t| t.languages_code == 'ro-RO' }
                                  &.name

            {
              id:              broadcast.id,
              template_id:     broadcast.whatsapp_template_id,
              template_name:   broadcast.whatsapp_template&.name,
              event_id:        broadcast.event_id,
              event_name:      event_name,
              recipient_count: broadcast.recipient_count,
              sent_at:         broadcast.created_at
            }
          end
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec — expect pass**

```bash
bin/rspec spec/requests/api/v1/admin/whatsapp_broadcasts_spec.rb
```

Expected: All examples pass.

- [ ] **Step 5: Run the full suite**

```bash
bin/rspec
```

Expected: No regressions. All previously passing specs still pass.

- [ ] **Step 6: Rubocop + commit**

```bash
bin/rubocop -a app/controllers/api/v1/admin/whatsapp_broadcasts_controller.rb
git add app/controllers/api/v1/admin/whatsapp_broadcasts_controller.rb spec/requests/api/v1/admin/whatsapp_broadcasts_spec.rb
git commit -m "feat: add WhatsApp broadcasts admin endpoint"
```

---

## Post-Implementation Checklist

- [ ] Add Twilio credentials to Rails encrypted credentials on both dev and production:
  ```bash
  bin/rails credentials:edit
  # Add under twilio:
  #   account_sid: ACxxx
  #   auth_token: xxx
  #   whatsapp_from: "whatsapp:+40700000000"
  ```
- [ ] Run migrations on production (port 5433) if not done in Task 2.
- [ ] Confirm `bin/rspec` passes clean with no failures.
