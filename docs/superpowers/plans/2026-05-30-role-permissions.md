# Role Permissions System — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `role` (admin/volunteer/attendee) to users with a `can?` permission helper, a `require_permission!` controller guard, role+permissions in the `/me` response, and the role field configured as a dropdown in Directus.

**Architecture:** A `role` string column (DB default `'attendee'`) is added to `users`. The permission matrix is a frozen Ruby constant in `User`; `user.can?(:permission)` looks it up. The `Authenticatable` concern gains `require_permission!` for controllers to guard future endpoints. The `me` endpoint returns `role` and the full permissions hash.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec + FactoryBot, Directus 11.5 (REST API at `localhost:8091`)

---

## File Map

| File | Action |
|---|---|
| `db/migrate/<ts>_add_role_to_users.rb` | Create — add `role` column |
| `app/models/user.rb` | Modify — defaults, constants, validates, `can?` |
| `spec/factories/users.rb` | Modify — explicit `role` default in factory |
| `config/locales/en.yml` | Modify — add `auth.errors.forbidden` |
| `config/locales/ro.yml` | Modify — add `auth.errors.forbidden` |
| `app/controllers/concerns/authenticatable.rb` | Modify — add `require_permission!` |
| `app/controllers/api/v1/auth/me_controller.rb` | Modify — `role` + `permissions` in `user_json` |
| `spec/models/user_spec.rb` | Modify — role validation, `can?` tests |
| `spec/requests/concerns/require_permission_spec.rb` | Create — integration test for `require_permission!` |
| `spec/requests/api/v1/auth/me_spec.rb` | Modify — assert role + permissions in response |

---

## Task 1: Add role column migration

**Files:**
- Create: `db/migrate/<timestamp>_add_role_to_users.rb`

- [ ] **Step 1: Generate the migration**

```bash
cd /path/to/ct-events-api
bin/rails generate migration AddRoleToUsers
```

Expected output: `invoke  active_record` / `create    db/migrate/YYYYMMDDHHMMSS_add_role_to_users.rb`

- [ ] **Step 2: Fill in the migration body**

Open the generated file and replace its contents with:

```ruby
# frozen_string_literal: true

class AddRoleToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :role, :string, null: false, default: "attendee"
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected output: `== AddRoleToUsers: migrating ==========` / `-- add_column(:users, :role, :string, ...)` / `== AddRoleToUsers: migrated`

- [ ] **Step 4: Verify schema**

Check `db/schema.rb` — the `users` table should include:

```ruby
t.string "role", default: "attendee", null: false
```

- [ ] **Step 5: Commit**

```bash
git add db/migrate db/schema.rb
git commit -m "Add role column to users (default: attendee)"
```

---

## Task 2: User model — role constants and can?

**Files:**
- Modify: `app/models/user.rb`
- Modify: `spec/models/user_spec.rb`
- Modify: `spec/factories/users.rb`

- [ ] **Step 1: Write failing tests in user_spec.rb**

Add the following blocks to `spec/models/user_spec.rb`, after the existing `describe 'email preferences'` block:

```ruby
describe 'role' do
  describe 'default' do
    it 'defaults to attendee' do
      user = create(:user)
      expect(user.reload.role).to eq('attendee')
    end
  end

  describe 'validation' do
    it 'is valid with attendee role' do
      expect(build(:user, role: 'attendee')).to be_valid
    end

    it 'is valid with volunteer role' do
      expect(build(:user, role: 'volunteer')).to be_valid
    end

    it 'is valid with admin role' do
      expect(build(:user, role: 'admin')).to be_valid
    end

    it 'is invalid with an unknown role' do
      user = build(:user, role: 'superuser')
      expect(user).not_to be_valid
      expect(user.errors[:role]).to be_present
    end
  end

  describe '#can?' do
    context 'admin role' do
      let(:user) { build(:user, role: 'admin') }

      it { expect(user.can?(:can_check_in_attendees)).to be true }
      it { expect(user.can?(:can_scan_food_stamp)).to be true }
    end

    context 'volunteer role' do
      let(:user) { build(:user, role: 'volunteer') }

      it { expect(user.can?(:can_check_in_attendees)).to be true }
      it { expect(user.can?(:can_scan_food_stamp)).to be true }
    end

    context 'attendee role' do
      let(:user) { build(:user, role: 'attendee') }

      it { expect(user.can?(:can_check_in_attendees)).to be false }
      it { expect(user.can?(:can_scan_food_stamp)).to be false }
    end

    it 'returns false for an unknown permission' do
      expect(build(:user, role: 'admin').can?(:fly_to_moon)).to be false
    end
  end
