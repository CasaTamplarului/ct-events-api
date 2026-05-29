# Email/Password Authentication Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add email/password registration and login to the CT Events API, using the existing JWT and multi-provider identity infrastructure built for Google Sign-In.

**Architecture:** Two new endpoints — `POST /api/v1/auth/registration` (creates user + identity, backfills attendees, returns JWT) and `POST /api/v1/auth/session` (authenticates with `has_secure_password`, returns JWT). Rate limiting via `rack-attack` (5 req/IP/min on both endpoints). Email users get a `UserIdentity` row with `provider: "email"`, `uid: email`. The `me` and `google` endpoints are updated to return the expanded user shape including `phone_number`, `church_name`, and `city`.

**Tech Stack:** Rails 8.1 API, PostgreSQL 17, `has_secure_password` (existing on `User`), `jwt` gem (existing), `JwtService` (existing), `rack-attack` gem (new).

---

## Context

This builds on the Google Sign-In implementation. Key existing pieces:

- `app/models/user.rb` — `has_secure_password(validations: false)`, `normalizes :email`, unique index on `email`
- `app/models/user_identity.rb` — `belongs_to :user`, unique index on `[provider, uid]`
- `app/services/jwt_service.rb` — `JwtService.encode(user_id)` / `JwtService.decode(token)`
- `app/controllers/concerns/authenticatable.rb` — `authenticate_user!` reads Bearer token, sets `@current_user`
- `app/controllers/api/v1/auth/googles_controller.rb` — shows the find-or-create + backfill pattern to follow
- `spec/requests/api/v1/auth/google_spec.rb` — shows the request spec style to follow

All new controllers inherit from `ActionController::API` and live in `module Api::V1::Auth`.

---

## Files

**Created:**
- `db/migrate/20260529000001_add_profile_fields_to_users.rb`
- `config/initializers/rack_attack.rb`
- `app/controllers/api/v1/auth/registrations_controller.rb`
- `app/controllers/api/v1/auth/sessions_controller.rb`
- `spec/requests/api/v1/auth/registrations_spec.rb`
- `spec/requests/api/v1/auth/sessions_spec.rb`
- `spec/requests/api/v1/auth/rack_attack_spec.rb`

**Modified:**
- `Gemfile` — add `rack-attack`
- `config/application.rb` — insert Rack::Attack middleware
- `config/routes.rb` — add registration and session resources
- `app/models/user.rb` — remove `last_name` presence validation (optional for email registration)
- `app/controllers/api/v1/auth/me_controller.rb` — return `phone_number`, `church_name`, `city`
- `app/controllers/api/v1/auth/googles_controller.rb` — return `phone_number`, `church_name`, `city`
- `spec/requests/api/v1/auth/me_spec.rb` — assert new fields are present

---

## Task 1: Migration — add profile columns and make last_name optional

**Files:**
- Create: `db/migrate/20260529000001_add_profile_fields_to_users.rb`
- Modify: `app/models/user.rb`
- Test: `spec/models/user_spec.rb`

- [ ] **Step 1: Write the failing model spec**

Add to `spec/models/user_spec.rb` after the existing `describe 'associations'` block:

```ruby
describe 'profile fields' do
  it 'accepts church_name and city' do
    user = build(:user, church_name: 'Betel', city: 'Cluj')
    expect(user).to be_valid
    expect(user.church_name).to eq('Betel')
    expect(user.city).to eq('Cluj')
  end

  it 'is valid without last_name' do
    user = build(:user, last_name: nil)
    expect(user).to be_valid
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

```bash
bin/rspec spec/models/user_spec.rb --format documentation
```

Expected: FAIL — `church_name` unknown attribute, `last_name` presence violation.

- [ ] **Step 3: Write the migration**

Create `db/migrate/20260529000001_add_profile_fields_to_users.rb`:

```ruby
# frozen_string_literal: true

class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :last_name, true
    add_column :users, :church_name, :string
    add_column :users, :city, :string
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 5: Remove the `last_name` presence validation from the User model**

In `app/models/user.rb`, remove the line:

```ruby
  validates :last_name, presence: true
```

The full model should now look like:

```ruby
# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password(validations: false)

  has_many :attendees, dependent: :nullify
  has_many :user_identities, dependent: :destroy

  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :first_name, presence: true
  validates :email, presence: true, uniqueness: true,
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
end
```

