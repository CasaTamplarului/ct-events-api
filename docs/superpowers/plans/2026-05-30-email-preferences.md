# Email Preferences Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-category email preference toggles to User, with a PATCH settings endpoint, a public token-based unsubscribe endpoint, and marketing consent captured at signup.

**Architecture:** Five boolean columns on `users` (all default false) store preferences. A new `EmailUnsubscribeTokenService` generates and verifies signed tokens using `Rails.application.message_verifier`. Two new controllers handle settings updates and unsubscribe link clicks. All nine existing `user_json` methods are extended to include the preferences object.

**Tech Stack:** Rails 7.1, ActiveSupport MessageVerifier (no new gems), existing SendGrid service pattern.

---

## File Map

**New files:**
- `db/migrate/20260530120001_add_email_preferences_to_users.rb`
- `app/services/email_unsubscribe_token_service.rb`
- `app/controllers/api/v1/auth/me/email_preferences_controller.rb`
- `app/controllers/api/v1/unsubscribe_controller.rb`
- `spec/services/email_unsubscribe_token_service_spec.rb`
- `spec/requests/api/v1/auth/me/email_preferences_spec.rb`
- `spec/requests/api/v1/unsubscribe_spec.rb`

**Modified files:**
- `config/routes.rb` — add email_preferences member resource + unsubscribe route
- `app/controllers/api/v1/auth/me_controller.rb:66` — add `email_preferences` to `user_json`
- `app/controllers/api/v1/auth/registrations_controller.rb:34,66` — accept `marketing_emails` param + add to `user_json`
- `app/controllers/api/v1/auth/sessions_controller.rb:32` — add `email_preferences` to `user_json`
- `app/controllers/api/v1/auth/googles_controller.rb:66` — add `email_preferences` to `user_json`
- `app/controllers/api/v1/auth/facebooks_controller.rb:70` — add `email_preferences` to `user_json`
- `app/controllers/api/v1/auth/apples_controller.rb:69` — add `email_preferences` to `user_json`
- `app/controllers/api/v1/auth/microsofts_controller.rb:66` — add `email_preferences` to `user_json`
- `app/controllers/api/v1/auth/passkeys_controller.rb:143` — add `email_preferences` to `user_json`
- `app/controllers/api/v1/auth/passwords_controller.rb:61` — add `email_preferences` to `user_json`
- `spec/models/user_spec.rb` — extend with preference defaults
- `spec/requests/api/v1/auth/me_spec.rb` — extend GET /me test
- `spec/requests/api/v1/auth/registrations_spec.rb` — extend with marketing_emails tests

---

## Task 1: Migration — add email preference columns

**Files:**
- Create: `db/migrate/20260530120001_add_email_preferences_to_users.rb`
- Modify: `spec/models/user_spec.rb`

- [ ] **Step 1: Write the failing test**

Add this block to `spec/models/user_spec.rb` inside the top-level `RSpec.describe User` block:

```ruby
describe 'email preferences' do
  it 'defaults all preference columns to false' do
    user = create(:user)
    expect(user.marketing_emails).to be false
    expect(user.payment_reminder_emails).to be false
    expect(user.payment_receipt_emails).to be false
    expect(user.event_reminder_emails).to be false
    expect(user.event_update_emails).to be false
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rspec spec/models/user_spec.rb --format documentation
```

Expected: FAIL with `NoMethodError: undefined method 'marketing_emails'`

- [ ] **Step 3: Create the migration**

```bash
bin/rails generate migration AddEmailPreferencesToUsers
```

Replace the generated migration body with:

