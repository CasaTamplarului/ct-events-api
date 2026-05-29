# Apple Sign-In Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a single `POST /api/v1/auth/apple` endpoint that accepts Apple identity tokens from both iOS native and web clients, verifies them against Apple's JWKS, and returns a JWT + user object.

**Architecture:** `AppleAuthService` mirrors `MicrosoftAuthService` exactly — JWKS fetch/cache (1h TTL), single retry on stale key, RS256 verification. The key difference: audience is an array (`apple_bundle_ids`) so one endpoint handles both the iOS Bundle ID and the web Service ID. `ApplesController` mirrors `MicrosoftsController`. No new gems.

**Tech Stack:** Rails 8.1, `jwt` gem (already present), PostgreSQL.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `app/services/apple_auth_service.rb` | Create | Verify Apple identity tokens, return user data |
| `spec/services/apple_auth_service_spec.rb` | Create | Unit tests for the service |
| `config/locales/en.yml` | Modify | Add `invalid_apple_token` error key |
| `config/locales/ro.yml` | Modify | Add `invalid_apple_token` error key (Romanian) |
| `config/credentials.yml.enc` | Modify | Add `auth.apple_bundle_ids` array (placeholders) |
| `config/routes.rb` | Modify | Add `resource :apple, only: :create` |
| `app/controllers/api/v1/auth/apples_controller.rb` | Create | Controller — validate, call service, find/create user, return JWT |
| `spec/requests/api/v1/auth/apple_spec.rb` | Create | Request-level integration tests |
| `docs/auth/apple-signin-integration.md` | Create | FE integration guide (iOS, Web, React Native) |

---

### Task 1: AppleAuthService + unit tests

**Files:**
- Create: `app/services/apple_auth_service.rb`
- Create: `spec/services/apple_auth_service_spec.rb`

