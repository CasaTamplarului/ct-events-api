# Forgot Password Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add forgot-password and reset-password endpoints backed by SendGrid dynamic email templates, plus store user language at registration.

**Architecture:** Two new controller actions (`passwords#forgot`, `passwords#reset`) under `/api/v1/auth/password/`. A plain-text URL-safe token is stored on the user row with a 1-hour expiry. A dedicated `SendgridService` encapsulates the SendGrid API call. The SendGrid API key lives in Rails encrypted credentials; the frontend URL base lives in `.env` as `FRONTEND_URL`.

**Tech Stack:** Rails 8.1, sendgrid-ruby gem, rack-attack (already present), RSpec + WebMock (already present).

---

## File Map

| Action | File |
|--------|------|
| Create | `db/migrate/20260529100000_add_forgot_password_to_users.rb` |
| Modify | `Gemfile` — add `sendgrid-ruby` |
| Create | `app/services/sendgrid_service.rb` |
| Modify | `config/initializers/rack_attack.rb` — add forgot throttle |
| Modify | `config/routes.rb` — add password routes |
| Create | `app/controllers/api/v1/auth/passwords_controller.rb` |
| Modify | `app/controllers/api/v1/auth/registrations_controller.rb` — store language |
| Create | `spec/services/sendgrid_service_spec.rb` |
| Create | `spec/requests/api/v1/auth/passwords_spec.rb` |
| Modify | `spec/requests/api/v1/auth/rack_attack_spec.rb` — add forgot throttle test |
| Modify | `spec/requests/api/v1/auth/registrations_spec.rb` — add language test |

---

## Task 1: Database migration

**Files:**
- Create: `db/migrate/20260529100000_add_forgot_password_to_users.rb`

- [ ] **Step 1: Write the migration**

```ruby
# db/migrate/20260529100000_add_forgot_password_to_users.rb
# frozen_string_literal: true

class AddForgotPasswordToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :language, :string
    add_column :users, :password_reset_token, :string
    add_column :users, :password_reset_token_expires_at, :datetime
    add_index :users, :password_reset_token, unique: true
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
```

Expected: `== AddForgotPasswordToUsers: migrated` with no errors.

- [ ] **Step 3: Verify schema has the new columns**

```bash
grep -A 5 'password_reset_token\|language' db/schema.rb
```

Expected: three new column lines inside the `users` table block.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260529100000_add_forgot_password_to_users.rb db/schema.rb
git commit -m "feat: add forgot password columns and language to users"
```

---

## Task 2: Add sendgrid-ruby gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add the gem**

In `Gemfile`, after the `# Google Sign-In` block, add:

```ruby
# Email
gem 'sendgrid-ruby'
```

- [ ] **Step 2: Install**

```bash
bundle install
```

Expected: `Bundle complete!` with no errors.

- [ ] **Step 3: Add SendGrid credentials**

Run the credentials editor:

```bash
EDITOR=nano bin/rails credentials:edit
```

Add the following YAML block (do not overwrite existing keys):

```yaml
sendgrid:
  api_key: YOUR_SENDGRID_API_KEY
  from_email: noreply@yourdomain.com
```

Save and close the editor.

- [ ] **Step 4: Add FRONTEND_URL to .env**

Open `.env` and add:

```
FRONTEND_URL=https://your-frontend-domain.com
```

- [ ] **Step 5: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "feat: add sendgrid-ruby gem"
```

> **Note:** Never commit `.env` or `config/master.key`.

---

## Task 3: SendgridService

**Files:**
- Create: `app/services/sendgrid_service.rb`
- Create: `spec/services/sendgrid_service_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/services/sendgrid_service_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendgridService do
  describe '.send_password_reset' do
    let(:romanian_user) { build(:user, first_name: 'Ion', language: 'ro-RO', email: 'ion@example.com') }
    let(:english_user) { build(:user, first_name: 'John', language: 'en-US', email: 'john@example.com') }
    let(:reset_url) { 'https://app.example.com/reset-password?token=abc123' }

    before do
      stub_request(:post, 'https://api.sendgrid.com/v3/mail/send')
        .to_return(status: 202, body: '', headers: {})
    end

    it 'posts to the SendGrid mail/send endpoint' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
    end

    it 'sends with the correct template ID' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req| JSON.parse(req.body)['template_id'] == 'd-952a77f57d9f410597cfa1cf84260cef' }
    end

    it 'sets is_romanian to true for a Romanian user' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req|
          data = JSON.parse(req.body)['personalizations'].first['dynamic_template_data']
          data['is_romanian'] == true
        }
    end

    it 'sets is_romanian to false for a non-Romanian user' do
      SendgridService.send_password_reset(user: english_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req|
          data = JSON.parse(req.body)['personalizations'].first['dynamic_template_data']
          data['is_romanian'] == false
        }
    end

    it 'sends first_name and reset_url in dynamic template data' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req|
          data = JSON.parse(req.body)['personalizations'].first['dynamic_template_data']
          data['first_name'] == 'Ion' && data['reset_url'] == reset_url
        }
    end

    it 'includes the current year as a string in dynamic template data' do
      SendgridService.send_password_reset(user: romanian_user, reset_url: reset_url)

      expect(WebMock).to have_requested(:post, 'https://api.sendgrid.com/v3/mail/send')
        .with { |req|
          data = JSON.parse(req.body)['personalizations'].first['dynamic_template_data']
          data['year'] == Time.current.year.to_s
        }
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/services/sendgrid_service_spec.rb --format documentation
```

Expected: `6 examples, 6 failures` — `uninitialized constant SendgridService`.

- [ ] **Step 3: Implement SendgridService**

```ruby
# app/services/sendgrid_service.rb
# frozen_string_literal: true