```ruby
# frozen_string_literal: true

class AddEmailPreferencesToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :marketing_emails,         :boolean, null: false, default: false
    add_column :users, :payment_reminder_emails,  :boolean, null: false, default: false
    add_column :users, :payment_receipt_emails,   :boolean, null: false, default: false
    add_column :users, :event_reminder_emails,    :boolean, null: false, default: false
    add_column :users, :event_update_emails,      :boolean, null: false, default: false
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs cleanly, schema.rb updated with all 5 columns.

- [ ] **Step 5: Run the test to verify it passes**

```bash
bin/rspec spec/models/user_spec.rb --format documentation
```

Expected: all tests PASS including the new `defaults all preference columns to false`.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/20260530120001_add_email_preferences_to_users.rb db/schema.rb spec/models/user_spec.rb
git commit -m "Add email preference boolean columns to users"
```

---

## Task 2: EmailUnsubscribeTokenService

**Files:**
- Create: `app/services/email_unsubscribe_token_service.rb`
- Create: `spec/services/email_unsubscribe_token_service_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/services/email_unsubscribe_token_service_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe EmailUnsubscribeTokenService do
  let(:user) { create(:user) }

  describe '.generate' do
    it 'returns a non-empty string token for a known type' do
      token = described_class.generate(user: user, type: 'marketing_emails')
      expect(token).to be_a(String).and be_present
    end

    it 'raises ArgumentError for an unknown type' do
      expect { described_class.generate(user: user, type: 'bad_type') }
        .to raise_error(ArgumentError, /Unknown preference type/)
    end
  end

  describe '.verify' do
    described_class::PREFERENCE_COLUMNS.each do |col|
      it "returns user_id and type for a valid #{col} token" do
        token = described_class.generate(user: user, type: col)
        result = described_class.verify(token)
        expect(result[:user_id]).to eq(user.id)
        expect(result[:type]).to eq(col)
      end
    end

    it 'returns nil for a tampered token' do
      expect(described_class.verify('not-a-real-token')).to be_nil
    end

    it 'returns nil for an empty string' do
      expect(described_class.verify('')).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

```bash
bin/rspec spec/services/email_unsubscribe_token_service_spec.rb --format documentation
```

Expected: FAIL with `NameError: uninitialized constant EmailUnsubscribeTokenService`

- [ ] **Step 3: Implement the service**

Create `app/services/email_unsubscribe_token_service.rb`:

```ruby
# frozen_string_literal: true

class EmailUnsubscribeTokenService
  VERIFIER_SALT = :email_unsubscribe

  PREFERENCE_COLUMNS = %w[
    marketing_emails
    payment_reminder_emails
    payment_receipt_emails
    event_reminder_emails
    event_update_emails
  ].freeze

  def self.generate(user:, type:)
    raise ArgumentError, "Unknown preference type: #{type}" unless PREFERENCE_COLUMNS.include?(type.to_s)

    Rails.application.message_verifier(VERIFIER_SALT).generate({ user_id: user.id, type: type.to_s })
  end

  def self.verify(token)
    return nil if token.blank?

    data = Rails.application.message_verifier(VERIFIER_SALT).verify(token)
    return nil unless PREFERENCE_COLUMNS.include?(data[:type])

    data
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

```bash
bin/rspec spec/services/email_unsubscribe_token_service_spec.rb --format documentation
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/email_unsubscribe_token_service.rb spec/services/email_unsubscribe_token_service_spec.rb
git commit -m "Add EmailUnsubscribeTokenService for signed per-type unsubscribe tokens"
```

---

## Task 3: Routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add the email_preferences member resource**

In `config/routes.rb`, find the `resource :me` block and add the email_preferences resource inside it:

```ruby
# Before:
resource :me, only: %i[show update destroy], controller: 'me' do
  patch :password, on: :member
end

# After:
resource :me, only: %i[show update destroy], controller: 'me' do
  patch :password, on: :member
  resource :email_preferences, only: :update, controller: 'me/email_preferences'
end
```

- [ ] **Step 2: Add the public unsubscribe route**

In `config/routes.rb`, add the following inside `namespace :v1` but outside (and after) `namespace :auth`:

```ruby
get '/unsubscribe', to: 'unsubscribe#show'
```

Place it between the closing `end` of `namespace :auth` and the `scope '/:languages_code'` block:

