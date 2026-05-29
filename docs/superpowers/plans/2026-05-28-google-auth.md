# Google Sign-In Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Google Sign-In to the Rails API with a multi-provider identity model, returning stateless JWTs, and linking new users to their past attendee records by email.

**Architecture:** FE handles Google OAuth client-side and sends a Google ID token to `POST /api/v1/auth/google`. The API verifies the token via the `google-id-token` gem, finds or creates a `User` + `UserIdentity`, backfills any matching `Attendee` records, and returns a signed JWT. `GET /api/v1/auth/me` is a protected endpoint that decodes the JWT and returns the user profile.

**Tech Stack:** Rails 8.1, RSpec, FactoryBot, `jwt` gem, `google-id-token` gem, PostgreSQL 17.

---

## File Map

| File | Status | Responsibility |
|---|---|---|
| `db/migrate/..._alter_users_for_oauth.rb` | Create | Make `password_digest` nullable, add `avatar_url` |
| `db/migrate/..._create_user_identities.rb` | Create | New provider identity table |
| `app/models/user_identity.rb` | Create | `belongs_to :user`, validates provider + uid |
| `spec/factories/user_identities.rb` | Create | Factory for UserIdentity |
| `spec/factories/users.rb` | Create | Factory for User |
| `app/models/user.rb` | Modify | Add `user_identities`, fix `has_secure_password` |
| `spec/models/user_identity_spec.rb` | Create | Model spec for UserIdentity |
| `app/services/jwt_service.rb` | Create | `encode(user_id)` / `decode(token)` |
| `spec/services/jwt_service_spec.rb` | Create | Unit spec for JwtService |
| `app/services/google_auth_service.rb` | Create | Verify Google ID token, return claims hash |
| `spec/services/google_auth_service_spec.rb` | Create | Unit spec with stubbed validator |
| `app/controllers/concerns/authenticatable.rb` | Create | `authenticate_user!` before-action |
| `app/controllers/api/v1/auth/google_controller.rb` | Create | `POST /auth/google` |
| `app/controllers/api/v1/auth/me_controller.rb` | Create | `GET /auth/me` |
| `spec/requests/api/v1/auth/google_spec.rb` | Create | Request spec for Google sign-in |
| `spec/requests/api/v1/auth/me_spec.rb` | Create | Request spec for /me |
| `config/routes.rb` | Modify | Add auth namespace |
| `Gemfile` | Modify | Add `jwt`, `google-id-token` |

---

## Task 1: Add gems

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add the two new gems to Gemfile**

Open `Gemfile` and add after the `gem 'oj'` line:

```ruby
gem 'google-id-token', '~> 1.4'
gem 'jwt', '~> 2.8'
```

- [ ] **Step 2: Install**

```bash
bundle install
```

Expected: both gems appear in `Gemfile.lock`, no errors.

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Add jwt and google-id-token gems"
```

---

## Task 2: Migrations

**Files:**
- Create: `db/migrate/TIMESTAMP_alter_users_for_oauth.rb`
- Create: `db/migrate/TIMESTAMP_create_user_identities.rb`

- [ ] **Step 1: Generate migration to alter users table**

```bash
bin/rails generate migration AlterUsersForOauth
```

- [ ] **Step 2: Write the migration**

Replace the generated file body with:

```ruby
# frozen_string_literal: true

class AlterUsersForOauth < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :password_digest, true
    add_column :users, :avatar_url, :string
  end
end
```

- [ ] **Step 3: Generate migration for user_identities table**

```bash
bin/rails generate migration CreateUserIdentities
```

- [ ] **Step 4: Write the migration**

```ruby
# frozen_string_literal: true

class CreateUserIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :user_identities do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :uid, null: false
      t.timestamps
    end

    add_index :user_identities, %i[provider uid], unique: true
  end
end
```

- [ ] **Step 5: Run migrations**

```bash
bin/rails db:migrate
```

Expected: both migrations appear as `up` in `bin/rails db:migrate:status`.

- [ ] **Step 6: Commit**

```bash
git add db/migrate/ db/schema.rb
git commit -m "Add user_identities table and alter users for OAuth"
```

---

## Task 3: UserIdentity model

**Files:**
- Create: `app/models/user_identity.rb`
- Create: `spec/models/user_identity_spec.rb`
- Create: `spec/factories/user_identities.rb`
- Create: `spec/factories/users.rb`

- [ ] **Step 1: Create the user factory**

Create `spec/factories/users.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
    email { Faker::Internet.unique.email }
    avatar_url { nil }
  end