require 'sendgrid-ruby'

class SendgridService
  RESET_PASSWORD_TEMPLATE_ID = 'd-952a77f57d9f410597cfa1cf84260cef'

  def self.send_password_reset(user:, reset_url:)
    mail = SendGrid::Mail.new
    mail.from = SendGrid::Email.new(email: Rails.application.credentials.dig(:sendgrid, :from_email))
    mail.template_id = RESET_PASSWORD_TEMPLATE_ID

    personalization = SendGrid::Personalization.new
    personalization.add_to(SendGrid::Email.new(email: user.email))
    personalization.dynamic_template_data = {
      is_romanian: user.language&.start_with?('ro') || false,
      first_name: user.first_name,
      reset_url: reset_url,
      year: Time.current.year.to_s
    }
    mail.add_personalization(personalization)

    client = SendGrid::API.new(api_key: Rails.application.credentials.dig(:sendgrid, :api_key))
    client.client.mail._('send').post(request_body: mail.to_json)
  end
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/services/sendgrid_service_spec.rb --format documentation
```

Expected: `6 examples, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add app/services/sendgrid_service.rb spec/services/sendgrid_service_spec.rb
git commit -m "feat: add SendgridService for password reset emails"
```

---

## Task 4: Routes and rack-attack

**Files:**
- Modify: `config/routes.rb`
- Modify: `config/initializers/rack_attack.rb`

- [ ] **Step 1: Add password routes to config/routes.rb**

Replace the `namespace :auth` block (lines 10–15 in current routes.rb):

```ruby
namespace :auth do
  resource :google, only: :create
  resource :me, only: :show, controller: 'me'
  resource :registration, only: :create
  resource :session, only: :create
  scope '/password' do
    post '/forgot', to: 'passwords#forgot'
    post '/reset',  to: 'passwords#reset'
  end
end
```

- [ ] **Step 2: Verify routing**

```bash
bin/rails routes | grep password
```

Expected output includes:
```
POST /api/v1/auth/password/forgot  api/v1/auth/passwords#forgot
POST /api/v1/auth/password/reset   api/v1/auth/passwords#reset
```

- [ ] **Step 3: Add forgot throttle to rack_attack.rb**

Replace the full content of `config/initializers/rack_attack.rb`:

```ruby
# frozen_string_literal: true

module Rack
  class Attack
    AUTH_ENDPOINTS = %w[/api/v1/auth/registration /api/v1/auth/session].freeze

    throttle('auth/ip', limit: 5, period: 1.minute) do |req|
      req.ip if AUTH_ENDPOINTS.include?(req.path) && req.post?
    end

    throttle('password_forgot/ip', limit: 3, period: 1.minute) do |req|
      req.ip if req.path == '/api/v1/auth/password/forgot' && req.post?
    end

    self.throttled_responder = lambda do |_env|
      body = { error: 'Too many requests. Please try again later.' }.to_json
      [429, { 'Content-Type' => 'application/json' }, [body]]
    end
  end