- [ ] **Step 1: Create `spec/services/apple_auth_service_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AppleAuthService do
  let(:bundle_ids) { %w[com.example.app com.example.app.web] }
  let(:rsa_key)    { OpenSSL::PKey::RSA.generate(2048) }
  let(:jwk)        { JWT::JWK.new(rsa_key.public_key) }
  let(:jwks_body)  { { keys: [jwk.export] }.to_json }
  let(:jwks_uri)   { 'https://appleid.apple.com/auth/keys' }

  before do
    allow(Rails.application.credentials).to receive(:dig)
      .with(:auth, :apple_bundle_ids).and_return(bundle_ids)
    stub_request(:get, jwks_uri)
      .to_return(status: 200, body: jwks_body,
                 headers: { 'Content-Type' => 'application/json' })
    described_class.instance_variable_set(:@jwks_cache, nil)
    described_class.instance_variable_set(:@jwks_fetched_at, nil)
  end

  def encode_token(overrides = {})
    payload = {
      sub:            'apple-uid-123',
      email:          'ion@icloud.com',
      email_verified: true,
      iss:            AppleAuthService::ISSUER,
      aud:            'com.example.app',
      exp:            1.hour.from_now.to_i,
      iat:            Time.current.to_i
    }.merge(overrides)
    JWT.encode(payload, rsa_key, 'RS256', { kid: jwk.kid })
  end

  describe '.call' do
    context 'with a valid token' do
      it 'returns the correct uid' do
        expect(described_class.call(encode_token)[:uid]).to eq('apple-uid-123')
      end

      it 'returns the correct email' do
        expect(described_class.call(encode_token)[:email]).to eq('ion@icloud.com')
      end

      it 'returns nil avatar_url' do
        expect(described_class.call(encode_token)[:avatar_url]).to be_nil
      end

      it 'returns nil last_name' do
        expect(described_class.call(encode_token)[:last_name]).to be_nil
      end
    end

    context 'with a regular email' do
      it 'derives first_name from the email prefix' do
        result = described_class.call(encode_token(email: 'ion@icloud.com'))
        expect(result[:first_name]).to eq('ion')
      end
    end

    context 'with a privaterelay email' do
      it 'sets first_name to "Apple"' do
        relay = 'abc123def@privaterelay.appleid.com'
        expect(described_class.call(encode_token(email: relay))[:first_name]).to eq('Apple')
      end

      it 'sets last_name to nil' do
        relay = 'abc123def@privaterelay.appleid.com'
        expect(described_class.call(encode_token(email: relay))[:last_name]).to be_nil
      end
    end

    context 'when audience matches the second bundle_id' do
      it 'succeeds' do
        token = encode_token(aud: 'com.example.app.web')
        expect { described_class.call(token) }.not_to raise_error
      end
    end

    context 'with email_verified: false' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(email_verified: false)) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with an expired token' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(exp: 1.hour.ago.to_i)) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with wrong issuer' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(iss: 'https://accounts.google.com')) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with audience not in bundle_ids list' do
      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token(aud: 'com.other.app')) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with a bad signature (signed with a different key)' do
      it 'raises InvalidTokenError' do # rubocop:disable RSpec/ExampleLength
        other_key = OpenSSL::PKey::RSA.generate(2048)
        token = JWT.encode(
          { sub: 'x', aud: 'com.example.app', iss: AppleAuthService::ISSUER,
            email: 'x@icloud.com', email_verified: true,
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          other_key, 'RS256', { kid: jwk.kid }
        )
        expect { described_class.call(token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS fetch returns non-2xx' do
      before { stub_request(:get, jwks_uri).to_return(status: 503, body: 'Service Unavailable') }

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS endpoint times out' do
      before { stub_request(:get, jwks_uri).to_raise(Net::ReadTimeout) }

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'with missing credentials' do
      before do
        allow(Rails.application.credentials).to receive(:dig)
          .with(:auth, :apple_bundle_ids).and_return(nil)
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call(encode_token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end

    context 'when JWKS cache is within TTL' do
      it 'only makes one HTTP call for two consecutive sign-ins' do
        described_class.call(encode_token)
        described_class.call(encode_token)
        expect(WebMock).to have_requested(:get, jwks_uri).once
      end

      it 'refetches after TTL expires' do # rubocop:disable RSpec/ExampleLength
        described_class.call(encode_token)
        described_class.instance_variable_set(
          :@jwks_fetched_at,
          (AppleAuthService::JWKS_TTL + 1.second).ago
        )
        described_class.call(encode_token)
        expect(WebMock).to have_requested(:get, jwks_uri).twice
      end
    end

    context 'when JWKS key rotation occurs (kid not in cached JWKS)' do
      let(:new_rsa_key) { OpenSSL::PKey::RSA.generate(2048) }
      let(:new_jwk)     { JWT::JWK.new(new_rsa_key.public_key) }

      it 'refreshes JWKS and succeeds on retry' do # rubocop:disable RSpec/ExampleLength
        stub_request(:get, jwks_uri)
          .to_return(
            { status: 200, body: { keys: [jwk.export] }.to_json,
              headers: { 'Content-Type' => 'application/json' } },
            { status: 200, body: { keys: [new_jwk.export] }.to_json,
              headers: { 'Content-Type' => 'application/json' } }
          )
        token = JWT.encode(
          { sub: 'apple-uid-new', email: 'ion@icloud.com', email_verified: true,
            iss: AppleAuthService::ISSUER, aud: 'com.example.app',
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          new_rsa_key, 'RS256', { kid: new_jwk.kid }
        )
        expect(described_class.call(token)[:uid]).to eq('apple-uid-new')
      end

      it 'raises InvalidTokenError when kid still not found after refresh' do # rubocop:disable RSpec/ExampleLength
        unknown_key = OpenSSL::PKey::RSA.generate(2048)
        token = JWT.encode(
          { sub: 'x', aud: 'com.example.app', iss: AppleAuthService::ISSUER,
            email: 'x@icloud.com', email_verified: true,
            exp: 1.hour.from_now.to_i, iat: Time.current.to_i },
          unknown_key, 'RS256', { kid: 'unknown-kid' }
        )
        expect { described_class.call(token) }
          .to raise_error(AppleAuthService::InvalidTokenError)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/services/apple_auth_service_spec.rb --format documentation 2>&1 | head -10
```