end
```

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
bin/rspec spec/models/user_spec.rb --format documentation
```

Expected: multiple failures mentioning `undefined method 'can?'` and role validation errors.

- [ ] **Step 3: Update app/models/user.rb**

Replace the file with:

```ruby
# frozen_string_literal: true

class User < ApplicationRecord
  has_secure_password(validations: false, reset_token: false)

  has_many :attendees, dependent: :nullify
  has_many :user_identities, dependent: :destroy
  has_many :passkeys, dependent: :destroy

  ROLES = %w[admin volunteer attendee].freeze

  ROLE_PERMISSIONS = {
    "admin"     => { can_check_in_attendees: true,  can_scan_food_stamp: true  },
    "volunteer" => { can_check_in_attendees: true,  can_scan_food_stamp: true  },
    "attendee"  => { can_check_in_attendees: false, can_scan_food_stamp: false }
  }.freeze

  attribute :role, :string, default: "attendee"

  normalizes :email, with: ->(e) { e&.strip&.downcase }

  scope :active, -> { where(deleted_at: nil) }

  validates :first_name, presence: true
  validates :email, uniqueness: { allow_nil: true },
                    format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :role, inclusion: { in: ROLES }

  def can?(permission)
    ROLE_PERMISSIONS.dig(role, permission) == true
  end
end
```

- [ ] **Step 4: Update spec/factories/users.rb to include explicit role**

Replace the file with:

```ruby
# frozen_string_literal: true

FactoryBot.define do
  factory :user do
    first_name { Faker::Name.first_name }
    last_name  { Faker::Name.last_name }
    email      { Faker::Internet.unique.email }
    avatar_url { nil }
    password   { 'Password1!' }
    role       { 'attendee' }
  end
end
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
bin/rspec spec/models/user_spec.rb --format documentation
```

Expected: all examples pass, including the new role and `can?` examples.

- [ ] **Step 6: Commit**

```bash
git add app/models/user.rb spec/models/user_spec.rb spec/factories/users.rb
git commit -m "Add role constants and can? permission check to User"
```

---

## Task 3: i18n — forbidden error key

**Files:**
- Modify: `config/locales/en.yml`
- Modify: `config/locales/ro.yml`

- [ ] **Step 1: Add the key to en.yml**

In `config/locales/en.yml`, add `forbidden` under `auth.errors` (alongside `unauthorized`):

```yaml
en:
  auth:
    errors:
      unauthorized: "Unauthorized"
      forbidden: "Forbidden"
      # ... rest of existing keys unchanged
```

The full `auth.errors` section after the change:

```yaml
  auth:
    errors:
      unauthorized: "Unauthorized"
      forbidden: "Forbidden"
      email_password_required: "email and password are required"
      invalid_credentials: "Invalid email or password"
      registration_params_required: "first_name, email, and password are required"
      email_taken: "Email is already registered"
      email_google_only: "This email is linked to a Google account. Please sign in with Google."
      id_token_required: "id_token is required"
      invalid_google_token: "Invalid Google token"
      invalid_facebook_token: "Invalid Facebook token"
      invalid_microsoft_token: "Invalid Microsoft token"
      invalid_apple_token: "Invalid Apple token"
      access_token_required: "access_token is required"
      email_required: "email is required"
      token_password_required: "token and password are required"
      invalid_reset_token: "Invalid or expired reset token"
      email_not_changeable_google: "Email cannot be changed on Google accounts"
      current_password_required: "current_password and password are required"
      incorrect_current_password: "Current password is incorrect"
      password_not_changeable_google: "Password cannot be changed on Google accounts"
      invalid_challenge_token: "Invalid or expired challenge"
      passkey_verification_failed: "Passkey verification failed"
      passkey_not_found: "Passkey not found"
      passkey_already_registered: "Passkey already registered"
      slugs_required: "slugs is required"
```