end
```

- [ ] **Step 4: Commit**

```bash
git add config/routes.rb config/initializers/rack_attack.rb
git commit -m "feat: add password reset routes and forgot rate limit"
```

---

## Task 5: PasswordsController

**Files:**
- Create: `app/controllers/api/v1/auth/passwords_controller.rb`
- Create: `spec/requests/api/v1/auth/passwords_spec.rb`

- [ ] **Step 1: Write the failing spec**

```ruby
# spec/requests/api/v1/auth/passwords_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth::Passwords' do
  before do
    allow(SendgridService).to receive(:send_password_reset)
  end

  describe 'POST /api/v1/auth/password/forgot' do
    def post_forgot(params)
      post '/api/v1/auth/password/forgot',
           params: params.to_json,
           headers: { 'Content-Type' => 'application/json' }
    end

    context 'with an existing user' do
      let!(:user) { create(:user, email: 'ion@example.com') }

      it 'returns 200' do
        post_forgot(email: 'ion@example.com')

        expect(response).to have_http_status(:ok)
      end

      it 'returns the generic success message' do
        post_forgot(email: 'ion@example.com')

        expect(json['message']).to eq('If that email is registered, a reset link has been sent.')
      end

      it 'sets a password_reset_token on the user' do
        post_forgot(email: 'ion@example.com')

        expect(user.reload.password_reset_token).to be_present
      end

      it 'sets password_reset_token_expires_at to ~1 hour from now' do
        post_forgot(email: 'ion@example.com')

        expect(user.reload.password_reset_token_expires_at).to be_within(5.seconds).of(1.hour.from_now)
      end

      it 'calls SendgridService.send_password_reset with the user' do
        post_forgot(email: 'ion@example.com')

        expect(SendgridService).to have_received(:send_password_reset)
          .with(user: user, reset_url: anything)
      end

      it 'builds reset_url from FRONTEND_URL env var' do
        stub_const('ENV', ENV.to_h.merge('FRONTEND_URL' => 'https://app.example.com'))
        post_forgot(email: 'ion@example.com')

        expect(SendgridService).to have_received(:send_password_reset)
          .with(user: anything, reset_url: start_with('https://app.example.com/reset-password?token='))
      end
    end

    context 'with a non-existent email' do
      it 'returns 200 (no user enumeration)' do
        post_forgot(email: 'nobody@example.com')

        expect(response).to have_http_status(:ok)
      end

      it 'does not call SendgridService' do
        post_forgot(email: 'nobody@example.com')

        expect(SendgridService).not_to have_received(:send_password_reset)
      end
    end

    context 'with a missing email param' do
      it 'returns 422' do
        post_forgot({})

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to be_present
      end
    end
  end

  describe 'POST /api/v1/auth/password/reset' do
    def post_reset(params)
      post '/api/v1/auth/password/reset',
           params: params.to_json,
           headers: { 'Content-Type' => 'application/json' }
    end

    let(:user) { create(:user) }
    let(:valid_token) { 'valid_token_abc123xyz' }

    before do
      user.update_columns(
        password_reset_token: valid_token,
        password_reset_token_expires_at: 1.hour.from_now
      )
    end

    context 'with a valid token' do
      it 'returns 200 with a JWT and user data' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(response).to have_http_status(:ok)
        expect(json['jwt']).to be_present
        expect(json['user']['email']).to eq(user.email)
      end

      it 'updates the user password' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(user.reload.authenticate('NewPassword1!')).to be_truthy
      end

      it 'clears the reset token after use' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(user.reload.password_reset_token).to be_nil
        expect(user.reload.password_reset_token_expires_at).to be_nil
      end

      it 'returns a JWT that decodes to the correct user_id' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(JwtService.decode(json['jwt'])).to eq(user.id)
      end

      it 'includes all user profile fields in the response' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(json['user']).to include('id', 'first_name', 'last_name', 'email',
                                        'avatar_url', 'phone_number', 'church_name', 'city')
      end
    end

    context 'with an invalid token' do
      it 'returns 422' do
        post_reset(token: 'bad_token', password: 'NewPassword1!')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('Invalid or expired reset token')
      end
    end

    context 'with an expired token' do
      before { user.update_columns(password_reset_token_expires_at: 1.minute.ago) }

      it 'returns 422' do
        post_reset(token: valid_token, password: 'NewPassword1!')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to eq('Invalid or expired reset token')
      end
    end

    context 'with a password shorter than 8 characters' do
      it 'returns 422' do
        post_reset(token: valid_token, password: 'short')

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json['error']).to match(/password/i)
      end
    end

    context 'with missing params' do
      it 'returns 422 when token is missing' do
        post_reset(password: 'NewPassword1!')

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 422 when password is missing' do
        post_reset(token: valid_token)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/auth/passwords_spec.rb --format documentation