end
```

- [ ] **Step 2: Create the user_identity factory**

Create `spec/factories/user_identities.rb`:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :user_identity do
    user
    provider { 'google' }
    uid { SecureRandom.hex(16) }
  end
end
```

- [ ] **Step 3: Write the failing model spec**

Create `spec/models/user_identity_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserIdentity do
  it 'has a valid factory' do
    expect(build(:user_identity)).to be_valid
  end

  describe 'validations' do
    subject { build(:user_identity) }

    it { is_expected.to validate_presence_of(:provider) }
    it { is_expected.to validate_presence_of(:uid) }
    it { is_expected.to validate_uniqueness_of(:uid).scoped_to(:provider) }
  end

  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end
end
```

- [ ] **Step 4: Run the failing spec**

```bash
bin/rspec spec/models/user_identity_spec.rb
```

Expected: FAIL — `uninitialized constant UserIdentity`

- [ ] **Step 5: Create the model**

Create `app/models/user_identity.rb`:

```ruby
# frozen_string_literal: true

class UserIdentity < ApplicationRecord
  belongs_to :user

  validates :provider, presence: true
  validates :uid, presence: true, uniqueness: { scope: :provider }
end
```

- [ ] **Step 6: Run the spec again**

```bash
bin/rspec spec/models/user_identity_spec.rb
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/models/user_identity.rb spec/models/user_identity_spec.rb spec/factories/user_identities.rb spec/factories/users.rb
git commit -m "Add UserIdentity model, factory and spec"
```

---

## Task 4: Update User model

**Files:**
- Modify: `app/models/user.rb`

The current `User` model uses `has_secure_password` which automatically adds `validates :password, presence: true, on: :create`. This blocks creating OAuth users who have no password. The fix is `has_secure_password(validations: false)` — it keeps the `password=` setter and `authenticate` method but removes the auto-validations. The existing manual `validates :password, length: { minimum: 8 }, allow_nil: true` continues to enforce minimum length for email/password users.

- [ ] **Step 1: Write a failing spec proving OAuth user creation works**

Add to `spec/models/user_identity_spec.rb` inside `RSpec.describe UserIdentity` (or create a separate `spec/models/user_spec.rb`):

Create `spec/models/user_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe User do
  it 'has a valid factory' do
    expect(build(:user)).to be_valid
  end

  describe 'OAuth user (no password)' do
    it 'is valid without a password' do
      user = build(:user, password: nil, password_digest: nil)
      expect(user).to be_valid
    end
  end

  describe 'associations' do
    it { is_expected.to have_many(:user_identities).dependent(:destroy) }
    it { is_expected.to have_many(:attendees).dependent(:nullify) }
  end

  describe 'email normalization' do
    it 'strips and downcases email on save' do
      user = create(:user, email: '  Test@EXAMPLE.COM  ')
      expect(user.reload.email).to eq('test@example.com')
    end
  end
end
```

- [ ] **Step 2: Run the failing spec**

```bash
bin/rspec spec/models/user_spec.rb
```

Expected: FAIL — `OAuth user is valid without a password` fails because `has_secure_password` enforces password presence on create.

- [ ] **Step 3: Update the User model**

Replace the contents of `app/models/user.rb` with:

```ruby
# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password(validations: false)

  has_many :attendees, dependent: :nullify
  has_many :user_identities, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :first_name, presence: true
  validates :last_name, presence: true
  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
end
```

- [ ] **Step 4: Run the spec**

```bash
bin/rspec spec/models/user_spec.rb
```

Expected: all green.

- [ ] **Step 5: Run the full suite to catch regressions**

```bash
bin/rspec
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add app/models/user.rb spec/models/user_spec.rb
git commit -m "Update User model for multi-provider OAuth support"
```

---

## Task 5: JwtService

**Files:**
- Create: `app/services/jwt_service.rb`
- Create: `spec/services/jwt_service_spec.rb`

First, add `auth.jwt_secret` to Rails encrypted credentials. Generate a secret and add it:

- [ ] **Step 1: Generate a JWT secret**

```bash
openssl rand -hex 64
```

Copy the output.

- [ ] **Step 2: Add the secret to encrypted credentials**

```bash
bin/rails credentials:edit
```

Add this block (use the hex string from Step 1):

```yaml
auth:
  jwt_secret: PASTE_HEX_STRING_HERE
  google_client_id: PASTE_GOOGLE_OAUTH_CLIENT_ID_HERE
```

Save and close the editor. The `google_client_id` is the client ID from your Google Cloud Console OAuth credentials — you can set it to a placeholder now and fill it in later.

