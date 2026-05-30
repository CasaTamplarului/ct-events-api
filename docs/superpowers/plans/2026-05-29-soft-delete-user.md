# User Soft-Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `DELETE /api/v1/auth/me` so users can delete their own account — anonymising their PII in place while preserving all attendee records intact.

**Architecture:** A migration adds `deleted_at` to `users`. `UserDeletionService` stamps it, wipes all PII fields via `update_columns`, and destroys `user_identities` + `passkeys` in one transaction. `Authenticatable` gains a one-line change to reject deleted users. `MeController#destroy` calls the service and returns 204. Attendee `user_id` FKs stay untouched.

**Tech Stack:** Rails 8.1, PostgreSQL, RSpec.

---

## File Map

| File | Action | Purpose |
|------|--------|---------|
| `db/migrate/<timestamp>_add_deleted_at_to_users.rb` | Create | Add `deleted_at` column + index to users |
| `app/services/user_deletion_service.rb` | Create | Anonymise user PII, destroy identities/passkeys |
| `spec/services/user_deletion_service_spec.rb` | Create | Unit tests for the service |
| `app/controllers/concerns/authenticatable.rb` | Modify | Reject deleted users from all protected endpoints |
| `config/routes.rb` | Modify | Add `:destroy` to `resource :me` |
| `app/controllers/api/v1/auth/me_controller.rb` | Modify | Add `destroy` action |
| `spec/requests/api/v1/auth/me_spec.rb` | Modify | Add DELETE tests |

---

### Task 1: Migration + UserDeletionService + unit tests

**Files:**
- Create: `db/migrate/<timestamp>_add_deleted_at_to_users.rb`
- Create: `app/services/user_deletion_service.rb`
- Create: `spec/services/user_deletion_service_spec.rb`

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration AddDeletedAtToUsers deleted_at:datetime:index
```

Open the generated file and confirm it looks like this (Rails may have generated it correctly already):

```ruby
class AddDeletedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :deleted_at, :datetime, default: nil
    add_index  :users, :deleted_at
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs cleanly, `schema.rb` gains `t.datetime "deleted_at"` and the index on `users`.

- [ ] **Step 3: Create `spec/services/user_deletion_service_spec.rb`**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UserDeletionService do
  let(:user) do
    create(:user,
           first_name: 'Ion',
           last_name: 'Popescu',
           email: 'ion@example.com',
           phone_number: '+40721000001',
           church_name: 'Betania',
           city: 'Cluj-Napoca',
           language: 'ro')
  end

  describe '.call' do
    context 'PII fields on the user row' do
      before { described_class.call(user) }

      it 'stamps deleted_at' do
        expect(user.reload.deleted_at).to be_present
      end

      it 'sets first_name to "Deleted"' do
        expect(user.reload.first_name).to eq('Deleted')
      end

      it 'clears email' do
        expect(user.reload.email).to be_nil
      end

      it 'clears last_name' do
        expect(user.reload.last_name).to be_nil
      end

      it 'clears avatar_url' do
        expect(user.reload.avatar_url).to be_nil
      end

      it 'clears phone_number' do
        expect(user.reload.phone_number).to be_nil
      end

      it 'clears church_name' do
        expect(user.reload.church_name).to be_nil
      end

      it 'clears city' do
        expect(user.reload.city).to be_nil
      end

      it 'clears language' do
        expect(user.reload.language).to be_nil
      end

      it 'clears password_digest' do
        expect(user.reload.password_digest).to be_nil
      end

      it 'clears password_reset_token' do
        expect(user.reload.password_reset_token).to be_nil
      end

      it 'clears password_reset_token_expires_at' do
        expect(user.reload.password_reset_token_expires_at).to be_nil
      end
    end

    context 'associated records' do
      before do
        user.user_identities.create!(provider: 'google', uid: 'google-uid-123')
        create(:passkey, user: user)
        described_class.call(user)
      end

      it 'destroys all user_identities' do
        expect(UserIdentity.where(user_id: user.id)).to be_empty
      end

      it 'destroys all passkeys' do
        expect(Passkey.where(user_id: user.id)).to be_empty
      end
    end

    context 'attendee records' do
      let!(:event)    { create(:event) }
      let!(:attendee) { create(:attendee, event: event, user: user, email_address: 'ion@example.com', first_name: 'Ion') }

      before { described_class.call(user) }

      it 'leaves attendee user_id pointing to the anonymised user' do
        expect(attendee.reload.user_id).to eq(user.id)
      end

      it 'leaves attendee email_address unchanged' do
        expect(attendee.reload.email_address).to eq('ion@example.com')
      end

      it 'leaves attendee first_name unchanged' do
        expect(attendee.reload.first_name).to eq('Ion')
      end
    end
  end
end
```

- [ ] **Step 4: Run the spec to confirm it fails**

```bash
bundle exec rspec spec/services/user_deletion_service_spec.rb --format documentation 2>&1 | head -10
```

Expected: FAIL — `uninitialized constant UserDeletionService`

- [ ] **Step 5: Create `app/services/user_deletion_service.rb`**

```ruby
# frozen_string_literal: true

class UserDeletionService
  def self.call(user)
    ActiveRecord::Base.transaction do
      user.update_columns(
        deleted_at:                      Time.current,
        email:                           nil,
        first_name:                      'Deleted',
        last_name:                       nil,
        avatar_url:                      nil,
        phone_number:                    nil,
        church_name:                     nil,
        city:                            nil,
        language:                        nil,
        password_digest:                 nil,
        password_reset_token:            nil,
        password_reset_token_expires_at: nil
      )
      user.user_identities.destroy_all
      user.passkeys.destroy_all
    end
  end