- [ ] **Step 2: Add the key to ro.yml**

In `config/locales/ro.yml`, add `forbidden` under `auth.errors`:

```yaml
ro:
  auth:
    errors:
      unauthorized: "Neautorizat"
      forbidden: "Interzis"
      # ... rest of existing keys unchanged
```

- [ ] **Step 3: Commit (together with Task 4)**

Hold this commit — combine with the authenticatable change in Task 4.

---

## Task 4: Authenticatable — require_permission!

**Files:**
- Modify: `app/controllers/concerns/authenticatable.rb`
- Create: `spec/requests/concerns/require_permission_spec.rb`

- [ ] **Step 1: Write the failing test**

Create `spec/requests/concerns/require_permission_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

class PermissionTestController < ActionController::API
  include Authenticatable

  before_action :authenticate_user!
  before_action { require_permission!(:can_check_in_attendees) }

  def index
    render json: { ok: true }
  end
end

RSpec.describe 'require_permission! (Authenticatable concern)' do
  before(:all) do
    Rails.application.routes.draw do
      get '/spec/permission_check', to: 'permission_test#index'
    end
  end

  after(:all) { Rails.application.reload_routes! }

  let(:attendee)  { create(:user, role: 'attendee') }
  let(:volunteer) { create(:user, role: 'volunteer') }

  def call_endpoint(user)
    get '/spec/permission_check',
        headers: {
          'Authorization'  => "Bearer #{JwtService.encode(user.id)}",
          'Content-Type'   => 'application/json'
        }
  end

  it 'returns 403 Forbidden when user lacks the permission' do
    call_endpoint(attendee)
    expect(response).to have_http_status(:forbidden)
    expect(json['error']).to eq('Forbidden')
  end

  it 'returns 200 OK when user has the permission' do
    call_endpoint(volunteer)
    expect(response).to have_http_status(:ok)
    expect(json['ok']).to be true
  end

  it 'returns 401 Unauthorized when no token is provided' do
    get '/spec/permission_check', headers: { 'Content-Type' => 'application/json' }
    expect(response).to have_http_status(:unauthorized)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rspec spec/requests/concerns/require_permission_spec.rb --format documentation
```

Expected: failures with `undefined method 'require_permission!'`.

- [ ] **Step 3: Add require_permission! to the Authenticatable concern**

Replace `app/controllers/concerns/authenticatable.rb` with:

```ruby
# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user
  end

  def authenticate_user!
    token = request.headers['Authorization']&.split&.last
    return render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized if token.blank?

    user_id = JwtService.decode(token)
    @current_user = User.active.find_by(id: user_id)
    render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized unless @current_user
  rescue JWT::DecodeError
    render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized
  end

  def require_permission!(permission)
    return if current_user&.can?(permission)

    render json: { error: I18n.t('auth.errors.forbidden') }, status: :forbidden
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rspec spec/requests/concerns/require_permission_spec.rb --format documentation
```

Expected: all 3 examples pass.

- [ ] **Step 5: Commit locales + authenticatable together**

```bash
git add config/locales/en.yml config/locales/ro.yml \
        app/controllers/concerns/authenticatable.rb \
        spec/requests/concerns/require_permission_spec.rb
git commit -m "Add require_permission! to Authenticatable and forbidden i18n key"
```

---

## Task 5: Me controller — role and permissions in response

**Files:**
- Modify: `app/controllers/api/v1/auth/me_controller.rb`
- Modify: `spec/requests/api/v1/auth/me_spec.rb`

- [ ] **Step 1: Write the failing tests**