- [ ] **Step 3: Write the failing spec**

Create `spec/services/jwt_service_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe JwtService do
  let(:user_id) { 42 }

  describe '.encode and .decode' do
    it 'encodes a user_id into a JWT and decodes it back' do
      token = described_class.encode(user_id)
      expect(described_class.decode(token)).to eq(user_id)
    end
  end

  describe '.decode' do
    it 'raises JWT::DecodeError for a malformed token' do
      expect { described_class.decode('not.a.token') }.to raise_error(JWT::DecodeError)
    end

    it 'raises JWT::ExpiredSignature for an expired token' do
      secret = Rails.application.credentials.dig(:auth, :jwt_secret)
      expired_token = JWT.encode({ user_id: user_id, exp: 1.second.ago.to_i }, secret, 'HS256')
      expect { described_class.decode(expired_token) }.to raise_error(JWT::ExpiredSignature)
    end
  end
end
```

- [ ] **Step 4: Run the failing spec**

```bash
bin/rspec spec/services/jwt_service_spec.rb
```

Expected: FAIL — `uninitialized constant JwtService`

- [ ] **Step 5: Create the service**

Create `app/services/jwt_service.rb`:

```ruby
# frozen_string_literal: true

class JwtService
  ALGORITHM = 'HS256'
  EXPIRY = 30.days

  def self.encode(user_id)
    payload = { user_id: user_id, exp: EXPIRY.from_now.to_i }
    JWT.encode(payload, secret, ALGORITHM)
  end

  def self.decode(token)
    decoded = JWT.decode(token, secret, true, { algorithm: ALGORITHM })
    decoded.first['user_id']
  end

  def self.secret
    Rails.application.credentials.dig(:auth, :jwt_secret)
  end
  private_class_method :secret
end
```

- [ ] **Step 6: Run the spec**

```bash
bin/rspec spec/services/jwt_service_spec.rb
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/services/jwt_service.rb spec/services/jwt_service_spec.rb config/credentials.yml.enc
git commit -m "Add JwtService with encode/decode and encrypted jwt_secret"
```

---

## Task 6: GoogleAuthService

**Files:**
- Create: `app/services/google_auth_service.rb`
- Create: `spec/services/google_auth_service_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/services/google_auth_service_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe GoogleAuthService do
  let(:valid_payload) do
    {
      'sub' => 'google-uid-123',
      'email' => 'ion@example.com',
      'given_name' => 'Ion',
      'family_name' => 'Popescu',
      'picture' => 'https://lh3.googleusercontent.com/photo.jpg'
    }
  end

  describe '.call' do
    context 'with a valid Google ID token' do
      before do
        allow_any_instance_of(GoogleIDToken::Validator)
          .to receive(:check)
          .and_return(valid_payload)
      end

      it 'returns the extracted user claims' do
        result = described_class.call('valid.id.token')

        expect(result).to eq(
          uid: 'google-uid-123',
          email: 'ion@example.com',
          first_name: 'Ion',
          last_name: 'Popescu',
          avatar_url: 'https://lh3.googleusercontent.com/photo.jpg'
        )
      end
    end

    context 'with an invalid or expired Google ID token' do
      before do
        allow_any_instance_of(GoogleIDToken::Validator)
          .to receive(:check)
          .and_raise(GoogleIDToken::ValidationError, 'token expired')
      end

      it 'raises InvalidTokenError' do
        expect { described_class.call('bad.token') }
          .to raise_error(GoogleAuthService::InvalidTokenError, 'token expired')
      end
    end
  end
end
```

- [ ] **Step 2: Run the failing spec**

```bash
bin/rspec spec/services/google_auth_service_spec.rb
```

Expected: FAIL — `uninitialized constant GoogleAuthService`

- [ ] **Step 3: Create the service**

Create `app/services/google_auth_service.rb`:

```ruby
# frozen_string_literal: true

require 'google-id-token'

class GoogleAuthService
  InvalidTokenError = Class.new(StandardError)

  def self.call(id_token)
    client_id = Rails.application.credentials.dig(:auth, :google_client_id)
    validator = GoogleIDToken::Validator.new
    payload = validator.check(id_token, client_id)

    {
      uid: payload['sub'],
      email: payload['email'],
      first_name: payload['given_name'].to_s,
      last_name: payload['family_name'].to_s,
      avatar_url: payload['picture']
    }
  rescue GoogleIDToken::ValidationError => e
    raise InvalidTokenError, e.message
  end
end
```

- [ ] **Step 4: Run the spec**