```ruby
namespace :v1 do
  namespace :auth do
    # ... existing auth routes ...
  end

  get '/unsubscribe', to: 'unsubscribe#show'   # ← add this line

  scope '/:languages_code', constraints: { languages_code: /[a-zA-Z]{2}-[a-zA-Z]{2}/ } do
    # ... existing event/order routes ...
  end
end
```

- [ ] **Step 3: Verify the routes exist**

```bash
bin/rails routes | grep -E "email_preferences|unsubscribe"
```

Expected output includes:
```
PATCH  /api/v1/auth/me/email_preferences        api/v1/auth/me/email_preferences#update
GET    /api/v1/unsubscribe                       api/v1/unsubscribe#show
```

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb
git commit -m "Add routes for email preferences PATCH and public unsubscribe GET"
```

---

## Task 4: Me::EmailPreferencesController

**Files:**
- Create: `app/controllers/api/v1/auth/me/email_preferences_controller.rb`
- Create: `spec/requests/api/v1/auth/me/email_preferences_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/requests/api/v1/auth/me/email_preferences_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'PATCH /api/v1/auth/me/email_preferences' do
  let(:user) { create(:user) }
  let(:token) { JwtService.encode(user.id) }

  def patch_preferences(params, jwt: token)
    patch '/api/v1/auth/me/email_preferences',
          params: params.to_json,
          headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{jwt}" }
  end

  context 'with a valid JWT' do
    it 'returns 200 with the updated email_preferences object' do
      patch_preferences({ marketing_emails: true, event_reminder_emails: true })

      expect(response).to have_http_status(:ok)
      expect(json['email_preferences']['marketing_emails']).to be true
      expect(json['email_preferences']['event_reminder_emails']).to be true
    end

    it 'persists the updated values to the database' do
      patch_preferences({ payment_reminder_emails: true })

      expect(user.reload.payment_reminder_emails).to be true
    end

    it 'only changes provided fields and leaves others unchanged' do
      user.update!(event_reminder_emails: true)
      patch_preferences({ marketing_emails: true })

      expect(user.reload.event_reminder_emails).to be true
      expect(user.reload.marketing_emails).to be true
    end

    it 'returns all five preference fields in the response' do
      patch_preferences({ marketing_emails: false })

      expect(json['email_preferences'].keys).to match_array(%w[
        marketing_emails payment_reminder_emails payment_receipt_emails
        event_reminder_emails event_update_emails
      ])
    end

    it 'ignores unknown fields and still returns 200' do
      patch_preferences({ unknown_field: true, marketing_emails: true })

      expect(response).to have_http_status(:ok)
      expect(json['email_preferences'].keys).to match_array(%w[
        marketing_emails payment_reminder_emails payment_receipt_emails
        event_reminder_emails event_update_emails
      ])
    end
  end

  context 'without a JWT' do
    it 'returns 401' do
      patch '/api/v1/auth/me/email_preferences',
            params: { marketing_emails: true }.to_json,
            headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with an invalid JWT' do
    it 'returns 401' do
      patch_preferences({ marketing_emails: true }, jwt: 'invalid-token')
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

```bash
bin/rspec spec/requests/api/v1/auth/me/email_preferences_spec.rb --format documentation
```

Expected: FAIL with routing error or `ActionController::RoutingError`

- [ ] **Step 3: Create the directory and controller**

```bash
mkdir -p app/controllers/api/v1/auth/me
```

Create `app/controllers/api/v1/auth/me/email_preferences_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      module Me
        class EmailPreferencesController < ActionController::API
          include Authenticatable

          before_action :authenticate_user!

          def update
            attrs = params.permit(*EmailUnsubscribeTokenService::PREFERENCE_COLUMNS).to_h
                          .transform_values { |v| ActiveRecord::Type::Boolean.new.cast(v) }

            current_user.update!(attrs)
            render json: { email_preferences: email_preferences_json(current_user) }
          end

          private

            def email_preferences_json(user)
              EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.index_with { |col| user.public_send(col) }
            end
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

```bash
bin/rspec spec/requests/api/v1/auth/me/email_preferences_spec.rb --format documentation
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/auth/me/email_preferences_controller.rb \
        spec/requests/api/v1/auth/me/email_preferences_spec.rb