Expected: FAIL — `uninitialized constant AppleAuthService`

- [ ] **Step 3: Create `app/services/apple_auth_service.rb`**

```ruby
# frozen_string_literal: true

require 'net/http'
require 'json'

class AppleAuthService
  class InvalidTokenError < StandardError; end

  JWKS_URI = 'https://appleid.apple.com/auth/keys'
  ISSUER   = 'https://appleid.apple.com'
  JWKS_TTL = 1.hour

  @jwks_cache      = nil
  @jwks_fetched_at = nil

  def self.call(id_token)
    bundle_ids = Rails.application.credentials.dig(:auth, :apple_bundle_ids)
    raise InvalidTokenError, 'Apple credentials not configured' if bundle_ids.blank?

    payload = decode_token(id_token, bundle_ids)
    email = payload['email']
    raise InvalidTokenError, 'Email claim missing from Apple token' if email.blank?
    raise InvalidTokenError, 'Email not verified' unless payload['email_verified'] == true

    {
      uid:        payload['sub'],
      email:      email,
      first_name: derive_first_name(email),
      last_name:  nil,
      avatar_url: nil
    }
  rescue JWT::DecodeError => e
    raise InvalidTokenError, e.message
  end

  class << self
    private

      def decode_token(id_token, bundle_ids, retry_on_stale_key: true)
        JWT.decode(id_token, nil, true, {
                     algorithms: ['RS256'],
                     jwks: fetch_jwks,
                     iss: ISSUER,
                     verify_iss: true,
                     aud: bundle_ids,
                     verify_aud: true
                   }).first
      rescue JWT::DecodeError => e
        if retry_on_stale_key && e.message.include?('Could not find public key')
          @jwks_fetched_at = nil
          decode_token(id_token, bundle_ids, retry_on_stale_key: false)
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
        raise InvalidTokenError, "JWKS fetch failed: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        @jwks_cache = JWT::JWK::Set.new(JSON.parse(response.body))
        @jwks_fetched_at = Time.current
        @jwks_cache
      rescue JSON::ParserError, ArgumentError => e
        raise InvalidTokenError, "Invalid JWKS response: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT,
             Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
        raise InvalidTokenError, "Network error fetching JWKS: #{e.message}"
      end

      def derive_first_name(email)
        return 'Apple' if email.end_with?('@privaterelay.appleid.com')

        email.split('@').first.to_s
      end
  end
end
```

- [ ] **Step 4: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/services/apple_auth_service_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 5: Run the full suite**

```bash
bundle exec rspec
```

Expected: all existing examples still pass, 0 failures.

- [ ] **Step 6: Run RuboCop**

```bash
bundle exec rubocop app/services/apple_auth_service.rb spec/services/apple_auth_service_spec.rb
```

Fix any offenses.

- [ ] **Step 7: Commit**

```bash
git add app/services/apple_auth_service.rb spec/services/apple_auth_service_spec.rb
git commit -m "Add AppleAuthService with JWKS-based token verification"
```

---

### Task 2: i18n + credentials + route + ApplesController + request spec + FE doc + push

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`
- Modify: `config/credentials.yml.enc`
- Modify: `config/routes.rb`
- Create: `app/controllers/api/v1/auth/apples_controller.rb`
- Create: `spec/requests/api/v1/auth/apple_spec.rb`
- Create: `docs/auth/apple-signin-integration.md`

- [ ] **Step 1: Add `invalid_apple_token` to `config/locales/en.yml`**

Read the file first to find the current `auth.errors:` section. The key `invalid_microsoft_token` is around line 44. Add the new key immediately after it:

```yaml
      invalid_apple_token: "Invalid Apple token"
```

Resulting block (lines around 44-45):
```yaml
      invalid_microsoft_token: "Invalid Microsoft token"
      invalid_apple_token: "Invalid Apple token"