```bash
bin/rspec spec/services/google_auth_service_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/services/google_auth_service.rb spec/services/google_auth_service_spec.rb
git commit -m "Add GoogleAuthService with stubbed spec"
```

---

## Task 7: Authenticatable concern

**Files:**
- Create: `app/controllers/concerns/authenticatable.rb`

The concern reads the JWT from `Authorization: Bearer <token>`, decodes it, and sets `@current_user`. Any controller can call `before_action :authenticate_user!` to protect an endpoint.

- [ ] **Step 1: Create the concern**

There is no separate failing spec for this concern — it is covered by the `GET /auth/me` request spec in Task 9. Create it now so Task 8 and 9 can use it.

Create `app/controllers/concerns/authenticatable.rb`:

```ruby
# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user
  end

  def authenticate_user!
    token = request.headers['Authorization']&.split(' ')&.last
    return render json: { error: 'Unauthorized' }, status: :unauthorized if token.blank?

    user_id = JwtService.decode(token)
    @current_user = User.find_by(id: user_id)
    render json: { error: 'Unauthorized' }, status: :unauthorized unless @current_user
  rescue JWT::DecodeError
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end
end
```

- [ ] **Step 2: Commit**

```bash
git add app/controllers/concerns/authenticatable.rb
git commit -m "Add Authenticatable concern for JWT-based auth"
```

---

## Task 8: Google sign-in endpoint

**Files:**
- Create: `app/controllers/api/v1/auth/google_controller.rb`
- Create: `spec/requests/api/v1/auth/google_spec.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Add the routes**

Open `config/routes.rb` and update it to:

```ruby
# frozen_string_literal: true

Rails.application.routes.draw do
  apipie

  get '_healthcheck', to: 'healthcheck#index'

  namespace :api do
    namespace :v1 do
      namespace :auth do
        resource :google, only: :create
        resource :me, only: :show
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

Verify routes are correct:

```bash
bin/rails routes | grep auth
```

Expected output includes:
```
POST   /api/v1/auth/google  api/v1/auth/google#create
GET    /api/v1/auth/me      api/v1/auth/me#show
```

- [ ] **Step 2: Write the failing request spec**

Create `spec/requests/api/v1/auth/google_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/google' do
  let(:google_payload) do
    {
      'sub' => 'google-uid-123',
      'email' => 'ion@example.com',
      'given_name' => 'Ion',
      'family_name' => 'Popescu',
      'picture' => 'https://lh3.googleusercontent.com/photo.jpg'
    }
  end

  def post_google(id_token: 'valid.token')
    post '/api/v1/auth/google',
         params: { id_token: id_token }.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  context 'with a valid Google token' do
    before do
      allow_any_instance_of(GoogleIDToken::Validator)
        .to receive(:check)
        .and_return(google_payload)
    end

    it 'returns 200 with a JWT and user data' do
      post_google

      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@example.com')
      expect(json['user']['first_name']).to eq('Ion')
      expect(json['user']['last_name']).to eq('Popescu')
    end

    it 'creates a new user on first sign-in' do
      expect { post_google }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity for the new user' do
      post_google
      expect(UserIdentity.where(provider: 'google', uid: 'google-uid-123')).to exist
    end

    it 'returns the same user on subsequent sign-ins (idempotent)' do
      post_google
      expect { post_google }.not_to change(User, :count)
      expect(response).to have_http_status(:ok)
    end

    it 'links an existing user account that has the same email' do
      existing_user = create(:user, email: 'ion@example.com')
      post_google

      expect(User.count).to eq(1)
      expect(UserIdentity.find_by(provider: 'google', uid: 'google-uid-123').user).to eq(existing_user)
    end

    it 'backfills user_id on attendees matching the email' do
      event = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')

      post_google

      user = User.find_by(email: 'ion@example.com')
      expect(attendee.reload.user).to eq(user)
    end

    it 'returns a JWT that decodes to the correct user_id' do
      post_google

      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(User.find_by(email: 'ion@example.com').id)
    end
  end

  context 'with a missing id_token param' do
    it 'returns 422' do
      post '/api/v1/auth/google',
           params: {}.to_json,
           headers: { 'Content-Type' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end
  end

  context 'with an invalid Google token' do
    before do
      allow_any_instance_of(GoogleIDToken::Validator)
        .to receive(:check)
        .and_raise(GoogleIDToken::ValidationError, 'invalid token')
    end

    it 'returns 401' do
      post_google(id_token: 'bad.token')

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid Google token')
    end
  end
end
```

- [ ] **Step 3: Run the failing spec**