git commit -m "Add PATCH /api/v1/auth/me/email_preferences endpoint"
```

---

## Task 5: UnsubscribeController

**Files:**
- Create: `app/controllers/api/v1/unsubscribe_controller.rb`
- Create: `spec/requests/api/v1/unsubscribe_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/requests/api/v1/unsubscribe_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/unsubscribe' do
  before { ENV['FRONTEND_URL'] = 'http://localhost:3001' }
  after  { ENV.delete('FRONTEND_URL') }

  def get_unsubscribe(token)
    get "/api/v1/unsubscribe?token=#{CGI.escape(token)}"
  end

  context 'with a valid token for marketing_emails' do
    let(:user) { create(:user, marketing_emails: true) }
    let(:token) { EmailUnsubscribeTokenService.generate(user: user, type: 'marketing_emails') }

    it 'sets marketing_emails to false' do
      get_unsubscribe(token)
      expect(user.reload.marketing_emails).to be false
    end

    it 'redirects to the frontend unsubscribed page with the type param' do
      get_unsubscribe(token)
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?type=marketing_emails')
    end
  end

  context 'with a valid token for event_reminder_emails' do
    let(:user) { create(:user, event_reminder_emails: true) }
    let(:token) { EmailUnsubscribeTokenService.generate(user: user, type: 'event_reminder_emails') }

    it 'sets event_reminder_emails to false' do
      get_unsubscribe(token)
      expect(user.reload.event_reminder_emails).to be false
    end

    it 'redirects with the correct type param' do
      get_unsubscribe(token)
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?type=event_reminder_emails')
    end
  end

  context 'when the user is already unsubscribed (idempotent)' do
    let(:user) { create(:user, marketing_emails: false) }
    let(:token) { EmailUnsubscribeTokenService.generate(user: user, type: 'marketing_emails') }

    it 'still redirects with the type param' do
      get_unsubscribe(token)
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?type=marketing_emails')
    end
  end

  context 'with an invalid token' do
    it 'redirects with error=invalid_token' do
      get_unsubscribe('not-a-real-token')
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?error=invalid_token')
    end
  end

  context 'with a token for a soft-deleted user' do
    let(:user) { create(:user) }
    let(:token) { EmailUnsubscribeTokenService.generate(user: user, type: 'marketing_emails') }

    it 'redirects with error=invalid_token' do
      user.update!(deleted_at: Time.current)
      get_unsubscribe(token)
      expect(response).to redirect_to('http://localhost:3001/unsubscribed?error=invalid_token')
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

```bash
bin/rspec spec/requests/api/v1/unsubscribe_spec.rb --format documentation
```

Expected: FAIL with `ActionController::RoutingError` or uninitialized constant error.

- [ ] **Step 3: Create the controller**

Create `app/controllers/api/v1/unsubscribe_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    class UnsubscribeController < ActionController::API
      def show
        data = EmailUnsubscribeTokenService.verify(params[:token].to_s)
        return redirect_to "#{frontend_url}?error=invalid_token", allow_other_host: true unless data

        user = User.active.find_by(id: data[:user_id])
        return redirect_to "#{frontend_url}?error=invalid_token", allow_other_host: true unless user

        user.update(data[:type] => false)
        redirect_to "#{frontend_url}?type=#{data[:type]}", allow_other_host: true
      end

      private

        def frontend_url
          "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3001')}/unsubscribed"
        end
    end
  end
end
```

- [ ] **Step 4: Run the spec to verify it passes**

```bash
bin/rspec spec/requests/api/v1/unsubscribe_spec.rb --format documentation
```

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/unsubscribe_controller.rb \
        spec/requests/api/v1/unsubscribe_spec.rb