```

Expected: many failures — `No route matches` or `uninitialized constant`.

- [ ] **Step 3: Implement PasswordsController**

```ruby
# app/controllers/api/v1/auth/passwords_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Auth
      class PasswordsController < ActionController::API
        def forgot
          if params[:email].blank?
            render json: { error: 'email is required' }, status: :unprocessable_entity
            return
          end

          user = User.find_by(email: params[:email].to_s.strip.downcase)
          if user
            token = SecureRandom.urlsafe_base64(32)
            user.update_columns(
              password_reset_token: token,
              password_reset_token_expires_at: 1.hour.from_now
            )
            reset_url = "#{ENV.fetch('FRONTEND_URL', nil)}/reset-password?token=#{token}"
            SendgridService.send_password_reset(user: user, reset_url: reset_url)
          end

          render json: { message: 'If that email is registered, a reset link has been sent.' }, status: :ok
        end

        def reset
          if params[:token].blank? || params[:password].blank?
            render json: { error: 'token and password are required' }, status: :unprocessable_entity
            return
          end

          user = User.find_by(password_reset_token: params[:token])

          if user.nil? || user.password_reset_token_expires_at.nil? ||
             user.password_reset_token_expires_at < Time.current
            render json: { error: 'Invalid or expired reset token' }, status: :unprocessable_entity
            return
          end

          unless user.update(password: params[:password],
                             password_reset_token: nil,
                             password_reset_token_expires_at: nil)
            render json: { error: user.errors.full_messages.first }, status: :unprocessable_entity
            return
          end

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

        private

          def user_json(user)
            {
              id: user.id,
              first_name: user.first_name,
              last_name: user.last_name,
              email: user.email,
              avatar_url: user.avatar_url,
              phone_number: user.phone_number,
              church_name: user.church_name,
              city: user.city
            }
          end
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/requests/api/v1/auth/passwords_spec.rb --format documentation
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Run the full suite to check for regressions**

```bash
bundle exec rspec --format progress
```

Expected: 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/auth/passwords_controller.rb spec/requests/api/v1/auth/passwords_spec.rb
git commit -m "feat: add forgot and reset password endpoints"
```

---

## Task 6: rack-attack spec for forgot endpoint

**Files:**
- Modify: `spec/requests/api/v1/auth/rack_attack_spec.rb`

- [ ] **Step 1: Add the forgot throttle test**

Open `spec/requests/api/v1/auth/rack_attack_spec.rb` and add the following `describe` block inside `RSpec.describe 'Auth endpoint rate limiting'`, after the existing `POST /api/v1/auth/session` block:

```ruby
  def post_forgot(email)
    post '/api/v1/auth/password/forgot',
         params: { email: email }.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  describe 'POST /api/v1/auth/password/forgot' do
    before do
      allow(SendgridService).to receive(:send_password_reset)
    end

    it 'allows the first 3 requests and blocks the 4th with 429' do
      3.times { post_forgot('nobody@example.com') }
      post_forgot('nobody@example.com')

      expect(response).to have_http_status(:too_many_requests)
      expect(json['error']).to eq('Too many requests. Please try again later.')
    end
  end
```

- [ ] **Step 2: Run the rack-attack spec**

```bash
bundle exec rspec spec/requests/api/v1/auth/rack_attack_spec.rb --format documentation
```

Expected: all examples pass including the new forgot throttle test.

- [ ] **Step 3: Commit**

```bash
git add spec/requests/api/v1/auth/rack_attack_spec.rb
git commit -m "test: add rack-attack spec for forgot password throttle"
```

---

## Task 7: Store language at registration

**Files:**
- Modify: `app/controllers/api/v1/auth/registrations_controller.rb`
- Modify: `spec/requests/api/v1/auth/registrations_spec.rb`

- [ ] **Step 1: Write the failing test**

In `spec/requests/api/v1/auth/registrations_spec.rb`, add this example inside the `'with valid required params'` context:

```ruby
    it 'stores the language from params' do
      post_registration(valid_params.merge(language: 'ro-RO'))

      expect(User.find_by(email: 'ion@example.com').language).to eq('ro-RO')
    end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/auth/registrations_spec.rb --format documentation
```

Expected: the new example fails — `expected nil to eq "ro-RO"`.

- [ ] **Step 3: Update RegistrationsController to accept language**

In `app/controllers/api/v1/auth/registrations_controller.rb`, update the `User.create!` call inside `register_user!` to include `language`:

```ruby
          def register_user!
            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: params[:first_name],
                last_name: params[:last_name].presence,
                email: normalized_email,
                password: params[:password],
                phone_number: params[:phone_number].presence,
                church_name: params[:church_name].presence,
                city: params[:city].presence,
                language: params[:language].presence
              )
              user.user_identities.create!(provider: 'email', uid: user.email)
              # rubocop:disable Rails/SkipsModelValidations
              Attendee.where(email_address: user.email).update_all(user_id: user.id)
              # rubocop:enable Rails/SkipsModelValidations
              user
            end
          end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/requests/api/v1/auth/registrations_spec.rb --format documentation
```

Expected: all examples pass, 0 failures.

- [ ] **Step 5: Run the full suite**

```bash
bundle exec rspec --format progress
```

Expected: 0 failures.

- [ ] **Step 6: Run RuboCop**

```bash
bin/rubocop
```

Expected: no offenses (or only pre-existing ones).

- [ ] **Step 7: Commit and push**

```bash
git add app/controllers/api/v1/auth/registrations_controller.rb \
        spec/requests/api/v1/auth/registrations_spec.rb
git commit -m "feat: store user language at registration"
git push origin main
```