```

- [ ] **Step 2: Add `invalid_apple_token` to `config/locales/ro.yml`**

The Romanian `id_token_required` is around line 10. Find `invalid_microsoft_token` in the `auth.errors:` block (it's in a nested structure — in `ro.yml` the auth errors may be at a different path). Add after it:

```yaml
      invalid_apple_token: "Token Apple invalid"
```

- [ ] **Step 3: Add Apple credentials**

```bash
bin/rails credentials:edit
```

Add under the existing `auth:` key (alongside `jwt_secret`, `microsoft_client_id`, etc.):

```yaml
    apple_bundle_ids:
      - com.example.app
      - com.example.app.web
```

These are placeholder values. The real Bundle ID and Service ID are set once the team configures them in Apple Developer Console. Save and close.

- [ ] **Step 4: Add the Apple route to `config/routes.rb`**

Inside `namespace :auth do`, add `resource :apple, only: :create` after `resource :microsoft, only: :create`:

```ruby
namespace :auth do
  resource :facebook,  only: :create
  resource :google,    only: :create
  resource :microsoft, only: :create
  resource :apple,     only: :create   # ← add this line
  # ... rest unchanged
end
```

- [ ] **Step 5: Create `spec/requests/api/v1/auth/apple_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/apple' do
  let(:apple_data) do
    {
      uid:        'apple-uid-123',
      email:      'ion@icloud.com',
      first_name: 'ion',
      last_name:  nil,
      avatar_url: nil
    }
  end

  def post_apple(params = { id_token: 'valid.apple.token' })
    post '/api/v1/auth/apple',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  context 'with a valid token — new user' do
    before { allow(AppleAuthService).to receive(:call).and_return(apple_data) }

    it 'returns 200 with a JWT and user data' do
      post_apple
      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@icloud.com')
      expect(json['user']['first_name']).to eq('ion')
    end

    it 'creates a new User record' do
      expect { post_apple }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity with provider apple' do
      post_apple
      expect(UserIdentity.where(provider: 'apple', uid: 'apple-uid-123')).to exist
    end

    it 'returns nil avatar_url' do
      post_apple
      expect(json['user']['avatar_url']).to be_nil
    end

    it 'returns can_change_email: false' do
      post_apple
      expect(json['user']['can_change_email']).to be false
    end
  end

  context 'with a valid token — existing UserIdentity (idempotent)' do
    before do
      allow(AppleAuthService).to receive(:call).and_return(apple_data)
      post_apple
    end

    it 'does not create a second user on repeated sign-in' do
      expect { post_apple }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with a valid token — existing User matched by email' do
    let!(:existing_user) { create(:user, email: 'ion@icloud.com') }

    before { allow(AppleAuthService).to receive(:call).and_return(apple_data) }

    it 'does not create a new user' do
      expect { post_apple }.not_to change(User, :count)
    end

    it 'links a new Apple identity to the existing user' do
      post_apple
      expect(UserIdentity.find_by(provider: 'apple', uid: 'apple-uid-123').user).to eq(existing_user)
    end
  end

  context 'attendee backfill on new user' do
    before { allow(AppleAuthService).to receive(:call).and_return(apple_data) }

    it 'links existing attendees with matching email to the new user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@icloud.com')
      post_apple
      user = User.find_by(email: 'ion@icloud.com')
      expect(attendee.reload.user).to eq(user)
    end
  end

  context 'attendee backfill on email-matched existing user' do
    let!(:existing_user) { create(:user, email: 'ion@icloud.com') }

    before { allow(AppleAuthService).to receive(:call).and_return(apple_data) }

    it 'links existing attendees to the matched user' do
      event    = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@icloud.com')
      post_apple
      expect(attendee.reload.user).to eq(existing_user)
    end
  end

  context 'with a missing id_token param' do
    it 'returns 422' do
      post_apple({})
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('id_token is required')
    end
  end

  context 'with an invalid token' do
    before do
      allow(AppleAuthService).to receive(:call)
        .and_raise(AppleAuthService::InvalidTokenError, 'invalid')
    end

    it 'returns 401' do
      post_apple
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Apple token')
    end
  end