git commit -m "Add GET /api/v1/unsubscribe public token-based unsubscribe endpoint"
```

---

## Task 6: Add email_preferences to all user_json responses

**Files:**
- Modify: `app/controllers/api/v1/auth/me_controller.rb`
- Modify: `app/controllers/api/v1/auth/registrations_controller.rb`
- Modify: `app/controllers/api/v1/auth/sessions_controller.rb`
- Modify: `app/controllers/api/v1/auth/googles_controller.rb`
- Modify: `app/controllers/api/v1/auth/facebooks_controller.rb`
- Modify: `app/controllers/api/v1/auth/apples_controller.rb`
- Modify: `app/controllers/api/v1/auth/microsofts_controller.rb`
- Modify: `app/controllers/api/v1/auth/passkeys_controller.rb`
- Modify: `app/controllers/api/v1/auth/passwords_controller.rb`
- Modify: `spec/requests/api/v1/auth/me_spec.rb`

- [ ] **Step 1: Write a failing test**

In `spec/requests/api/v1/auth/me_spec.rb`, inside the `describe 'GET /api/v1/auth/me'` block, add:

```ruby
it 'includes email_preferences with all five fields' do
  get_me(headers: { 'Authorization' => "Bearer #{token}" })

  expect(json['email_preferences']).to eq({
    'marketing_emails'        => false,
    'payment_reminder_emails' => false,
    'payment_receipt_emails'  => false,
    'event_reminder_emails'   => false,
    'event_update_emails'     => false
  })
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rspec spec/requests/api/v1/auth/me_spec.rb --format documentation
```

Expected: FAIL — `email_preferences` key missing from response.

- [ ] **Step 3: Update every user_json method**

In each of the 9 controllers listed, find the private `user_json(user)` method and:

1. Add `email_preferences: email_preferences_json(user)` to the returned hash.
2. Add the private helper `email_preferences_json` immediately after `user_json`.

Apply this pattern to all 9 controllers. The `user_json` return hash addition (same in every controller):

```ruby
def user_json(user)
  {
    id: user.id,
    first_name: user.first_name,
    last_name: user.last_name,
    email: user.email,
    avatar_url: user.avatar_url,
    phone_number: user.phone_number,
    church_name: user.church_name,
    city: user.city,
    language: user.language,
    can_change_email: user.user_identities.exists?(provider: 'email'),
    email_preferences: email_preferences_json(user)   # ← add this line
  }
end

def email_preferences_json(user)
  EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.index_with { |col| user.public_send(col) }
end
```

Note: `passwords_controller.rb` and `sessions_controller.rb` may not include `can_change_email` — only add the `email_preferences` key and the helper; don't add fields that aren't already there.

**Controllers to update** (find `def user_json` in each):
- `app/controllers/api/v1/auth/me_controller.rb`
- `app/controllers/api/v1/auth/registrations_controller.rb`
- `app/controllers/api/v1/auth/sessions_controller.rb`
- `app/controllers/api/v1/auth/googles_controller.rb`
- `app/controllers/api/v1/auth/facebooks_controller.rb`
- `app/controllers/api/v1/auth/apples_controller.rb`
- `app/controllers/api/v1/auth/microsofts_controller.rb`
- `app/controllers/api/v1/auth/passkeys_controller.rb`
- `app/controllers/api/v1/auth/passwords_controller.rb`

- [ ] **Step 4: Run the failing test to verify it passes**

```bash
bin/rspec spec/requests/api/v1/auth/me_spec.rb --format documentation
```

Expected: all tests PASS including the new `includes email_preferences with all five fields`.

- [ ] **Step 5: Run the full test suite to catch regressions**

```bash
bin/rspec --format progress
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/auth/me_controller.rb \
        app/controllers/api/v1/auth/registrations_controller.rb \
        app/controllers/api/v1/auth/sessions_controller.rb \
        app/controllers/api/v1/auth/googles_controller.rb \
        app/controllers/api/v1/auth/facebooks_controller.rb \
        app/controllers/api/v1/auth/apples_controller.rb \
        app/controllers/api/v1/auth/microsofts_controller.rb \
        app/controllers/api/v1/auth/passkeys_controller.rb \
        app/controllers/api/v1/auth/passwords_controller.rb \
        spec/requests/api/v1/auth/me_spec.rb
