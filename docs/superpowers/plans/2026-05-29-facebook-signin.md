# Facebook Sign-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `POST /api/v1/auth/facebook` that accepts a Facebook `accessToken`, validates it via the Graph API, and returns a JWT + user object — mirroring the existing Google sign-in flow.

**Architecture:** `FacebookAuthService` validates the token with two Graph API calls (debug_token then /me), `FacebooksController` finds or creates the user using the same pattern as `GooglesController`, and the User model is relaxed to allow nil email for phone-number-only Facebook accounts.

**Tech Stack:** Rails 8.1, Ruby stdlib `Net::HTTP`, Facebook Graph API, existing `UserIdentity`/`User` models, RSpec + WebMock.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `app/services/facebook_auth_service.rb` | Create | Validate token + fetch user data from Graph API |
| `app/controllers/api/v1/auth/facebooks_controller.rb` | Create | Handle POST /auth/facebook, find/create user |
| `app/models/user.rb` | Modify | Relax email presence to allow nil |
| `config/routes.rb` | Modify | Add `resource :facebook, only: :create` |
| `config/locales/en.yml` | Modify | Add `invalid_facebook_token`, `access_token_required` |
| `config/locales/ro.yml` | Modify | Add same keys in Romanian |
| `spec/requests/api/v1/auth/facebook_spec.rb` | Create | Full request-level coverage |

---

### Task 1: Relax User email validation + i18n keys

**Files:**
- Modify: `app/models/user.rb`
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`

- [ ] **Step 1: Write a failing model test**

Add to `spec/models/user_spec.rb` (or create it if it doesn't exist — check with `ls spec/models/`):

```ruby
it 'is valid with a nil email (Facebook user with phone-only account)' do
  user = build(:user, email: nil, password: nil, password_digest: nil)
  expect(user).to be_valid
end
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
bundle exec rspec spec/models/user_spec.rb --format documentation
```

Expected: FAIL — `Email can't be blank`

- [ ] **Step 3: Relax the email validation in `app/models/user.rb`**

Replace lines 12-13:
```ruby
# Before
validates :email, presence: true, uniqueness: true,
                  format: { with: URI::MailTo::EMAIL_REGEXP }

# After
validates :email, uniqueness: { allow_nil: true },
                  format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
```

Full file after change:
```ruby
# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password(validations: false, reset_token: false)

  has_many :attendees, dependent: :nullify
  has_many :user_identities, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :first_name, presence: true
  validates :email, uniqueness: { allow_nil: true },
                    format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :password, length: { minimum: 8 }, allow_nil: true
end
```

- [ ] **Step 4: Run the model test to confirm it passes**

```bash
bundle exec rspec spec/models/user_spec.rb --format documentation
```

Expected: PASS

- [ ] **Step 5: Run the full suite to confirm nothing regressed**

```bash
bundle exec rspec
```

Expected: all existing examples pass (email presence for registration is enforced at the controller level, not the model, so nothing breaks).

- [ ] **Step 6: Add i18n keys to `config/locales/en.yml`**

Add two lines under `auth.errors:`:
```yaml
en:
  auth:
    errors:
      # ... existing keys ...
      invalid_facebook_token: "Invalid Facebook token"
      access_token_required: "access_token is required"
```

- [ ] **Step 7: Add i18n keys to `config/locales/ro.yml`**

```yaml
ro:
  auth:
    errors:
      # ... existing keys ...
      invalid_facebook_token: "Token Facebook invalid"
      access_token_required: "access_token este necesar"
```

- [ ] **Step 8: Commit**

```bash
git add app/models/user.rb config/locales/en.yml config/locales/ro.yml spec/models/user_spec.rb
git commit -m "Allow nil email on User for Facebook phone-only accounts; add Facebook i18n keys"
```

---

### Task 2: FacebookAuthService

**Files:**
- Create: `app/services/facebook_auth_service.rb`
- Create: `spec/services/facebook_auth_service_spec.rb`