end
```

- [ ] **Step 6: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/auth/apple_spec.rb --format documentation 2>&1 | head -10
```

Expected: routing error — `No route matches [POST] "/api/v1/auth/apple"` (route added but controller doesn't exist yet).

- [ ] **Step 7: Create `app/controllers/api/v1/auth/apples_controller.rb`**

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      class ApplesController < ActionController::API
        include LocaleSetter

        before_action :set_locale

        def create
          if params[:id_token].blank?
            render json: { error: I18n.t('auth.errors.id_token_required') },
                   status: :unprocessable_content
            return
          end

          apple_data = AppleAuthService.call(params[:id_token])
          user = find_or_create_user(apple_data)
          jwt  = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue AppleAuthService::InvalidTokenError
          render json: { error: I18n.t('auth.errors.invalid_apple_token') },
                 status: :unauthorized
        rescue ActiveRecord::RecordNotUnique
          identity = UserIdentity.find_by(provider: 'apple', uid: apple_data&.dig(:uid))
          user     = identity&.user || User.find_by(email: apple_data&.dig(:email))
          return render json: { error: I18n.t('auth.errors.unauthorized') },
                        status: :unauthorized unless user

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

        private

          def find_or_create_user(apple_data)
            identity = UserIdentity.find_by(provider: 'apple', uid: apple_data[:uid])
            return identity.user if identity

            user = User.find_by(email: apple_data[:email])
            if user
              ActiveRecord::Base.transaction do
                user.user_identities.create!(provider: 'apple', uid: apple_data[:uid])
                # rubocop:disable Rails/SkipsModelValidations
                Attendee.where(email_address: apple_data[:email]).update_all(user_id: user.id)
                # rubocop:enable Rails/SkipsModelValidations
              end
              return user
            end

            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: apple_data[:first_name],
                last_name:  apple_data[:last_name],
                email:      apple_data[:email]
              )
              user.user_identities.create!(provider: 'apple', uid: apple_data[:uid])
              # rubocop:disable Rails/SkipsModelValidations
              Attendee.where(email_address: apple_data[:email]).update_all(user_id: user.id)
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

- [ ] **Step 8: Run the request spec to confirm it passes**

```bash
bundle exec rspec spec/requests/api/v1/auth/apple_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 9: Run the full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 10: Run RuboCop**

```bash
bundle exec rubocop app/controllers/api/v1/auth/apples_controller.rb \
                    config/routes.rb \
                    spec/requests/api/v1/auth/apple_spec.rb \
                    config/locales/en.yml config/locales/ro.yml
```

Fix any offenses. (YAML file errors from RuboCop are pre-existing false positives — the linter treats YAML as Ruby. They were present before this task and are not introduced by it.)

- [ ] **Step 11: Create `docs/auth/apple-signin-integration.md`**

```markdown
# Apple Sign-In — FE Integration Guide

## Endpoint

```
POST /api/v1/auth/apple
Content-Type: application/json
```

## Flow

1. FE initiates Apple Sign-In and receives an `identityToken` / `id_token`
2. FE sends that token to this endpoint
3. BE validates the token locally using Apple's public keys and returns a JWT + user object
4. FE stores the JWT and user exactly as it does for Google and Microsoft sign-in

**iOS native and web are both supported** — both platforms produce an identity token that this endpoint accepts.

## Request

```json
{
  "id_token": "<apple_identity_token>"
}
```

| Field | Type | Required |
|-------|------|----------|
| `id_token` | string | Yes — the identity token from Apple |

### Getting the id_token (iOS — Swift)

```swift
import AuthenticationServices

class SignInCoordinator: NSObject, ASAuthorizationControllerDelegate {
    func startSignIn() {
        let provider = ASAuthorizationAppleIDProvider()
        let request  = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.performRequests()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard
            let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let tokenData   = credential.identityToken,
            let idToken     = String(data: tokenData, encoding: .utf8)
        else { return }

        // POST to /api/v1/auth/apple with { id_token: idToken }
    }
}
```