end
```

`update_columns` is used deliberately — it bypasses Active Record validations (the `first_name: presence: true` validation would reject the nil write for other fields if we used `update`). This is a system operation, not user input.

- [ ] **Step 6: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/services/user_deletion_service_spec.rb --format documentation
```

Expected: all examples pass.

- [ ] **Step 7: Run the full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 8: Run RuboCop**

```bash
bundle exec rubocop app/services/user_deletion_service.rb spec/services/user_deletion_service_spec.rb
```

Fix any offenses.

- [ ] **Step 9: Commit**

```bash
git add db/migrate/*_add_deleted_at_to_users.rb db/schema.rb \
        app/services/user_deletion_service.rb \
        spec/services/user_deletion_service_spec.rb
git commit -m "Add UserDeletionService with migration for deleted_at"
```

---

### Task 2: Auth guard + route + MeController#destroy + request tests + push

**Files:**
- Modify: `app/controllers/concerns/authenticatable.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/auth/me_controller.rb`
- Modify: `spec/requests/api/v1/auth/me_spec.rb`

- [ ] **Step 1: Add DELETE tests to `spec/requests/api/v1/auth/me_spec.rb`**

The file already has a `let(:token)` and a `def get_me` helper at the top level. Add a new `describe` block at the bottom of the file, before the final `end`:

```ruby
  # ── DELETE /api/v1/auth/me ───────────────────────────────────────────────────

  describe 'DELETE /api/v1/auth/me' do
    def delete_me(headers: { 'Authorization' => "Bearer #{token}" })
      delete '/api/v1/auth/me',
             headers: { 'Content-Type' => 'application/json' }.merge(headers)
    end

    context 'with a valid JWT' do
      it 'returns 204' do
        delete_me
        expect(response).to have_http_status(:no_content)
      end

      it 'stamps deleted_at on the user' do
        delete_me
        expect(user.reload.deleted_at).to be_present
      end

      it 'sets first_name to "Deleted"' do
        delete_me
        expect(user.reload.first_name).to eq('Deleted')
      end

      it 'clears the email' do
        delete_me
        expect(user.reload.email).to be_nil
      end
    end

    context 'after deletion, reusing the same JWT' do
      before { delete_me }

      it 'returns 401 on GET /api/v1/auth/me' do
        get_me(headers: { 'Authorization' => "Bearer #{token}" })
        expect(response).to have_http_status(:unauthorized)
      end

      it 'returns 401 on a second DELETE /api/v1/auth/me' do
        delete_me
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with no Authorization header' do
      it 'returns 401' do
        delete_me(headers: {})
        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
```

- [ ] **Step 2: Run the DELETE spec to confirm it fails**

```bash
bundle exec rspec spec/requests/api/v1/auth/me_spec.rb --format documentation 2>&1 | grep -A 3 "DELETE"
```

Expected: routing error — `No route matches [DELETE] "/api/v1/auth/me"`

- [ ] **Step 3: Update `config/routes.rb` to add `:destroy`**

Find this line (line 14):

```ruby
        resource :me, only: %i[show update], controller: 'me' do
```

Change it to:

```ruby
        resource :me, only: %i[show update destroy], controller: 'me' do
```

- [ ] **Step 4: Add `destroy` action to `app/controllers/api/v1/auth/me_controller.rb`**

Add after the `update` action and before the `password` action:

```ruby
        def destroy
          UserDeletionService.call(current_user)
          head :no_content
        end
```

- [ ] **Step 5: Run the spec — expect the "after deletion" tests to fail**

```bash
bundle exec rspec spec/requests/api/v1/auth/me_spec.rb --format documentation 2>&1 | grep -E "FAILED|DELETE"
```

The `204` and anonymisation tests should now pass. The "after deletion, reusing the same JWT" tests will still fail because `Authenticatable` still finds deleted users.

- [ ] **Step 6: Update `app/controllers/concerns/authenticatable.rb`**

Find this line:

```ruby
    @current_user = User.find_by(id: user_id)
```

Change it to:

```ruby
    @current_user = User.find_by(id: user_id, deleted_at: nil)
```

The full updated method:

```ruby
  def authenticate_user!
    token = request.headers['Authorization']&.split&.last
    return render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized if token.blank?

    user_id = JwtService.decode(token)
    @current_user = User.find_by(id: user_id, deleted_at: nil)
    render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized unless @current_user
  rescue JWT::DecodeError
    render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized
  end
```

- [ ] **Step 7: Run the full me spec to confirm all tests pass**

```bash
bundle exec rspec spec/requests/api/v1/auth/me_spec.rb --format documentation
```

Expected: all examples pass, including the "after deletion" context.

- [ ] **Step 8: Run the full suite**

```bash
bundle exec rspec
```

Expected: 0 failures.

- [ ] **Step 9: Run RuboCop**

```bash
bundle exec rubocop app/controllers/concerns/authenticatable.rb \
                    app/controllers/api/v1/auth/me_controller.rb \
                    config/routes.rb \
                    spec/requests/api/v1/auth/me_spec.rb
```

Fix any offenses.

- [ ] **Step 10: Commit**

```bash
git add app/controllers/concerns/authenticatable.rb \
        app/controllers/api/v1/auth/me_controller.rb \
        config/routes.rb \
        spec/requests/api/v1/auth/me_spec.rb
git commit -m "Add DELETE /api/v1/auth/me for user account deletion"
```

- [ ] **Step 11: Push**

```bash
git push origin main
```