- [ ] **Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FacebookAuthService do
  let(:access_token) { 'test_access_token' }
  let(:app_id) { 'test_app_id' }
  let(:app_secret) { 'test_app_secret' }

  let(:debug_token_url) do
    "https://graph.facebook.com/debug_token?input_token=#{access_token}&access_token=#{app_id}%7C#{app_secret}"
  end

  let(:me_url) do
    "https://graph.facebook.com/me?fields=id%2Cemail%2Cfirst_name%2Clast_name%2Cpicture.type%28large%29&access_token=#{access_token}"
  end

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :facebook_app_id).and_return(app_id)
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :facebook_app_secret).and_return(app_secret)
  end

  describe '.call' do
    context 'with a valid token' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: true, app_id: app_id } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        stub_request(:get, me_url)
          .to_return(
            status: 200,
            body: {
              id: 'fb-uid-123',
              email: 'ion@example.com',
              first_name: 'Ion',
              last_name: 'Popescu',
              picture: { data: { url: 'https://fb.com/photo.jpg' } }
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns user data hash' do
        result = described_class.call(access_token)

        expect(result[:uid]).to eq('fb-uid-123')
        expect(result[:email]).to eq('ion@example.com')
        expect(result[:first_name]).to eq('Ion')
        expect(result[:last_name]).to eq('Popescu')
        expect(result[:avatar_url]).to eq('https://fb.com/photo.jpg')
      end
    end

    context 'with a nil email (phone-only Facebook account)' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: true, app_id: app_id } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        stub_request(:get, me_url)
          .to_return(
            status: 200,
            body: { id: 'fb-uid-456', first_name: 'Ion', last_name: 'Popescu',
                    picture: { data: { url: nil } } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'returns nil email without raising' do
        result = described_class.call(access_token)
        expect(result[:email]).to be_nil
      end
    end

    context 'when debug_token returns is_valid: false' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: false, app_id: app_id } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(access_token) }
          .to raise_error(FacebookAuthService::InvalidTokenError)
      end
    end

    context 'when debug_token returns wrong app_id' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(
            status: 200,
            body: { data: { is_valid: true, app_id: 'other_app' } }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(access_token) }
          .to raise_error(FacebookAuthService::InvalidTokenError)
      end
    end

    context 'when Graph API returns non-2xx' do
      before do
        stub_request(:get, debug_token_url)
          .to_return(status: 400, body: '{}',
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(access_token) }
          .to raise_error(FacebookAuthService::InvalidTokenError)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/services/facebook_auth_service_spec.rb --format documentation
```

Expected: FAIL — `uninitialized constant FacebookAuthService`

- [ ] **Step 3: Create `app/services/facebook_auth_service.rb`**

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'

class FacebookAuthService
  class InvalidTokenError < StandardError; end

  GRAPH_BASE = 'https://graph.facebook.com'

  def self.call(access_token)
    app_id     = Rails.application.credentials.dig(:auth, :facebook_app_id)
    app_secret = Rails.application.credentials.dig(:auth, :facebook_app_secret)

    validate_token!(access_token, app_id, app_secret)
    fetch_user_data(access_token)
  end

  class << self
    private

    def validate_token!(access_token, app_id, app_secret)
      url = URI("#{GRAPH_BASE}/debug_token")
      url.query = URI.encode_www_form(
        input_token: access_token,
        access_token: "#{app_id}|#{app_secret}"
      )
      body = get_json!(url)
      data = body['data'] || {}
      raise InvalidTokenError, 'Token is invalid' unless data['is_valid'] && data['app_id'] == app_id
    end

    def fetch_user_data(access_token)
      url = URI("#{GRAPH_BASE}/me")
      url.query = URI.encode_www_form(
        fields: 'id,email,first_name,last_name,picture.type(large)',
        access_token: access_token
      )
      payload = get_json!(url)

      {
        uid:        payload['id'],
        email:      payload['email'],
        first_name: payload['first_name'].to_s,
        last_name:  payload['last_name'].to_s,
        avatar_url: payload.dig('picture', 'data', 'url')
      }
    end

    def get_json!(url)
      response = Net::HTTP.get_response(url)
      raise InvalidTokenError, "Graph API error: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/services/facebook_auth_service_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 5: Commit**

```bash
git add app/services/facebook_auth_service.rb spec/services/facebook_auth_service_spec.rb
git commit -m "Add FacebookAuthService with Graph API token validation"
```

---

### Task 3: FacebooksController + route + request specs

**Files:**
- Create: `app/controllers/api/v1/auth/facebooks_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/auth/facebook_spec.rb`

- [ ] **Step 1: Add the route to `config/routes.rb`**

Inside `namespace :auth do`, add `resource :facebook, only: :create` alongside the existing Google line:

```ruby
namespace :auth do
  resource :facebook, only: :create
  resource :google,   only: :create
  resource :me, only: %i[show update], controller: 'me' do
    patch :password, on: :member
  end
  resource :registration, only: :create
  resource :session,      only: :create
  scope '/password' do
    post '/forgot', to: 'passwords#forgot'
    post '/reset',  to: 'passwords#reset'
  end
end
```

- [ ] **Step 2: Write the request spec**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/facebook' do
  let(:app_id)     { 'test_app_id' }
  let(:app_secret) { 'test_app_secret' }
  let(:access_token) { 'test_fb_access_token' }

  let(:debug_token_url) do
    "https://graph.facebook.com/debug_token?input_token=#{access_token}&access_token=#{app_id}%7C#{app_secret}"
  end

  let(:me_url) do
    "https://graph.facebook.com/me?fields=id%2Cemail%2Cfirst_name%2Clast_name%2Cpicture.type%28large%29&access_token=#{access_token}"
  end

  let(:fb_user_payload) do
    {
      id: 'fb-uid-123',
      email: 'ion@example.com',
      first_name: 'Ion',
      last_name: 'Popescu',
      picture: { data: { url: 'https://fb.com/photo.jpg' } }
    }.to_json
  end

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :facebook_app_id).and_return(app_id)
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :facebook_app_secret).and_return(app_secret)

    stub_request(:get, debug_token_url)
      .to_return(status: 200,
                 body: { data: { is_valid: true, app_id: app_id } }.to_json,
                 headers: { 'Content-Type' => 'application/json' })
  end

  def post_facebook(params = { access_token: access_token })
    post '/api/v1/auth/facebook',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  context 'with a valid token — new user' do
    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 200 with a JWT and user data' do
      post_facebook
      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@example.com')
      expect(json['user']['first_name']).to eq('Ion')
    end

    it 'creates a new User record' do
      expect { post_facebook }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity with provider facebook' do
      post_facebook
      expect(UserIdentity.where(provider: 'facebook', uid: 'fb-uid-123')).to exist
    end

    it 'returns a JWT that decodes to the correct user_id' do
      post_facebook
      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(User.find_by(email: 'ion@example.com').id)
    end

    it 'sets avatar_url from the picture field' do
      post_facebook
      expect(User.find_by(email: 'ion@example.com').avatar_url).to eq('https://fb.com/photo.jpg')
    end

    it 'returns can_change_email: false' do
      post_facebook
      expect(json['user']['can_change_email']).to be false
    end

    it 'includes language in the user response' do
      post_facebook
      expect(json['user'].key?('language')).to be true
    end
  end

  context 'with a valid token — existing UserIdentity (idempotent)' do
    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
      post_facebook
    end

    it 'does not create a second user on repeated sign-in' do
      expect { post_facebook }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with a valid token — existing User matched by email' do
    let!(:existing_user) { create(:user, email: 'ion@example.com') }

    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'does not create a new user' do
      expect { post_facebook }.not_to change(User, :count)
    end

    it 'links a new Facebook identity to the existing user' do
      post_facebook
      expect(UserIdentity.find_by(provider: 'facebook', uid: 'fb-uid-123').user).to eq(existing_user)
    end

    it 'updates avatar_url on the existing user' do
      post_facebook
      expect(existing_user.reload.avatar_url).to eq('https://fb.com/photo.jpg')
    end
  end

  context 'attendee backfill on new user' do
    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'links existing attendees with matching email to the new user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')

      post_facebook

      user = User.find_by(email: 'ion@example.com')
      expect(attendee.reload.user).to eq(user)
    end
  end

  context 'attendee backfill on email-matched existing user' do
    let!(:existing_user) { create(:user, email: 'ion@example.com') }

    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_user_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'links existing attendees to the matched user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')

      post_facebook

      expect(attendee.reload.user).to eq(existing_user)
    end
  end

  context 'with a nil email (phone-only Facebook account)' do
    let(:fb_no_email_payload) do
      {
        id: 'fb-uid-789',
        first_name: 'Ion',
        last_name: 'Popescu',
        picture: { data: { url: nil } }
      }.to_json
    end

    before do
      stub_request(:get, me_url)
        .to_return(status: 200, body: fb_no_email_payload,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'creates a user with nil email' do
      post_facebook
      expect(response).to have_http_status(:ok)
      user = User.find_by(first_name: 'Ion')
      expect(user.email).to be_nil
    end
  end

  context 'with a missing access_token param' do
    it 'returns 422' do
      post_facebook({})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('access_token is required')
    end
  end

  context 'with an invalid token (is_valid: false)' do
    before do
      stub_request(:get, debug_token_url)
        .to_return(status: 200,
                   body: { data: { is_valid: false, app_id: app_id } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 401' do
      post_facebook
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Facebook token')
    end
  end

  context 'with a token from a different app' do
    before do
      stub_request(:get, debug_token_url)
        .to_return(status: 200,
                   body: { data: { is_valid: true, app_id: 'other_app' } }.to_json,
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 401' do
      post_facebook
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Facebook token')
    end
  end

  context 'when Graph API returns non-2xx' do
    before do
      stub_request(:get, debug_token_url)
        .to_return(status: 400, body: '{}',
                   headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns 401' do
      post_facebook
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Facebook token')
    end
  end
end
```

- [ ] **Step 3: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/auth/facebook_spec.rb --format documentation
```

Expected: FAIL — routing error (no route matches POST /api/v1/auth/facebook)

- [ ] **Step 4: Create `app/controllers/api/v1/auth/facebooks_controller.rb`**

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      class FacebooksController < ActionController::API
        include LocaleSetter

        before_action :set_locale

        def create
          if params[:access_token].blank?
            render json: { error: I18n.t('auth.errors.access_token_required') }, status: :unprocessable_content
            return
          end

          facebook_data = FacebookAuthService.call(params[:access_token])
          user = find_or_create_user(facebook_data)
          jwt  = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue FacebookAuthService::InvalidTokenError
          render json: { error: I18n.t('auth.errors.invalid_facebook_token') }, status: :unauthorized
        rescue ActiveRecord::RecordNotUnique
          identity = UserIdentity.find_by(provider: 'facebook', uid: facebook_data&.dig(:uid))
          user     = identity&.user || User.find_by(email: facebook_data&.dig(:email))
          return render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized unless user

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

        private

          def find_or_create_user(facebook_data)
            identity = UserIdentity.find_by(provider: 'facebook', uid: facebook_data[:uid])
            return identity.user if identity

            if facebook_data[:email].present?
              user = User.find_by(email: facebook_data[:email])
              if user
                ActiveRecord::Base.transaction do
                  user.user_identities.create!(provider: 'facebook', uid: facebook_data[:uid])
                  user.update!(avatar_url: facebook_data[:avatar_url])
                  # rubocop:disable Rails/SkipsModelValidations
                  Attendee.where(email_address: facebook_data[:email]).update_all(user_id: user.id)
                  # rubocop:enable Rails/SkipsModelValidations
                end
                return user
              end
            end

            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: facebook_data[:first_name],
                last_name:  facebook_data[:last_name],
                email:      facebook_data[:email],
                avatar_url: facebook_data[:avatar_url]
              )
              user.user_identities.create!(provider: 'facebook', uid: facebook_data[:uid])
              if facebook_data[:email].present?
                # rubocop:disable Rails/SkipsModelValidations
                Attendee.where(email_address: facebook_data[:email]).update_all(user_id: user.id)
                # rubocop:enable Rails/SkipsModelValidations
              end
              user
            end
          end

          def user_json(user)
            {
              id:               user.id,
              first_name:       user.first_name,
              last_name:        user.last_name,
              email:            user.email,
              avatar_url:       user.avatar_url,
              phone_number:     user.phone_number,
              church_name:      user.church_name,
              city:             user.city,
              language:         user.language,
              can_change_email: user.user_identities.exists?(provider: 'email')
            }
          end
      end
    end
  end
end
```

- [ ] **Step 5: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/requests/api/v1/auth/facebook_spec.rb --format documentation
```

Expected: all examples pass

- [ ] **Step 6: Run the full suite to confirm nothing regressed**

```bash
bundle exec rspec
```

Expected: all examples pass, 0 failures

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/auth/facebooks_controller.rb \
        config/routes.rb \
        spec/requests/api/v1/auth/facebook_spec.rb
git commit -m "Add POST /api/v1/auth/facebook endpoint"
```

- [ ] **Step 8: Push**

```bash
git push origin main
```
