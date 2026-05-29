# Microsoft Sign-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `POST /api/v1/auth/microsoft` that accepts a Microsoft `id_token` from MSAL, validates it locally via Microsoft's JWKS, and returns a JWT + user object mirroring the existing Google sign-in flow.

**Architecture:** `MicrosoftAuthService` fetches Microsoft's JWKS (cached 1 hour, auto-refreshed on key rotation), validates the signed JWT locally using the `jwt` gem already in the project, then `MicrosoftsController` finds or creates the user using the same pattern as `GooglesController`. No new gems needed.

**Tech Stack:** Rails 8.1, `jwt` gem (already in project), `Net::HTTP` (stdlib), Microsoft Identity Platform JWKS endpoint.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `app/services/microsoft_auth_service.rb` | Create | JWKS fetch/cache + JWT validation |
| `app/controllers/api/v1/auth/microsofts_controller.rb` | Create | Handle POST /auth/microsoft, find/create user |
| `config/routes.rb` | Modify | Add `resource :microsoft, only: :create` |
| `config/locales/en.yml` | Modify | Add `invalid_microsoft_token` key |
| `config/locales/ro.yml` | Modify | Add `invalid_microsoft_token` key |
| `spec/services/microsoft_auth_service_spec.rb` | Create | Unit tests with real RSA keys + WebMock stubs |
| `spec/requests/api/v1/auth/microsoft_spec.rb` | Create | Full request-level coverage |

---

### Task 1: i18n keys + MicrosoftAuthService

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`
- Create: `app/services/microsoft_auth_service.rb`
- Create: `spec/services/microsoft_auth_service_spec.rb`

- [ ] **Step 1: Add i18n key to `config/locales/en.yml`**

Add one line under `auth.errors:` (after `invalid_facebook_token`):

```yaml
      invalid_microsoft_token: "Invalid Microsoft token"
```

- [ ] **Step 2: Add i18n key to `config/locales/ro.yml`**

Add one line under `auth.errors:` (after `invalid_facebook_token`):

```yaml
      invalid_microsoft_token: "Token Microsoft invalid"