git commit -m "Include email_preferences in all user_json responses"
```

---

## Task 7: RegistrationsController — accept marketing_emails at signup

**Files:**
- Modify: `app/controllers/api/v1/auth/registrations_controller.rb`
- Modify: `spec/requests/api/v1/auth/registrations_spec.rb`

- [ ] **Step 1: Write the failing tests**

In `spec/requests/api/v1/auth/registrations_spec.rb`, add a new context inside `context 'with valid required params'`:

```ruby
context 'with marketing_emails: true' do
  it 'creates the user with marketing_emails enabled' do
    post_registration(valid_params.merge(marketing_emails: true))

    user = User.find_by(email: 'ion@example.com')
    expect(user.marketing_emails).to be true
  end

  it 'returns marketing_emails: true in the response email_preferences' do
    post_registration(valid_params.merge(marketing_emails: true))

    expect(json['user']['email_preferences']['marketing_emails']).to be true
  end
end

context 'without marketing_emails param' do
  it 'defaults marketing_emails to false' do
    post_registration(valid_params)

    user = User.find_by(email: 'ion@example.com')
    expect(user.marketing_emails).to be false
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rspec spec/requests/api/v1/auth/registrations_spec.rb --format documentation
```

Expected: the two new tests FAIL — `marketing_emails: true` is not persisted.

- [ ] **Step 3: Update register_user! to accept marketing_emails**

In `app/controllers/api/v1/auth/registrations_controller.rb`, find the `register_user!` private method and add `marketing_emails:` to the `User.create!` call:

```ruby
def register_user!
  ActiveRecord::Base.transaction do
    user = User.create!(
      first_name:      params[:first_name],
      last_name:       params[:last_name].presence,
      email:           normalized_email,
      password:        params[:password],
      phone_number:    params[:phone_number].presence,
      church_name:     params[:church_name].presence,
      city:            params[:city].presence,
      language:        params[:language].presence,
      marketing_emails: params.fetch(:marketing_emails, false) == true
    )
    user.user_identities.create!(provider: 'email', uid: user.email)
    # rubocop:disable Rails/SkipsModelValidations
    Attendee.backfill_user(email: user.email, user_id: user.id)
    # rubocop:enable Rails/SkipsModelValidations
    user
  end
end
```

The expression `params.fetch(:marketing_emails, false) == true` ensures only a literal boolean `true` sets the field — absent or falsy params default to `false`.

- [ ] **Step 4: Run the tests to verify they pass**

```bash
bin/rspec spec/requests/api/v1/auth/registrations_spec.rb --format documentation
```

Expected: all tests PASS.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rspec --format progress
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/auth/registrations_controller.rb \
        spec/requests/api/v1/auth/registrations_spec.rb
git commit -m "Accept marketing_emails opt-in at signup"
```

---

## Done

At this point:
- 5 preference columns exist on `users`, all defaulting to `false`
- `GET /api/v1/auth/me` and all other auth responses include `email_preferences`
- `PATCH /api/v1/auth/me/email_preferences` lets authenticated users update their toggles
- `GET /api/v1/unsubscribe?token=xxx` processes per-type unsubscribe link clicks and redirects to the frontend
- Email/password signup accepts `marketing_emails: true` to capture consent
- OAuth users start with all preferences `false` (post-onboarding step is a separate scope)
- `EmailUnsubscribeTokenService` is ready for use in `SendgridService` when future notification emails are added — call `EmailUnsubscribeTokenService.generate(user: user, type: 'the_column_name')` to build the unsubscribe URL for each email type