**Note:** Apple only provides `fullName` on the first sign-in. The backend derives a display name from the email address — no need to send the name separately.

### Getting the id_token (Web — Apple JS SDK)

Include Apple's JS SDK in your HTML:

```html
<script src="https://appleid.cdn-apple.com/appleauth/static/jsapi/appleid/1/en_US/appleid.auth.js"></script>
```

Configure and sign in:

```js
AppleID.auth.init({
  clientId: '<YOUR_SERVICE_ID>',      // Web Service ID from Apple Developer Console
  scope: 'name email',
  redirectURI: window.location.origin, // must match what's registered in Apple Console
  usePopup: true,
})

const response = await AppleID.auth.signIn()
const idToken  = response.authorization.id_token
// POST to /api/v1/auth/apple with { id_token: idToken }
```

### Getting the id_token (React Native — react-native-apple-authentication)

```bash
npm install @invertase/react-native-apple-authentication
```

```js
import appleAuth from '@invertase/react-native-apple-authentication'

const appleAuthRequestResponse = await appleAuth.performRequest({
  requestedOperation: appleAuth.Operation.LOGIN,
  requestedScopes: [appleAuth.Scope.EMAIL, appleAuth.Scope.FULL_NAME],
})

const { identityToken } = appleAuthRequestResponse
// POST to /api/v1/auth/apple with { id_token: identityToken }
```

This library handles both iOS (native) and Android (web fallback) automatically.

## Response — 200 OK

Same shape as Google, Microsoft, Facebook, and email/password sign-in.

```json
{
  "jwt": "eyJhbGciOiJIUzI1NiJ9...",
  "user": {
    "id": 42,
    "first_name": "ion",
    "last_name": null,
    "email": "ion@icloud.com",
    "avatar_url": null,
    "phone_number": null,
    "church_name": null,
    "city": null,
    "language": null,
    "can_change_email": false
  }
}
```

### Fields to note

| Field | Notes |
|-------|-------|
| `first_name` | Derived from the email prefix (e.g. `ion` from `ion@icloud.com`); `"Apple"` for Hide My Email relay addresses |
| `last_name` | Always `null` at account creation — set via `PATCH /api/v1/auth/me` |
| `avatar_url` | Always `null` — Apple does not provide a profile photo |
| `can_change_email` | Always `false` for Apple-only accounts — hide the email field on the profile edit screen |
| `language` | `null` at first sign-in — set via `PATCH /api/v1/auth/me` |

## Error Responses

| Status | Body | When |
|--------|------|------|
| `422` | `{ "error": "id_token is required" }` | `id_token` param is missing or blank |
| `401` | `{ "error": "Invalid Apple token" }` | Token is expired, invalid signature, wrong audience, or email not verified |

Both error strings are localised — pass `language` in the request body to receive Romanian errors.

## Language param

```json
{
  "id_token": "<token>",
  "language": "ro-RO"
}
```

## Notes

- The JWT format and expiry (30 days) are identical to all other sign-in methods.
- If an Apple user has a Hide My Email relay address (`@privaterelay.appleid.com`), that relay address is stored as their email. It will not be automatically linked to an existing account created with the real email.
- If a user signs in with Apple after previously registering with email/password using the same email, the Apple identity is linked automatically — no duplicate account.
- `can_change_email` is always `false` for Apple-only accounts. If the user later adds an email/password identity, it becomes `true`.
- Apple Sign-In requires your app to be configured in Apple Developer Console with an App ID (iOS) and a Service ID (web). Update `auth.apple_bundle_ids` in Rails credentials with the real values once configured.
```

- [ ] **Step 12: Commit**

```bash
git add config/locales/en.yml config/locales/ro.yml config/credentials.yml.enc \
        config/routes.rb \
        app/controllers/api/v1/auth/apples_controller.rb \
        spec/requests/api/v1/auth/apple_spec.rb \
        docs/auth/apple-signin-integration.md
git commit -m "Add POST /api/v1/auth/apple endpoint"
```

- [ ] **Step 13: Push**

```bash
git push origin main
```