```

- [ ] **Step 3: Create `spec/services/microsoft_auth_service_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe MicrosoftAuthService do
  let(:client_id)  { 'test-microsoft-client-id' }
  let(:rsa_key)    { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk)        { JWT::JWK.new(rsa_key.public_key) }
  let(:jwks_body)  { { keys: [jwk.export] }.to_json }
  let(:jwks_uri)   { 'https://login.microsoftonline.com/consumers/discovery/v2.0/keys' }

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :microsoft_client_id).and_return(client_id)
    stub_request(:get, jwks_uri)
      .to_return(status: 200, body: jwks_body,
                 headers: { 'Content-Type' => 'application/json' })
    # Reset class-level JWKS cache between examples
    described_class.instance_variable_set(:@jwks_cache, nil)
    described_class.instance_variable_set(:@jwks_fetched_at, nil)
  end

  def encode_token(overrides = {})
    payload = {
      sub: 'ms-uid-123',
      email: 'ion@outlook.com',
      given_name: 'Ion',
      family_name: 'Popescu',
      iss: MicrosoftAuthService::ISSUER,
      aud: client_id,
      exp: 1.hour.from_now.to_i,
      iat: Time.current.to_i
    }.merge(overrides)
    JWT.encode(payload, rsa_key, 'RS256', { kid: jwk.kid })
  end

  describe '.call' do
    context 'with a valid token' do
      it 'returns the correct uid' do
        expect(described_class.call(encode_token)[:uid]).to eq('ms-uid-123')
      end

      it 'returns the correct email' do
        expect(described_class.call(encode_token)[:email]).to eq('ion@outlook.com')
      end

      it 'returns the correct first_name' do
        expect(described_class.call(encode_token)[:first_name]).to eq('Ion')
      end

      it 'returns the correct last_name' do
        expect(described_class.call(encode_token)[:last_name]).to eq('Popescu')
      end

      it 'returns nil avatar_url' do
        expect(described_class.call(encode_token)[:avatar_url]).to be_nil
      end
    end

    context 'with an expired token' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(exp: 1.hour.ago.to_i)) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with wrong audience' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(aud: 'other-client-id')) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with wrong issuer' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(iss: 'https://accounts.google.com')) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with a bad signature (signed with a different key)' do
      it 'raises InvalidTokenError' do
        other_key = OpenSSL::PKey::RSA.generate(2048)
        token = JWT.encode(
          { sub: 'x', aud: client_id, iss: MicrosoftAuthService::ISSUER,
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          other_key, 'RS256', { kid: jwk.kid }
        )
        expect { described_class.call(token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS fetch returns non-2xx' do
      before do
        stub_request(:get, jwks_uri).to_return(status: 503, body: 'Service Unavailable')
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'with missing credentials' do
      before do
        allow(Rails.application.credentials).to receive(:dig)
          .with(:auth, :microsoft_client_id).and_return(nil)
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end

    context 'JWKS cache — reuses keys within TTL' do
      it 'only makes one HTTP call for two consecutive sign-ins' do
        described_class.call(encode_token)
        described_class.call(encode_token)
        expect(WebMock).to have_requested(:get, jwks_uri).once
      end

      it 'refetches after TTL expires' do
        described_class.call(encode_token)
        described_class.instance_variable_set(
          :@jwks_fetched_at,
          (MicrosoftAuthService::JWKS_TTL + 1.second).ago
        )
        described_class.call(encode_token)
        expect(WebMock).to have_requested(:get, jwks_uri).twice
      end
    end

    context 'key rotation — kid not in cached JWKS' do
      let(:new_rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
      let(:new_jwk)     { JWT::JWK.new(new_rsa_key.public_key) }

      it 'refreshes JWKS and succeeds on retry' do
        stub_request(:get, jwks_uri)
          .to_return(
            { status: 200, body: { keys: [jwk.export] }.to_json,
              headers: { 'Content-Type' => 'application/json' } },
            { status: 200, body: { keys: [new_jwk.export] }.to_json,
              headers: { 'Content-Type' => 'application/json' } }
          )

        token = JWT.encode(
          { sub: 'ms-uid-new', email: 'ion@outlook.com', given_name: 'Ion',
            family_name: 'Popescu', iss: MicrosoftAuthService::ISSUER,
            aud: client_id, exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          new_rsa_key, 'RS256', { kid: new_jwk.kid }
        )

        result = described_class.call(token)
        expect(result[:uid]).to eq('ms-uid-new')
      end

      it 'raises InvalidTokenError when kid still not found after refresh' do
        unknown_key = OpenSSL::PKey::RSA.generate(2048)
        token = JWT.encode(
          { sub: 'x', aud: client_id, iss: MicrosoftAuthService::ISSUER,
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          unknown_key, 'RS256', { kid: 'unknown-kid' }
        )

        expect { described_class.call(token) }
          .to raise_error(MicrosoftAuthService::InvalidTokenError)
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/services/microsoft_auth_service_spec.rb --format documentation
```

Expected: FAIL — `uninitialized constant MicrosoftAuthService`

- [ ] **Step 5: Create `app/services/microsoft_auth_service.rb`**

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'

class MicrosoftAuthService
  class InvalidTokenError < StandardError; end

  JWKS_URI = 'https://login.microsoftonline.com/consumers/discovery/v2.0/keys'
  ISSUER   = 'https://login.microsoftonline.com/9188040d-6c67-4c5b-b112-36a304b66dad/v2.0'
  JWKS_TTL = 1.hour

  @jwks_cache      = nil
  @jwks_fetched_at = nil

  def self.call(id_token)
    client_id = Rails.application.credentials.dig(:auth, :microsoft_client_id)
    raise InvalidTokenError, 'Microsoft credentials not configured' if client_id.blank?

    payload = decode_token(id_token, client_id)
    {
      uid:        payload['sub'],
      email:      payload['email'],
      first_name: payload['given_name'].to_s,
      last_name:  payload['family_name'].to_s,
      avatar_url: nil
    }
  rescue JWT::DecodeError => e
    raise InvalidTokenError, e.message
  end

  class << self
    private

    def decode_token(id_token, client_id, retry_on_stale_key: true)
      JWT.decode(id_token, nil, true, {
        algorithms: ['RS256'],
        jwks: fetch_jwks,
        iss: ISSUER,
        verify_iss: true,
        aud: client_id,
        verify_aud: true
      }).first
    rescue JWT::DecodeError => e
      if retry_on_stale_key && e.message.include?('Could not find public key')
        @jwks_fetched_at = nil
        decode_token(id_token, client_id, retry_on_stale_key: false)
      else
        raise
      end
    end

    def fetch_jwks
      if @jwks_cache.nil? || @jwks_fetched_at.nil? ||
         Time.current - @jwks_fetched_at > JWKS_TTL
        refresh_jwks!
      end
      @jwks_cache
    end

    def refresh_jwks!
      response = Net::HTTP.get_response(URI(JWKS_URI))
      unless response.is_a?(Net::HTTPSuccess)
        raise InvalidTokenError, "JWKS fetch failed: #{response.code}"
      end

      @jwks_cache = JWT::JWK::Set.new(JSON.parse(response.body))
      @jwks_fetched_at = Time.current
      @jwks_cache
    rescue JSON::ParserError => e
      raise InvalidTokenError, "Invalid JWKS response: #{e.message}"
    rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT => e
      raise InvalidTokenError, "Network error fetching JWKS: #{e.message}"
    end
  end
end
```

- [ ] **Step 6: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/services/microsoft_auth_service_spec.rb --format documentation
```

Expected: all examples pass. Note — RSA key generation makes this spec slower than usual (~5-10 seconds). That is expected.

- [ ] **Step 7: Run the full suite**

```bash
bundle exec rspec
```

Expected: all existing examples pass, 0 failures.

- [ ] **Step 8: Run RuboCop**

```bash
bundle exec rubocop app/services/microsoft_auth_service.rb spec/services/microsoft_auth_service_spec.rb
```

Fix any offenses before committing.

- [ ] **Step 9: Commit**

```bash
git add app/services/microsoft_auth_service.rb \
        spec/services/microsoft_auth_service_spec.rb \
        config/locales/en.yml config/locales/ro.yml
git commit -m "Add MicrosoftAuthService with JWKS validation and i18n keys"
```

---

### Task 2: MicrosoftsController + route + request specs

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/api/v1/auth/microsofts_controller.rb`
- Create: `spec/requests/api/v1/auth/microsoft_spec.rb`

- [ ] **Step 1: Add the route to `config/routes.rb`**

Add `resource :microsoft, only: :create` inside `namespace :auth do`:

```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  apipie

  get '_healthcheck', to: 'healthcheck#index'

  namespace :api do
    namespace :v1 do
      namespace :auth do
        resource :facebook,  only: :create
        resource :google,    only: :create
        resource :microsoft, only: :create
        resource :me, only: %i[show update], controller: 'me' do
          patch :password, on: :member
        end
        resource :registration, only: :create
        resource :session, only: :create
        scope '/password' do
          post '/forgot', to: 'passwords#forgot'
          post '/reset',  to: 'passwords#reset'
        end
      end

      scope '/:languages_code', constraints: { languages_code: /[a-zA-Z]{2}-[a-zA-Z]{2}/ } do
        namespace :events do
          resources :upcoming, only: :index
          resources :past, only: :index
          resources :hero, only: :index
        end

        resources :event, only: :show, param: :slug
        resources :orders, only: :create
      end
    end
  end
end
```

- [ ] **Step 2: Create `spec/requests/api/v1/auth/microsoft_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/microsoft' do
  let(:ms_data) do
    {
      uid:        'ms-uid-123',
      email:      'ion@outlook.com',
      first_name: 'Ion',
      last_name:  'Popescu',
      avatar_url: nil
    }
  end

  def post_microsoft(params = { id_token: 'valid.ms.token' })
    post '/api/v1/auth/microsoft',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  context 'with a valid token — new user' do
    before { allow(MicrosoftAuthService).to receive(:call).and_return(ms_data) }

    it 'returns 200 with a JWT and user data' do
      post_microsoft
      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@outlook.com')
      expect(json['user']['first_name']).to eq('Ion')
    end

    it 'creates a new User record' do
      expect { post_microsoft }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity with provider microsoft' do
      post_microsoft
      expect(UserIdentity.where(provider: 'microsoft', uid: 'ms-uid-123')).to exist
    end

    it 'returns a JWT that decodes to the correct user_id' do
      post_microsoft
      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(User.find_by(email: 'ion@outlook.com').id)
    end

    it 'returns nil avatar_url' do
      post_microsoft
      expect(json['user']['avatar_url']).to be_nil
    end

    it 'returns can_change_email: false' do
      post_microsoft
      expect(json['user']['can_change_email']).to be false
    end

    it 'includes language in the user response' do
      post_microsoft
      expect(json['user'].key?('language')).to be true
    end
  end

  context 'with a valid token — existing UserIdentity (idempotent)' do
    before do
      allow(MicrosoftAuthService).to receive(:call).and_return(ms_data)
      post_microsoft
    end

    it 'does not create a second user on repeated sign-in' do
      expect { post_microsoft }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with a valid token — existing User matched by email' do
    let!(:existing_user) { create(:user, email: 'ion@outlook.com') }

    before { allow(MicrosoftAuthService).to receive(:call).and_return(ms_data) }

    it 'does not create a new user' do
      expect { post_microsoft }.not_to change(User, :count)
    end

    it 'links a new Microsoft identity to the existing user' do
      post_microsoft
      expect(UserIdentity.find_by(provider: 'microsoft', uid: 'ms-uid-123').user).to eq(existing_user)
    end
  end

  context 'attendee backfill on new user' do
    before { allow(MicrosoftAuthService).to receive(:call).and_return(ms_data) }

    it 'links existing attendees with matching email to the new user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@outlook.com')

      post_microsoft

      user = User.find_by(email: 'ion@outlook.com')
      expect(attendee.reload.user).to eq(user)
    end
  end

  context 'attendee backfill on email-matched existing user' do
    let!(:existing_user) { create(:user, email: 'ion@outlook.com') }

    before { allow(MicrosoftAuthService).to receive(:call).and_return(ms_data) }

    it 'links existing attendees to the matched user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@outlook.com')

      post_microsoft

      expect(attendee.reload.user).to eq(existing_user)
    end
  end

  context 'with a missing id_token param' do
    it 'returns 422' do
      post_microsoft({})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('id_token is required')
    end
  end

  context 'with an invalid token' do
    before do
      allow(MicrosoftAuthService).to receive(:call)
        .and_raise(MicrosoftAuthService::InvalidTokenError, 'invalid')
    end

    it 'returns 401' do
      post_microsoft
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Microsoft token')
    end
  end
end
```

- [ ] **Step 3: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/auth/microsoft_spec.rb --format documentation
```

Expected: FAIL — routing error (no route matches POST /api/v1/auth/microsoft)

- [ ] **Step 4: Create `app/controllers/api/v1/auth/microsofts_controller.rb`**

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      class MicrosoftsController < ActionController::API
        include LocaleSetter

        before_action :set_locale

        def create
          if params[:id_token].blank?
            render json: { error: I18n.t('auth.errors.id_token_required') }, status: :unprocessable_content
            return
          end

          microsoft_data = MicrosoftAuthService.call(params[:id_token])
          user = find_or_create_user(microsoft_data)
          jwt  = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue MicrosoftAuthService::InvalidTokenError
          render json: { error: I18n.t('auth.errors.invalid_microsoft_token') }, status: :unauthorized
        rescue ActiveRecord::RecordNotUnique
          identity = UserIdentity.find_by(provider: 'microsoft', uid: microsoft_data&.dig(:uid))
          user     = identity&.user || User.find_by(email: microsoft_data&.dig(:email))
          return render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized unless user

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

        private

          def find_or_create_user(microsoft_data)
            identity = UserIdentity.find_by(provider: 'microsoft', uid: microsoft_data[:uid])
            return identity.user if identity

            user = User.find_by(email: microsoft_data[:email])
            if user
              ActiveRecord::Base.transaction do
                user.user_identities.create!(provider: 'microsoft', uid: microsoft_data[:uid])
                user.update!(avatar_url: microsoft_data[:avatar_url])
                # rubocop:disable Rails/SkipsModelValidations
                Attendee.where(email_address: microsoft_data[:email]).update_all(user_id: user.id)
                # rubocop:enable Rails/SkipsModelValidations
              end
              return user
            end

            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: microsoft_data[:first_name],
                last_name:  microsoft_data[:last_name],
                email:      microsoft_data[:email],
                avatar_url: microsoft_data[:avatar_url]
              )
              user.user_identities.create!(provider: 'microsoft', uid: microsoft_data[:uid])
              # rubocop:disable Rails/SkipsModelValidations
              Attendee.where(email_address: microsoft_data[:email]).update_all(user_id: user.id)
              # rubocop:enable Rails/SkipsModelValidations
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
bundle exec rspec spec/requests/api/v1/auth/microsoft_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 6: Run the full suite**

```bash
bundle exec rspec
```

Expected: all examples pass, 0 failures.

- [ ] **Step 7: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/v1/auth/microsofts_controller.rb
```

Fix any offenses before committing.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/api/v1/auth/microsofts_controller.rb \
        config/routes.rb \
        spec/requests/api/v1/auth/microsoft_spec.rb
git commit -m "Add POST /api/v1/auth/microsoft endpoint"
```

- [ ] **Step 9: Push**

```bash
git push origin main
```