- [ ] **Step 6: Run the spec to verify it passes**

```bash
bin/rspec spec/models/user_spec.rb --format documentation
```

Expected: All examples PASS.

- [ ] **Step 7: Run the full suite to check for regressions**

```bash
bin/rspec --format progress
```

Expected: No failures.

- [ ] **Step 8: Commit**

```bash
git add db/migrate/20260529000001_add_profile_fields_to_users.rb app/models/user.rb spec/models/user_spec.rb db/schema.rb
git commit -m "feat: add church_name, city to users; make last_name optional"
```

---

## Task 2: Add rack-attack gem and configure throttle

**Files:**
- Modify: `Gemfile`
- Modify: `config/application.rb`
- Create: `config/initializers/rack_attack.rb`
- Create: `spec/requests/api/v1/auth/rack_attack_spec.rb`

- [ ] **Step 1: Write the failing throttle spec**

Create `spec/requests/api/v1/auth/rack_attack_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Auth endpoint rate limiting' do
  before do
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
  end

  let(:valid_registration_params) do
    { first_name: 'Ion', email: "ion#{SecureRandom.hex(4)}@example.com", password: 'Password123' }
  end

  def post_registration(params)
    post '/api/v1/auth/registration',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  def post_session(params)
    post '/api/v1/auth/session',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  describe 'POST /api/v1/auth/registration' do
    it 'allows the first 5 requests and blocks the 6th with 429' do
      5.times { post_registration(valid_registration_params.merge(email: "ion#{SecureRandom.hex(4)}@example.com")) }
      post_registration(valid_registration_params.merge(email: "ion#{SecureRandom.hex(4)}@example.com"))

      expect(response).to have_http_status(:too_many_requests)
      expect(json['error']).to eq('Too many requests. Please try again later.')
    end
  end

  describe 'POST /api/v1/auth/session' do
    it 'allows the first 5 requests and blocks the 6th with 429' do
      6.times { post_session({ email: 'x@example.com', password: 'wrong' }) }

      expect(response).to have_http_status(:too_many_requests)
      expect(json['error']).to eq('Too many requests. Please try again later.')
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

```bash
bin/rspec spec/requests/api/v1/auth/rack_attack_spec.rb --format documentation
```

Expected: FAIL — routing error (controllers don't exist yet) or 404.

- [ ] **Step 3: Add rack-attack to Gemfile**

In `Gemfile`, add after the `# Google Sign-In` block:

```ruby
# Rate limiting
gem 'rack-attack', '~> 6.7'
```

- [ ] **Step 4: Install the gem**

```bash
bundle install
```

- [ ] **Step 5: Add Rack::Attack to the middleware stack**

In `config/application.rb`, add inside the `class Application < Rails::Application` block:

```ruby
config.middleware.use Rack::Attack
```

The full `application.rb` should now look like:

```ruby
# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

Bundler.require(*Rails.groups)

module CtEventsApi
  class Application < Rails::Application
    config.load_defaults 8.0

    config.middleware.use Rack::Attack
  end
end
```

- [ ] **Step 6: Write the rack-attack initializer**

Create `config/initializers/rack_attack.rb`:

```ruby
# frozen_string_literal: true

class Rack::Attack
  AUTH_ENDPOINTS = %w[/api/v1/auth/registration /api/v1/auth/session].freeze

  throttle('auth/ip', limit: 5, period: 1.minute) do |req|
    req.ip if AUTH_ENDPOINTS.include?(req.path) && req.post?
  end

  self.throttled_responder = lambda do |_env|
    body = { error: 'Too many requests. Please try again later.' }.to_json
    [429, { 'Content-Type' => 'application/json' }, [body]]
  end
end
```