```bash
bin/rspec spec/requests/api/v1/auth/google_spec.rb
```

Expected: FAIL — `ActionController::RoutingError` or `uninitialized constant` errors.

- [ ] **Step 4: Create the controller**

Create `app/controllers/api/v1/auth/google_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      class GoogleController < ActionController::API
        def create
          return render json: { error: 'id_token is required' }, status: :unprocessable_entity if params[:id_token].blank?

          google_data = GoogleAuthService.call(params[:id_token])
          user = find_or_create_user(google_data)
          jwt = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue GoogleAuthService::InvalidTokenError
          render json: { error: 'Invalid Google token' }, status: :unauthorized
        end

        private

        def find_or_create_user(google_data)
          identity = UserIdentity.find_by(provider: 'google', uid: google_data[:uid])
          return identity.user if identity

          user = User.find_by(email: google_data[:email])
          if user
            user.user_identities.create!(provider: 'google', uid: google_data[:uid])
            user.update(avatar_url: google_data[:avatar_url])
            return user
          end

          ActiveRecord::Base.transaction do
            user = User.create!(
              first_name: google_data[:first_name],
              last_name: google_data[:last_name],
              email: google_data[:email],
              avatar_url: google_data[:avatar_url]
            )
            user.user_identities.create!(provider: 'google', uid: google_data[:uid])
            Attendee.where(email_address: google_data[:email]).update_all(user_id: user.id)
            user
          end
        end

        def user_json(user)
          {
            id: user.id,
            first_name: user.first_name,
            last_name: user.last_name,
            email: user.email,
            avatar_url: user.avatar_url
          }
        end
      end
    end
  end
end
```

- [ ] **Step 5: Run the spec**

```bash
bin/rspec spec/requests/api/v1/auth/google_spec.rb
```

Expected: all green.

- [ ] **Step 6: Commit**

```bash
git add config/routes.rb app/controllers/api/v1/auth/google_controller.rb spec/requests/api/v1/auth/google_spec.rb
git commit -m "Add POST /api/v1/auth/google endpoint"
```

---

## Task 9: Me endpoint

**Files:**
- Create: `app/controllers/api/v1/auth/me_controller.rb`
- Create: `spec/requests/api/v1/auth/me_spec.rb`

- [ ] **Step 1: Write the failing spec**

Create `spec/requests/api/v1/auth/me_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/auth/me' do
  let(:user) { create(:user, first_name: 'Ion', last_name: 'Popescu', email: 'ion@example.com') }
  let(:token) { JwtService.encode(user.id) }

  def get_me(headers: {})
    get '/api/v1/auth/me', headers: { 'Content-Type' => 'application/json' }.merge(headers)
  end

  context 'with a valid JWT' do
    it 'returns 200 with the user profile' do
      get_me(headers: { 'Authorization' => "Bearer #{token}" })

      expect(response).to have_http_status(:ok)
      expect(json['id']).to eq(user.id)
      expect(json['email']).to eq('ion@example.com')
      expect(json['first_name']).to eq('Ion')
      expect(json['last_name']).to eq('Popescu')
    end
  end

  context 'with no Authorization header' do
    it 'returns 401' do
      get_me

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Unauthorized')
    end
  end

  context 'with a malformed token' do
    it 'returns 401' do
      get_me(headers: { 'Authorization' => 'Bearer not.a.real.token' })

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Unauthorized')
    end
  end

  context 'with an expired token' do
    it 'returns 401' do
      secret = Rails.application.credentials.dig(:auth, :jwt_secret)
      expired_token = JWT.encode({ user_id: user.id, exp: 1.second.ago.to_i }, secret, 'HS256')

      get_me(headers: { 'Authorization' => "Bearer #{expired_token}" })

      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Unauthorized')
    end
  end
end
```

- [ ] **Step 2: Run the failing spec**

```bash
bin/rspec spec/requests/api/v1/auth/me_spec.rb
```

Expected: FAIL — controller not found.

- [ ] **Step 3: Create the controller**

Create `app/controllers/api/v1/auth/me_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      class MeController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!

        def show
          render json: {
            id: current_user.id,
            first_name: current_user.first_name,
            last_name: current_user.last_name,
            email: current_user.email,
            avatar_url: current_user.avatar_url
          }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec**

```bash
bin/rspec spec/requests/api/v1/auth/me_spec.rb
```

Expected: all green.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rspec
```

Expected: all green, no regressions.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/auth/me_controller.rb spec/requests/api/v1/auth/me_spec.rb
git commit -m "Add GET /api/v1/auth/me endpoint"
```