In `spec/requests/api/v1/auth/me_spec.rb`, add two examples inside the existing `describe 'GET /api/v1/auth/me'` > `context 'with a valid JWT'` block, after the `'includes email_preferences'` example:

```ruby
it 'includes role in response' do
  get_me(headers: { 'Authorization' => "Bearer #{token}" })
  expect(json['role']).to eq('attendee')
end

it 'includes permissions hash in response' do
  get_me(headers: { 'Authorization' => "Bearer #{token}" })
  expect(json['permissions']).to eq({
    'can_check_in_attendees' => false,
    'can_scan_food_stamp'    => false
  })
end

it 'returns updated permissions for a volunteer' do
  user.update!(role: 'volunteer')
  get_me(headers: { 'Authorization' => "Bearer #{token}" })
  expect(json['role']).to eq('volunteer')
  expect(json['permissions']).to eq({
    'can_check_in_attendees' => true,
    'can_scan_food_stamp'    => true
  })
end
```

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
bin/rspec spec/requests/api/v1/auth/me_spec.rb --format documentation
```

Expected: the three new examples fail with `expected: "attendee" / got: nil`.

- [ ] **Step 3: Update user_json in me_controller.rb**

In `app/controllers/api/v1/auth/me_controller.rb`, update the private `user_json` method to add `role` and `permissions`:

```ruby
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
    role:             user.role,
    permissions:      User::ROLE_PERMISSIONS[user.role],
    can_change_email: user.user_identities.exists?(provider: 'email'),
    email_preferences: email_preferences_json(user)
  }
end
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
bin/rspec spec/requests/api/v1/auth/me_spec.rb --format documentation
```

Expected: all examples pass, including the three new ones.

- [ ] **Step 5: Run the full test suite**

```bash
bin/rspec
```

Expected: all examples pass with 0 failures.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/api/v1/auth/me_controller.rb \
        spec/requests/api/v1/auth/me_spec.rb
git commit -m "Include role and permissions in /me response"
```

---

## Task 6: Configure role field in Directus

This task runs against the local Directus instance at `localhost:8091`. No code changes — this configures how Directus displays the `role` column that already exists after the migration.

**Credentials:** `admin@synthbit.io` / `Tw1l1ght932008` (from `docker-compose.yaml`).

- [ ] **Step 1: Get an admin access token**

```bash
DIRECTUS_TOKEN=$(curl -s -X POST http://localhost:8091/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@synthbit.io","password":"Tw1l1ght932008"}' \
  | jq -r '.data.access_token')

echo $DIRECTUS_TOKEN
```

Expected: a long JWT string (not `null`). If `null`, check that Directus is running (`docker-compose up -d`) and credentials are correct.

- [ ] **Step 2: Configure the role field as a select dropdown**

```bash
curl -s -X PATCH "http://localhost:8091/fields/users/role" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $DIRECTUS_TOKEN" \
  -d '{
    "meta": {
      "interface": "select-dropdown",
      "options": {
        "choices": [
          { "text": "Admin",     "value": "admin"     },
          { "text": "Volunteer", "value": "volunteer" },
          { "text": "Attendee",  "value": "attendee"  }
        ]
      },
      "display": "labels",
      "display_options": {
        "choices": [
          { "text": "Admin",     "value": "admin",     "foreground": "#FFFFFF", "background": "#E35169" },
          { "text": "Volunteer", "value": "volunteer", "foreground": "#FFFFFF", "background": "#6644FF" },
          { "text": "Attendee",  "value": "attendee",  "foreground": "#FFFFFF", "background": "#2ECDA7" }
        ]
      },
      "width": "half"
    }
  }' | jq '.data.field'
```

Expected: `"role"` printed, confirming the patch succeeded.

- [ ] **Step 3: Verify in the Directus UI**

Open `http://localhost:8091` → Content → Users → click any user record. The `role` field should show as a coloured badge dropdown with the three options.

- [ ] **Step 4: Note for production**

The same `PATCH /fields/users/role` call can be run against the production Directus URL with a production admin token when deploying.