The spec will still fail (controllers don't exist). That's expected — proceed to Task 3 and 4 to create them, then re-run this spec.

- [ ] **Step 7: Commit**

```bash
git add Gemfile Gemfile.lock config/application.rb config/initializers/rack_attack.rb spec/requests/api/v1/auth/rack_attack_spec.rb
git commit -m "feat: add rack-attack rate limiting on auth endpoints"
```

---

## Task 3: RegistrationsController

**Files:**
- Create: `app/controllers/api/v1/auth/registrations_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/api/v1/auth/registrations_spec.rb`

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/api/v1/auth/registrations_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/registration' do
  def post_registration(params)
    post '/api/v1/auth/registration',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  let(:valid_params) do
    {
      first_name: 'Ion',
      last_name: 'Popescu',
      email: 'ion@example.com',
      password: 'SecurePass1!'
    }
  end

  context 'with valid required params' do
    it 'returns 201 with a JWT and user data' do
      post_registration(valid_params)

      expect(response).to have_http_status(:created)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@example.com')
      expect(json['user']['first_name']).to eq('Ion')
    end

    it 'creates a User record' do
      expect { post_registration(valid_params) }.to change(User, :count).by(1)
    end

    it 'creates a UserIdentity with provider email' do
      post_registration(valid_params)
      expect(UserIdentity.where(provider: 'email', uid: 'ion@example.com')).to exist
    end

    it 'returns a JWT that decodes to the created user' do
      post_registration(valid_params)
      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(User.find_by(email: 'ion@example.com').id)
    end

    it 'normalizes email to lowercase' do
      post_registration(valid_params.merge(email: 'Ion@EXAMPLE.COM'))
      expect(User.find_by(email: 'ion@example.com')).to be_present
    end

    it 'includes all user profile fields in the response' do
      post_registration(valid_params.merge(phone_number: '+40700000000', church_name: 'Betel', city: 'Cluj'))

      expect(json['user']['phone_number']).to eq('+40700000000')
      expect(json['user']['church_name']).to eq('Betel')
      expect(json['user']['city']).to eq('Cluj')
      expect(json['user'].key?('avatar_url')).to be true
    end

    it 'is valid without optional fields (last_name, phone_number, church_name, city)' do
      post_registration({ first_name: 'Ion', email: 'ion@example.com', password: 'SecurePass1!' })
      expect(response).to have_http_status(:created)
      expect(json['user']['last_name']).to be_nil
    end
  end

  context 'attendee backfill' do
    it 'links existing attendees with matching email to the new user' do
      event = create(:event)
      attendee = create(:attendee, event: event, email_address: 'ion@example.com')

      post_registration(valid_params)

      user = User.find_by(email: 'ion@example.com')
      expect(attendee.reload.user).to eq(user)
    end
  end

  context 'with missing required params' do
    it 'returns 422 when first_name is missing' do
      post_registration(valid_params.except(:first_name))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end

    it 'returns 422 when email is missing' do
      post_registration(valid_params.except(:email))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end

    it 'returns 422 when password is missing' do
      post_registration(valid_params.except(:password))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to be_present
    end
  end

  context 'with an invalid password' do
    it 'returns 422 when password is shorter than 8 characters' do
      post_registration(valid_params.merge(password: 'short'))
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to match(/password/i)
    end
  end

  context 'with a duplicate email' do
    before { create(:user, email: 'ion@example.com') }

    it 'returns 409' do
      post_registration(valid_params)
      expect(response).to have_http_status(:conflict)
      expect(json['error']).to eq('Email is already registered')
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

```bash
bin/rspec spec/requests/api/v1/auth/registrations_spec.rb --format documentation
```

Expected: FAIL — routing error (no route matches POST /api/v1/auth/registration).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside `namespace :auth` add:

```ruby
namespace :auth do
  resource :google, only: :create
  resource :me, only: :show, controller: 'me'
  resource :registration, only: :create
  resource :session, only: :create
end
```

- [ ] **Step 4: Write the controller**

Create `app/controllers/api/v1/auth/registrations_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      class RegistrationsController < ActionController::API
        def create
          if params[:first_name].blank? || params[:email].blank? || params[:password].blank?
            render json: { error: 'first_name, email, and password are required' }, status: :unprocessable_entity
            return
          end

          email = params[:email].to_s.strip.downcase

          if User.exists?(email: email)
            render json: { error: 'Email is already registered' }, status: :conflict
            return
          end

          user = nil
          ActiveRecord::Base.transaction do
            user = User.create!(
              first_name: params[:first_name],
              last_name: params[:last_name].presence,
              email: email,
              password: params[:password],
              phone_number: params[:phone_number].presence,
              church_name: params[:church_name].presence,
              city: params[:city].presence
            )
            user.user_identities.create!(provider: 'email', uid: user.email)
            # rubocop:disable Rails/SkipsModelValidations
            Attendee.where(email_address: user.email).update_all(user_id: user.id)
            # rubocop:enable Rails/SkipsModelValidations
          end

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.first }, status: :unprocessable_entity
        rescue ActiveRecord::RecordNotUnique
          render json: { error: 'Email is already registered' }, status: :conflict
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

- [ ] **Step 5: Run the spec to verify it passes**

```bash
bin/rspec spec/requests/api/v1/auth/registrations_spec.rb --format documentation
```

Expected: All examples PASS.

- [ ] **Step 6: Run rubocop**

```bash
bin/rubocop app/controllers/api/v1/auth/registrations_controller.rb
```

Fix any offenses, then re-run until clean.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/auth/registrations_controller.rb config/routes.rb spec/requests/api/v1/auth/registrations_spec.rb
git commit -m "feat: add email/password registration endpoint"
```

---

## Task 4: SessionsController

**Files:**
- Create: `app/controllers/api/v1/auth/sessions_controller.rb`
- Create: `spec/requests/api/v1/auth/sessions_spec.rb`

(Routes were added in Task 3.)

- [ ] **Step 1: Write the failing request spec**

Create `spec/requests/api/v1/auth/sessions_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'POST /api/v1/auth/session' do
  def post_session(params)
    post '/api/v1/auth/session',
         params: params.to_json,
         headers: { 'Content-Type' => 'application/json' }
  end

  let!(:user) do
    create(:user,
           email: 'ion@example.com',
           password: 'SecurePass1!',
           first_name: 'Ion',
           last_name: 'Popescu',
           phone_number: '+40700000000',
           church_name: 'Betel',
           city: 'Cluj')
  end

  context 'with valid credentials' do
    it 'returns 200 with a JWT and user data' do
      post_session({ email: 'ion@example.com', password: 'SecurePass1!' })

      expect(response).to have_http_status(:ok)
      expect(json['jwt']).to be_present
      expect(json['user']['email']).to eq('ion@example.com')
      expect(json['user']['first_name']).to eq('Ion')
    end

    it 'returns a JWT that decodes to the correct user_id' do
      post_session({ email: 'ion@example.com', password: 'SecurePass1!' })
      user_id = JwtService.decode(json['jwt'])
      expect(user_id).to eq(user.id)
    end

    it 'returns all user profile fields in the response' do
      post_session({ email: 'ion@example.com', password: 'SecurePass1!' })

      expect(json['user']['phone_number']).to eq('+40700000000')
      expect(json['user']['church_name']).to eq('Betel')
      expect(json['user']['city']).to eq('Cluj')
      expect(json['user'].key?('avatar_url')).to be true
    end

    it 'is case-insensitive for email' do
      post_session({ email: 'ION@EXAMPLE.COM', password: 'SecurePass1!' })
      expect(response).to have_http_status(:ok)
    end
  end

  context 'with a wrong password' do
    it 'returns 401 with a generic error' do
      post_session({ email: 'ion@example.com', password: 'WrongPassword' })
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid email or password')
    end
  end

  context 'with an unknown email' do
    it 'returns 401 with a generic error' do
      post_session({ email: 'nobody@example.com', password: 'SecurePass1!' })
      expect(response).to have_http_status(:unauthorized)
      expect(json['error']).to eq('Invalid email or password')
    end
  end

  context 'with missing params' do
    it 'returns 422 when email is missing' do
      post_session({ password: 'SecurePass1!' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('email and password are required')
    end

    it 'returns 422 when password is missing' do
      post_session({ email: 'ion@example.com' })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(json['error']).to eq('email and password are required')
    end
  end
end
```

- [ ] **Step 2: Run the spec to verify it fails**

```bash
bin/rspec spec/requests/api/v1/auth/sessions_spec.rb --format documentation
```

Expected: FAIL — routing error (no controller).

- [ ] **Step 3: Write the controller**

Create `app/controllers/api/v1/auth/sessions_controller.rb`:

```ruby
# frozen_string_literal: true

module Api
  module V1
    module Auth
      class SessionsController < ActionController::API
        def create
          if params[:email].blank? || params[:password].blank?
            render json: { error: 'email and password are required' }, status: :unprocessable_entity
            return
          end

          user = User.find_by(email: params[:email].to_s.strip.downcase)
          authenticated = user&.authenticate(params[:password])

          unless authenticated
            render json: { error: 'Invalid email or password' }, status: :unauthorized
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

- [ ] **Step 4: Run the spec to verify it passes**

```bash
bin/rspec spec/requests/api/v1/auth/sessions_spec.rb --format documentation
```

Expected: All examples PASS.

- [ ] **Step 5: Run the throttle spec now that both controllers exist**

```bash
bin/rspec spec/requests/api/v1/auth/rack_attack_spec.rb --format documentation
```

Expected: All examples PASS.

- [ ] **Step 6: Run rubocop**

```bash
bin/rubocop app/controllers/api/v1/auth/sessions_controller.rb
```

Fix any offenses, then re-run until clean.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/api/v1/auth/sessions_controller.rb spec/requests/api/v1/auth/sessions_spec.rb
git commit -m "feat: add email/password session (login) endpoint"
```

---

## Task 5: Extend me and google endpoints with new user fields

The `GET /api/v1/auth/me` and the `POST /api/v1/auth/google` responses currently return only `id`, `first_name`, `last_name`, `email`, `avatar_url`. They must also return `phone_number`, `church_name`, and `city` for consistency with the new registration/session responses.

**Files:**
- Modify: `app/controllers/api/v1/auth/me_controller.rb`
- Modify: `app/controllers/api/v1/auth/googles_controller.rb`
- Modify: `spec/requests/api/v1/auth/me_spec.rb`

- [ ] **Step 1: Update the me spec to assert the new fields**

In `spec/requests/api/v1/auth/me_spec.rb`, update the `'includes all user profile fields in response'` example:

Replace:
```ruby
it 'includes all user profile fields in response' do
  get_me(headers: { 'Authorization' => "Bearer #{token}" })

  expect(json['id']).to eq(user.id)
  expect(json['email']).to eq('ion@example.com')
  expect(json['first_name']).to eq('Ion')
  expect(json['last_name']).to eq('Popescu')
  expect(json.key?('avatar_url')).to be true
end
```

With:
```ruby
it 'includes all user profile fields in response' do
  get_me(headers: { 'Authorization' => "Bearer #{token}" })

  expect(json['id']).to eq(user.id)
  expect(json['email']).to eq('ion@example.com')
  expect(json['first_name']).to eq('Ion')
  expect(json['last_name']).to eq('Popescu')
  expect(json.key?('avatar_url')).to be true
  expect(json.key?('phone_number')).to be true
  expect(json.key?('church_name')).to be true
  expect(json.key?('city')).to be true
end
```

- [ ] **Step 2: Run the me spec to verify the new assertions fail**

```bash
bin/rspec spec/requests/api/v1/auth/me_spec.rb --format documentation
```

Expected: FAIL on the profile fields example.

- [ ] **Step 3: Update MeController to include new fields**

Replace the `show` action in `app/controllers/api/v1/auth/me_controller.rb`:

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
            avatar_url: current_user.avatar_url,
            phone_number: current_user.phone_number,
            church_name: current_user.church_name,
            city: current_user.city
          }
        end
      end
    end
  end
end
```

- [ ] **Step 4: Run the me spec to verify it passes**

```bash
bin/rspec spec/requests/api/v1/auth/me_spec.rb --format documentation
```

Expected: All examples PASS.

- [ ] **Step 5: Update GooglesController#user_json to include new fields**

In `app/controllers/api/v1/auth/googles_controller.rb`, replace the `user_json` private method:

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
    city: user.city
  }
end
```

- [ ] **Step 6: Run the google spec to verify it still passes**

```bash
bin/rspec spec/requests/api/v1/auth/google_spec.rb --format documentation
```

Expected: All examples PASS.

- [ ] **Step 7: Run the full test suite**

```bash
bin/rspec --format progress
```

Expected: No failures.

- [ ] **Step 8: Run rubocop on all modified files**

```bash
bin/rubocop app/controllers/api/v1/auth/me_controller.rb app/controllers/api/v1/auth/googles_controller.rb
```

Fix any offenses, then re-run until clean.

- [ ] **Step 9: Commit**

```bash
git add app/controllers/api/v1/auth/me_controller.rb app/controllers/api/v1/auth/googles_controller.rb spec/requests/api/v1/auth/me_spec.rb
git commit -m "feat: include phone_number, church_name, city in all auth user responses"
```
