# Q&A Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Q&A session management to the Rails API — staff create sessions per event, public users submit and vote on questions via a short-code URL.

**Architecture:** Four new tables (`qa_sessions`, `qa_session_translations`, `qa_questions`, `qa_votes`) in the shared PostgreSQL database. Admin endpoints are protected by `role == 'admin'`; public endpoints use an optional JWT plus an `X-QA-Token` UUID header for anonymous identity. No serializer classes — all controllers render JSON inline to keep identity-aware field logic (my_vote, can_delete) simple.

**Tech Stack:** Rails 8 API, PostgreSQL, RSpec + FactoryBot, JwtService (existing), Alba not used here (inline JSON rendering).

**Spec:** `docs/superpowers/specs/2026-06-20-qa-sessions-design.md`

---

## File Map

**New migrations:**
- `db/migrate/20260621000001_create_qa_sessions.rb`
- `db/migrate/20260621000002_create_qa_session_translations.rb`
- `db/migrate/20260621000003_create_qa_questions.rb`
- `db/migrate/20260621000004_create_qa_votes.rb`

**New models:**
- `app/models/qa_session.rb`
- `app/models/qa_session_translation.rb`
- `app/models/qa_question.rb`
- `app/models/qa_vote.rb`

**Modified models:**
- `app/models/event.rb` — add `has_many :qa_sessions`
- `app/models/user.rb` — add `has_many :created_qa_sessions`

**New concerns:**
- `app/controllers/concerns/qa_identifiable.rb` — resolves caller identity on public endpoints
- `app/controllers/concerns/qa_question_renderable.rb` — shared `question_json` helper

**Modified:**
- `app/controllers/concerns/authenticatable.rb` — add `require_admin!`
- `config/routes.rb` — new admin + public Q&A routes

**New controllers:**
- `app/controllers/api/v1/admin/qa_sessions_controller.rb`
- `app/controllers/api/v1/admin/qa_questions_controller.rb`
- `app/controllers/api/v1/qa_sessions_controller.rb`
- `app/controllers/api/v1/qa_questions_controller.rb`
- `app/controllers/api/v1/qa_votes_controller.rb`

**New factories:**
- `spec/factories/qa_sessions.rb`
- `spec/factories/qa_session_translations.rb`
- `spec/factories/qa_questions.rb`
- `spec/factories/qa_votes.rb`

**New specs:**
- `spec/models/qa_session_spec.rb`
- `spec/models/qa_question_spec.rb`
- `spec/models/qa_vote_spec.rb`
- `spec/requests/api/v1/admin/qa_sessions_spec.rb`
- `spec/requests/api/v1/admin/qa_questions_spec.rb`
- `spec/requests/api/v1/qa_sessions_spec.rb`
- `spec/requests/api/v1/qa_questions_spec.rb`
- `spec/requests/api/v1/qa_votes_spec.rb`

---

## Task 1: Migrations

**Files:**
- Create: `db/migrate/20260621000001_create_qa_sessions.rb`
- Create: `db/migrate/20260621000002_create_qa_session_translations.rb`
- Create: `db/migrate/20260621000003_create_qa_questions.rb`
- Create: `db/migrate/20260621000004_create_qa_votes.rb`

- [ ] **Step 1: Create migration files**

```ruby
# db/migrate/20260621000001_create_qa_sessions.rb
class CreateQaSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :qa_sessions do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.string :code, limit: 8, null: false
      t.integer :status, null: false, default: 0
      t.boolean :voting_enabled, null: false, default: true
      t.boolean :questions_public, null: false, default: true
      t.bigint :created_by_user_id, null: false
      t.timestamps
    end
    add_index :qa_sessions, :code, unique: true
    add_foreign_key :qa_sessions, :users, column: :created_by_user_id
  end
end
```

```ruby
# db/migrate/20260621000002_create_qa_session_translations.rb
class CreateQaSessionTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :qa_session_translations do |t|
      t.references :qa_session, null: false, foreign_key: { on_delete: :cascade }
      t.string :languages_code, null: false
      t.string :name, null: false
      t.timestamps
    end
    add_index :qa_session_translations, %i[qa_session_id languages_code],
              unique: true, name: 'idx_qa_session_translations_unique'
    add_foreign_key :qa_session_translations, :languages,
                    column: :languages_code, primary_key: :code
  end
end
```

```ruby
# db/migrate/20260621000003_create_qa_questions.rb
class CreateQaQuestions < ActiveRecord::Migration[8.1]
  def change
    create_table :qa_questions do |t|
      t.references :qa_session, null: false, foreign_key: { on_delete: :cascade }
      t.text :body, null: false
      t.string :display_name
      t.bigint :user_id
      t.string :submitter_token
      t.timestamps
    end
    add_index :qa_questions, :qa_session_id
    add_foreign_key :qa_questions, :users, column: :user_id, on_delete: :nullify
  end
end
```

```ruby
# db/migrate/20260621000004_create_qa_votes.rb
class CreateQaVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :qa_votes do |t|
      t.references :qa_question, null: false, foreign_key: { on_delete: :cascade }
      t.integer :value, null: false
      t.bigint :user_id
      t.string :voter_token
      t.timestamps
    end
    add_index :qa_votes, %i[qa_question_id user_id],
              unique: true, where: 'user_id IS NOT NULL', name: 'idx_qa_votes_user_unique'
    add_index :qa_votes, %i[qa_question_id voter_token],
              unique: true, where: 'voter_token IS NOT NULL', name: 'idx_qa_votes_token_unique'
  end
end
```

- [ ] **Step 2: Run migrations**

```bash
bin/rails db:migrate
```

Expected: 4 migrations applied, no errors.

- [ ] **Step 3: Verify schema**

```bash
grep -A5 'create_table "qa_sessions"' db/schema.rb
grep -A5 'create_table "qa_votes"' db/schema.rb
```

Expected: both tables present with correct columns.

- [ ] **Step 4: Commit**

```bash
git add db/migrate/20260621000001_create_qa_sessions.rb \
        db/migrate/20260621000002_create_qa_session_translations.rb \
        db/migrate/20260621000003_create_qa_questions.rb \
        db/migrate/20260621000004_create_qa_votes.rb \
        db/schema.rb
git commit -m "feat: add qa_sessions, qa_questions, qa_votes migrations"
```

---

## Task 2: Models + Factories

**Files:**
- Create: `app/models/qa_session.rb`
- Create: `app/models/qa_session_translation.rb`
- Create: `app/models/qa_question.rb`
- Create: `app/models/qa_vote.rb`
- Modify: `app/models/event.rb`
- Modify: `app/models/user.rb`
- Create: `spec/factories/qa_sessions.rb`
- Create: `spec/factories/qa_session_translations.rb`
- Create: `spec/factories/qa_questions.rb`
- Create: `spec/factories/qa_votes.rb`
- Create: `spec/models/qa_session_spec.rb`
- Create: `spec/models/qa_question_spec.rb`
- Create: `spec/models/qa_vote_spec.rb`

- [ ] **Step 1: Write failing model specs**

```ruby
# spec/models/qa_session_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QaSession do
  let(:admin)   { create(:user, role: 'admin') }
  let(:event)   { create(:event) }

  describe 'code auto-generation' do
    it 'generates an 8-character alphanumeric code before create' do
      session = QaSession.create!(event: event, created_by_user: admin)
      expect(session.code).to match(/\A[A-Z0-9]{8}\z/)
    end

    it 'does not overwrite a manually set code on create' do
      session = QaSession.new(event: event, created_by_user: admin)
      session.code = 'MYCODE01'
      session.save!
      expect(session.reload.code).to eq('MYCODE01')
    end
  end

  describe '#name_for' do
    let!(:language_ro) { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }
    let!(:language_en) { Language.find_or_create_by!(code: 'en-US') { |l| l.name = 'English' } }
    let(:session) { create(:qa_session, event: event, created_by_user: admin) }

    before do
      session.qa_session_translations.create!(languages_code: 'ro-RO', name: 'Sesiunea 1')
      session.qa_session_translations.create!(languages_code: 'en-US', name: 'Session 1')
    end

    it 'returns the name for the requested language' do
      expect(session.name_for('ro-RO')).to eq('Sesiunea 1')
      expect(session.name_for('en-US')).to eq('Session 1')
    end

    it 'falls back to the first available translation when language not found' do
      expect(session.name_for('fr-FR')).to eq('Sesiunea 1')
    end
  end

  describe 'enum status' do
    it 'defaults to open' do
      session = QaSession.create!(event: event, created_by_user: admin)
      expect(session).to be_open
    end

    it 'can be closed' do
      session = create(:qa_session, event: event, created_by_user: admin)
      session.closed!
      expect(session.reload).to be_closed
    end
  end
end
```

```ruby
# spec/models/qa_question_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QaQuestion do
  let(:session) { create(:qa_session) }

  describe 'validations' do
    it 'is invalid without body' do
      q = QaQuestion.new(qa_session: session, submitter_token: SecureRandom.uuid)
      expect(q).not_to be_valid
      expect(q.errors[:body]).to be_present
    end

    it 'is invalid without user_id or submitter_token' do
      q = QaQuestion.new(qa_session: session, body: 'Question?')
      expect(q).not_to be_valid
      expect(q.errors[:base]).to include('must have user or submitter token')
    end

    it 'is valid with user_id' do
      user = create(:user)
      q = QaQuestion.new(qa_session: session, body: 'Question?', user_id: user.id)
      expect(q).to be_valid
    end

    it 'is valid with submitter_token' do
      q = QaQuestion.new(qa_session: session, body: 'Question?', submitter_token: SecureRandom.uuid)
      expect(q).to be_valid
    end
  end

  describe '#submitted_by?' do
    let(:user)  { create(:user) }
    let(:token) { SecureRandom.uuid }

    it 'matches by user_id' do
      q = create(:qa_question, qa_session: session, user_id: user.id, submitter_token: nil)
      expect(q.submitted_by?({ user_id: user.id, voter_token: nil })).to be true
      expect(q.submitted_by?({ user_id: user.id + 1, voter_token: nil })).to be false
    end

    it 'matches by voter_token' do
      q = create(:qa_question, qa_session: session, submitter_token: token)
      expect(q.submitted_by?({ user_id: nil, voter_token: token })).to be true
      expect(q.submitted_by?({ user_id: nil, voter_token: 'other' })).to be false
    end

    it 'returns false for nil identity' do
      q = create(:qa_question, qa_session: session, submitter_token: token)
      expect(q.submitted_by?(nil)).to be false
    end
  end

  describe '#score' do
    let(:question) { create(:qa_question, qa_session: session) }

    it 'sums vote values' do
      create(:qa_vote, qa_question: question, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: question, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: question, value: -1, voter_token: SecureRandom.uuid)
      expect(question.qa_votes.reload.sum(&:value)).to eq(1)
    end
  end
end
```

```ruby
# spec/models/qa_vote_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe QaVote do
  let(:question) { create(:qa_question) }

  describe 'validations' do
    it 'is invalid with value 0' do
      vote = QaVote.new(qa_question: question, value: 0, voter_token: SecureRandom.uuid)
      expect(vote).not_to be_valid
    end

    it 'is valid with value 1' do
      vote = QaVote.new(qa_question: question, value: 1, voter_token: SecureRandom.uuid)
      expect(vote).to be_valid
    end

    it 'is valid with value -1' do
      vote = QaVote.new(qa_question: question, value: -1, voter_token: SecureRandom.uuid)
      expect(vote).to be_valid
    end

    it 'requires user_id or voter_token' do
      vote = QaVote.new(qa_question: question, value: 1)
      expect(vote).not_to be_valid
      expect(vote.errors[:base]).to include('must have user_id or voter_token')
    end
  end

  describe '.find_for' do
    let(:user)  { create(:user) }
    let(:token) { SecureRandom.uuid }

    it 'finds by user_id' do
      vote = create(:qa_vote, qa_question: question, value: 1, user_id: user.id, voter_token: nil)
      expect(QaVote.find_for(question: question, identity: { user_id: user.id, voter_token: nil })).to eq(vote)
    end

    it 'finds by voter_token' do
      vote = create(:qa_vote, qa_question: question, value: 1, voter_token: token)
      expect(QaVote.find_for(question: question, identity: { user_id: nil, voter_token: token })).to eq(vote)
    end

    it 'returns nil when not found' do
      expect(QaVote.find_for(question: question, identity: { user_id: nil, voter_token: 'missing' })).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run specs to confirm they fail**

```bash
bin/rspec spec/models/qa_session_spec.rb spec/models/qa_question_spec.rb spec/models/qa_vote_spec.rb
```

Expected: fails with `uninitialized constant QaSession` (or similar).

- [ ] **Step 3: Write factories**

```ruby
# spec/factories/qa_sessions.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :qa_session do
    association :event
    association :created_by_user, factory: :user, role: 'admin'
    status { :open }
    voting_enabled { true }
    questions_public { true }
  end
end
```

```ruby
# spec/factories/qa_session_translations.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :qa_session_translation do
    association :qa_session
    languages_code { 'ro-RO' }
    name { 'Sesiunea de Q&A' }

    before(:create) do |t|
      Language.find_or_create_by!(code: t.languages_code) { |l| l.name = 'Romanian' }
    end
  end
end
```

```ruby
# spec/factories/qa_questions.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :qa_question do
    association :qa_session
    body { 'What time does it start?' }
    display_name { 'A User' }
    submitter_token { SecureRandom.uuid }
    user_id { nil }
  end
end
```

```ruby
# spec/factories/qa_votes.rb
# frozen_string_literal: true

FactoryBot.define do
  factory :qa_vote do
    association :qa_question
    value { 1 }
    voter_token { SecureRandom.uuid }
    user_id { nil }
  end
end
```

- [ ] **Step 4: Write models**

```ruby
# app/models/qa_session.rb
# frozen_string_literal: true

class QaSession < ApplicationRecord
  belongs_to :event
  belongs_to :created_by_user, class_name: 'User'
  has_many :qa_session_translations, dependent: :destroy
  has_many :qa_questions, dependent: :destroy

  enum :status, { open: 0, closed: 1 }

  validates :code, presence: true, uniqueness: true

  before_validation :generate_code, on: :create, if: -> { code.blank? }

  def name_for(lang)
    translations = qa_session_translations.to_a
    translation = translations.find { |t| t.languages_code == lang } || translations.first
    translation&.name
  end

  private

    def generate_code
      loop do
        self.code = SecureRandom.alphanumeric(8).upcase
        break unless QaSession.exists?(code: code)
      end
    end
end
```

```ruby
# app/models/qa_session_translation.rb
# frozen_string_literal: true

class QaSessionTranslation < ApplicationRecord
  belongs_to :qa_session
  belongs_to :language, foreign_key: :languages_code, primary_key: :code

  validates :name, presence: true
  validates :languages_code, presence: true, uniqueness: { scope: :qa_session_id }
end
```

```ruby
# app/models/qa_question.rb
# frozen_string_literal: true

class QaQuestion < ApplicationRecord
  belongs_to :qa_session
  belongs_to :user, optional: true
  has_many :qa_votes, dependent: :destroy

  validates :body, presence: true
  validate :identity_present

  def submitted_by?(identity)
    return false if identity.nil?
    return user_id == identity[:user_id] if identity[:user_id] && user_id
    return submitter_token == identity[:voter_token] if identity[:voter_token].present? && submitter_token.present?

    false
  end

  private

    def identity_present
      errors.add(:base, 'must have user or submitter token') if user_id.nil? && submitter_token.blank?
    end
end
```

```ruby
# app/models/qa_vote.rb
# frozen_string_literal: true

class QaVote < ApplicationRecord
  belongs_to :qa_question

  validates :value, inclusion: { in: [1, -1] }
  validate :identity_present

  def self.find_for(question:, identity:)
    if identity[:user_id]
      find_by(qa_question: question, user_id: identity[:user_id])
    else
      find_by(qa_question: question, voter_token: identity[:voter_token])
    end
  end

  private

    def identity_present
      errors.add(:base, 'must have user_id or voter_token') if user_id.nil? && voter_token.blank?
    end
end
```

- [ ] **Step 5: Add associations to Event and User**

In `app/models/event.rb`, add after the existing `has_many` lines:

```ruby
has_many :qa_sessions, dependent: :destroy
```

In `app/models/user.rb`, add after `has_many :push_subscriptions`:

```ruby
has_many :created_qa_sessions, class_name: 'QaSession', foreign_key: :created_by_user_id, dependent: :restrict_with_error
```

- [ ] **Step 6: Run specs to confirm they pass**

```bash
bin/rspec spec/models/qa_session_spec.rb spec/models/qa_question_spec.rb spec/models/qa_vote_spec.rb
```

Expected: all green.

- [ ] **Step 7: Commit**

```bash
git add app/models/qa_session.rb app/models/qa_session_translation.rb \
        app/models/qa_question.rb app/models/qa_vote.rb \
        app/models/event.rb app/models/user.rb \
        spec/factories/qa_sessions.rb spec/factories/qa_session_translations.rb \
        spec/factories/qa_questions.rb spec/factories/qa_votes.rb \
        spec/models/qa_session_spec.rb spec/models/qa_question_spec.rb \
        spec/models/qa_vote_spec.rb
git commit -m "feat: add QaSession, QaQuestion, QaVote models with specs"
```

---

## Task 3: Concerns + Routes

**Files:**
- Create: `app/controllers/concerns/qa_identifiable.rb`
- Create: `app/controllers/concerns/qa_question_renderable.rb`
- Modify: `app/controllers/concerns/authenticatable.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Create QaIdentifiable concern**

```ruby
# app/controllers/concerns/qa_identifiable.rb
# frozen_string_literal: true

module QaIdentifiable
  extend ActiveSupport::Concern

  def current_qa_identity
    if current_user
      { user_id: current_user.id, voter_token: nil }
    else
      { user_id: nil, voter_token: request.headers['X-QA-Token'].presence }
    end
  end
end
```

- [ ] **Step 2: Create QaQuestionRenderable concern**

The `question_json` helper is used in both admin and public controllers. It receives a question with eagerly-loaded `qa_votes`.

```ruby
# app/controllers/concerns/qa_question_renderable.rb
# frozen_string_literal: true

module QaQuestionRenderable
  def question_json(question, identity:, admin: false)
    votes = question.qa_votes.to_a
    my_vote = nil

    if identity
      found = votes.find do |v|
        (identity[:user_id] && v.user_id == identity[:user_id]) ||
          (identity[:voter_token].present? && v.voter_token == identity[:voter_token])
      end
      my_vote = found&.value
    end

    score = votes.sum(&:value)
    can_delete = admin || question.submitted_by?(identity)

    {
      id: question.id,
      body: question.body,
      display_name: question.display_name,
      score: score,
      my_vote: my_vote,
      can_delete: can_delete,
      created_at: question.created_at
    }
  end
end
```

- [ ] **Step 3: Add `require_admin!` to Authenticatable**

Open `app/controllers/concerns/authenticatable.rb` and add this method after `require_permission!`:

```ruby
def require_admin!
  return if current_user&.role == 'admin'

  render json: { error: I18n.t('auth.errors.forbidden') }, status: :forbidden
end
```

- [ ] **Step 4: Add routes**

Open `config/routes.rb`. Inside `namespace :v1 do`, add after the `namespace :admin do` block:

```ruby
# inside namespace :admin do, after existing resources:
scope '/events/:event_slug' do
  get  'qa_sessions', to: 'qa_sessions#index', as: 'admin_event_qa_sessions'
  post 'qa_sessions', to: 'qa_sessions#create'
end
scope '/qa_sessions/:code' do
  patch  '/',           to: 'qa_sessions#update',  as: 'admin_qa_session'
  delete '/',           to: 'qa_sessions#destroy'
  get    'questions',   to: 'qa_questions#index',   as: 'admin_qa_session_questions'
  delete 'questions/:id', to: 'qa_questions#destroy', as: 'admin_qa_session_question'
end
```

Then outside `namespace :admin`, inside `namespace :v1`, add:

```ruby
# Public Q&A routes (outside any language scope)
scope '/events/:event_slug/qa/:code' do
  get    '/',                          to: 'qa_sessions#show',    as: 'public_qa_session'
  post   'questions',                  to: 'qa_questions#create', as: 'public_qa_questions'
  delete 'questions/:id',              to: 'qa_questions#destroy', as: 'public_qa_question'
  post   'questions/:question_id/vote', to: 'qa_votes#create',    as: 'public_qa_vote'
end
```

- [ ] **Step 5: Verify routes**

```bash
bin/rails routes | grep qa
```

Expected output (approximately):
```
admin_event_qa_sessions  GET    /api/v1/admin/events/:event_slug/qa_sessions
                         POST   /api/v1/admin/events/:event_slug/qa_sessions
         admin_qa_session PATCH  /api/v1/admin/qa_sessions/:code
                          DELETE /api/v1/admin/qa_sessions/:code
admin_qa_session_questions GET  /api/v1/admin/qa_sessions/:code/questions
admin_qa_session_question DELETE /api/v1/admin/qa_sessions/:code/questions/:id
        public_qa_session GET   /api/v1/events/:event_slug/qa/:code
       public_qa_questions POST  /api/v1/events/:event_slug/qa/:code/questions
        public_qa_question DELETE /api/v1/events/:event_slug/qa/:code/questions/:id
            public_qa_vote POST  /api/v1/events/:event_slug/qa/:code/questions/:question_id/vote
```

- [ ] **Step 6: Commit**

```bash
git add app/controllers/concerns/qa_identifiable.rb \
        app/controllers/concerns/qa_question_renderable.rb \
        app/controllers/concerns/authenticatable.rb \
        config/routes.rb
git commit -m "feat: add QaIdentifiable/QaQuestionRenderable concerns, require_admin!, Q&A routes"
```

---

## Task 4: Admin QaSessionsController

**Files:**
- Create: `app/controllers/api/v1/admin/qa_sessions_controller.rb`
- Create: `spec/requests/api/v1/admin/qa_sessions_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/api/v1/admin/qa_sessions_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Q&A Sessions' do
  let!(:language) { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }
  let(:admin)     { create(:user, role: 'admin') }
  let(:non_admin) { create(:user, role: 'attendee') }
  let(:event)     { create(:event, slug: 'my-event') }
  let(:headers)   { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{JwtService.encode(admin.id)}" } }
  let(:non_admin_headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{JwtService.encode(non_admin.id)}" } }

  describe 'GET /api/v1/admin/events/:event_slug/qa_sessions' do
    let!(:session) { create(:qa_session, event: event, created_by_user: admin) }
    let!(:translation) { create(:qa_session_translation, qa_session: session, languages_code: 'ro-RO', name: 'Sesiunea 1') }

    it 'returns 401 without auth' do
      get "/api/v1/admin/events/#{event.slug}/qa_sessions"
      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns 403 for non-admin' do
      get "/api/v1/admin/events/#{event.slug}/qa_sessions", headers: non_admin_headers
      expect(response).to have_http_status(:forbidden)
    end

    it 'returns sessions with translations and question_count' do
      create(:qa_question, qa_session: session)
      get "/api/v1/admin/events/#{event.slug}/qa_sessions", headers: headers

      expect(response).to have_http_status(:ok)
      body = json
      expect(body).to be_an(Array)
      expect(body.length).to eq(1)

      s = body.first
      expect(s['code']).to eq(session.code)
      expect(s['status']).to eq('open')
      expect(s['voting_enabled']).to be true
      expect(s['questions_public']).to be true
      expect(s['question_count']).to eq(1)
      expect(s['translations'].first['languages_code']).to eq('ro-RO')
      expect(s['translations'].first['name']).to eq('Sesiunea 1')
    end

    it 'returns 404 for unknown event' do
      get '/api/v1/admin/events/nonexistent/qa_sessions', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/admin/events/:event_slug/qa_sessions' do
    let(:params) do
      {
        voting_enabled: true,
        questions_public: false,
        translations: { 'ro-RO' => { name: 'Sesiunea 1' } }
      }
    end

    it 'creates a session with an auto-generated code' do
      post "/api/v1/admin/events/#{event.slug}/qa_sessions",
           params: params.to_json, headers: headers

      expect(response).to have_http_status(:created)
      expect(json['code']).to match(/\A[A-Z0-9]{8}\z/)
      expect(json['status']).to eq('open')
      expect(json['voting_enabled']).to be true
      expect(json['questions_public']).to be false
      expect(json['translations'].first['name']).to eq('Sesiunea 1')
    end

    it 'returns 403 for non-admin' do
      post "/api/v1/admin/events/#{event.slug}/qa_sessions",
           params: params.to_json, headers: non_admin_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'PATCH /api/v1/admin/qa_sessions/:code' do
    let!(:session) { create(:qa_session, event: event, created_by_user: admin, status: :open) }
    let!(:translation) { create(:qa_session_translation, qa_session: session, languages_code: 'ro-RO', name: 'Old') }

    it 'closes the session' do
      patch "/api/v1/admin/qa_sessions/#{session.code}",
            params: { status: 'closed' }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['status']).to eq('closed')
      expect(session.reload).to be_closed
    end

    it 'updates a translation name' do
      patch "/api/v1/admin/qa_sessions/#{session.code}",
            params: { translations: { 'ro-RO' => { name: 'Updated' } } }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(session.qa_session_translations.find_by(languages_code: 'ro-RO').name).to eq('Updated')
    end

    it 'toggles voting_enabled' do
      patch "/api/v1/admin/qa_sessions/#{session.code}",
            params: { voting_enabled: false }.to_json, headers: headers

      expect(response).to have_http_status(:ok)
      expect(json['voting_enabled']).to be false
    end
  end

  describe 'DELETE /api/v1/admin/qa_sessions/:code' do
    let!(:session) { create(:qa_session, event: event, created_by_user: admin) }

    it 'deletes the session and returns 204' do
      delete "/api/v1/admin/qa_sessions/#{session.code}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(QaSession.find_by(code: session.code)).to be_nil
    end

    it 'returns 403 for non-admin' do
      delete "/api/v1/admin/qa_sessions/#{session.code}", headers: non_admin_headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm it fails**

```bash
bin/rspec spec/requests/api/v1/admin/qa_sessions_spec.rb
```

Expected: fails with routing error or `ActionController::RoutingError`.

- [ ] **Step 3: Write the controller**

```ruby
# app/controllers/api/v1/admin/qa_sessions_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Admin
      class QaSessionsController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!
        before_action :require_admin!
        before_action :load_event, only: %i[index create]

        def index
          sessions = @event.qa_sessions
                           .includes(:qa_session_translations, :qa_questions)
                           .order(created_at: :desc)
          render json: sessions.map { |s| session_json(s) }
        end

        def create
          session = @event.qa_sessions.new(
            created_by_user: current_user,
            voting_enabled: params.fetch(:voting_enabled, true),
            questions_public: params.fetch(:questions_public, true)
          )

          (params[:translations] || {}).each do |lang, attrs|
            session.qa_session_translations.build(languages_code: lang, name: attrs[:name])
          end

          if session.save
            render json: session_json(session), status: :created
          else
            render json: { error: session.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def update
          session = QaSession.find_by!(code: params[:code])
          attrs = params.permit(:voting_enabled, :questions_public, :status)

          if params[:translations].present?
            params[:translations].each do |lang, translation_attrs|
              t = session.qa_session_translations.find_or_initialize_by(languages_code: lang)
              t.name = translation_attrs[:name]
              t.save!
            end
          end

          if session.update(attrs)
            render json: session_json(session.reload)
          else
            render json: { error: session.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def destroy
          session = QaSession.find_by!(code: params[:code])
          session.destroy!
          head :no_content
        end

        private

          def load_event
            @event = Event.find_by(slug: params[:event_slug])
            render json: { error: 'Event not found' }, status: :not_found unless @event
          end

          def session_json(session)
            {
              code: session.code,
              status: session.status,
              voting_enabled: session.voting_enabled,
              questions_public: session.questions_public,
              question_count: session.qa_questions.size,
              translations: session.qa_session_translations.map do |t|
                { languages_code: t.languages_code, name: t.name }
              end,
              created_at: session.created_at
            }
          end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to confirm it passes**

```bash
bin/rspec spec/requests/api/v1/admin/qa_sessions_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/admin/qa_sessions_controller.rb \
        spec/requests/api/v1/admin/qa_sessions_spec.rb
git commit -m "feat: add admin QaSessionsController with CRUD endpoints"
```

---

## Task 5: Admin QaQuestionsController

**Files:**
- Create: `app/controllers/api/v1/admin/qa_questions_controller.rb`
- Create: `spec/requests/api/v1/admin/qa_questions_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/api/v1/admin/qa_questions_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Admin Q&A Questions' do
  let(:admin)   { create(:user, role: 'admin') }
  let(:event)   { create(:event) }
  let(:session) { create(:qa_session, event: event, created_by_user: admin) }
  let(:headers) { { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{JwtService.encode(admin.id)}" } }

  describe 'GET /api/v1/admin/qa_sessions/:code/questions' do
    let!(:q1) { create(:qa_question, qa_session: session, body: 'Question A') }
    let!(:q2) { create(:qa_question, qa_session: session, body: 'Question B') }

    before do
      create(:qa_vote, qa_question: q1, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: q1, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: q2, value: -1, voter_token: SecureRandom.uuid)
    end

    it 'returns questions sorted by score descending' do
      get "/api/v1/admin/qa_sessions/#{session.code}/questions", headers: headers

      expect(response).to have_http_status(:ok)
      bodies = json.map { |q| q['body'] }
      expect(bodies).to eq(['Question A', 'Question B'])
    end

    it 'returns correct scores' do
      get "/api/v1/admin/qa_sessions/#{session.code}/questions", headers: headers

      q1_json = json.find { |q| q['body'] == 'Question A' }
      q2_json = json.find { |q| q['body'] == 'Question B' }
      expect(q1_json['score']).to eq(2)
      expect(q2_json['score']).to eq(-1)
    end

    it 'returns 401 without auth' do
      get "/api/v1/admin/qa_sessions/#{session.code}/questions"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'DELETE /api/v1/admin/qa_sessions/:code/questions/:id' do
    let!(:question) { create(:qa_question, qa_session: session) }

    it 'removes the question and returns 204' do
      delete "/api/v1/admin/qa_sessions/#{session.code}/questions/#{question.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(QaQuestion.find_by(id: question.id)).to be_nil
    end

    it 'cascades to votes' do
      create(:qa_vote, qa_question: question, value: 1, voter_token: SecureRandom.uuid)
      delete "/api/v1/admin/qa_sessions/#{session.code}/questions/#{question.id}", headers: headers

      expect(QaVote.where(qa_question_id: question.id)).to be_empty
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm it fails**

```bash
bin/rspec spec/requests/api/v1/admin/qa_questions_spec.rb
```

Expected: fails with routing or uninitialized constant error.

- [ ] **Step 3: Write the controller**

```ruby
# app/controllers/api/v1/admin/qa_questions_controller.rb
# frozen_string_literal: true

module Api
  module V1
    module Admin
      class QaQuestionsController < ActionController::API
        include Authenticatable
        include QaQuestionRenderable

        before_action :authenticate_user!
        before_action :require_admin!
        before_action :load_session

        def index
          questions = @qa_session.qa_questions.includes(:qa_votes).to_a
          sorted = questions.sort_by { |q| [-q.qa_votes.sum(&:value), q.created_at] }
          render json: sorted.map { |q| question_json(q, identity: nil, admin: true) }
        end

        def destroy
          question = @qa_session.qa_questions.find(params[:id])
          question.destroy!
          head :no_content
        end

        private

          def load_session
            @qa_session = QaSession.find_by!(code: params[:code])
          rescue ActiveRecord::RecordNotFound
            render json: { error: 'Session not found' }, status: :not_found
          end
      end
    end
  end
end
```

- [ ] **Step 4: Run spec to confirm it passes**

```bash
bin/rspec spec/requests/api/v1/admin/qa_questions_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/admin/qa_questions_controller.rb \
        spec/requests/api/v1/admin/qa_questions_spec.rb
git commit -m "feat: add admin QaQuestionsController (list + delete)"
```

---

## Task 6: Public QaSessionsController (show)

**Files:**
- Create: `app/controllers/api/v1/qa_sessions_controller.rb`
- Create: `spec/requests/api/v1/qa_sessions_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/api/v1/qa_sessions_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/events/:event_slug/qa/:code' do
  let!(:language) { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }
  let(:admin)     { create(:user, role: 'admin') }
  let(:event)     { create(:event, slug: 'my-event') }
  let(:session)   { create(:qa_session, event: event, created_by_user: admin, questions_public: true) }
  let!(:translation) { create(:qa_session_translation, qa_session: session, languages_code: 'ro-RO', name: 'Sesiunea 1') }
  let(:qa_token)  { SecureRandom.uuid }
  let(:headers)   { { 'Content-Type' => 'application/json', 'X-QA-Token' => qa_token } }

  def get_session(code: session.code, lang: 'ro-RO')
    get "/api/v1/events/my-event/qa/#{code}?lang=#{lang}", headers: headers
  end

  it 'returns session info with translated name' do
    get_session
    expect(response).to have_http_status(:ok)
    expect(json['code']).to eq(session.code)
    expect(json['name']).to eq('Sesiunea 1')
    expect(json['status']).to eq('open')
    expect(json['voting_enabled']).to be true
    expect(json['questions_public']).to be true
    expect(json['questions']).to eq([])
  end

  it 'returns 404 for unknown session' do
    get_session(code: 'NOTEXIST')
    expect(response).to have_http_status(:not_found)
  end

  context 'with questions' do
    let!(:q1) { create(:qa_question, qa_session: session, body: 'Alpha?', submitter_token: qa_token) }
    let!(:q2) { create(:qa_question, qa_session: session, body: 'Beta?', submitter_token: 'other-token') }

    before do
      create(:qa_vote, qa_question: q1, value: 1, voter_token: qa_token)
      create(:qa_vote, qa_question: q2, value: 1, voter_token: SecureRandom.uuid)
      create(:qa_vote, qa_question: q2, value: 1, voter_token: SecureRandom.uuid)
    end

    it 'returns questions sorted by score descending' do
      get_session
      bodies = json['questions'].map { |q| q['body'] }
      expect(bodies).to eq(['Beta?', 'Alpha?'])
    end

    it 'returns my_vote for the requester' do
      get_session
      q1_json = json['questions'].find { |q| q['body'] == 'Alpha?' }
      q2_json = json['questions'].find { |q| q['body'] == 'Beta?' }
      expect(q1_json['my_vote']).to eq(1)
      expect(q2_json['my_vote']).to be_nil
    end

    it 'returns can_delete true only for own questions' do
      get_session
      q1_json = json['questions'].find { |q| q['body'] == 'Alpha?' }
      q2_json = json['questions'].find { |q| q['body'] == 'Beta?' }
      expect(q1_json['can_delete']).to be true
      expect(q2_json['can_delete']).to be false
    end
  end

  context 'when questions_public is false' do
    let(:session) { create(:qa_session, event: event, created_by_user: admin, questions_public: false) }
    let!(:own_question)   { create(:qa_question, qa_session: session, body: 'Mine?',   submitter_token: qa_token) }
    let!(:other_question) { create(:qa_question, qa_session: session, body: 'Others?', submitter_token: 'other') }

    it 'returns only the requester own questions' do
      get_session
      bodies = json['questions'].map { |q| q['body'] }
      expect(bodies).to eq(['Mine?'])
      expect(bodies).not_to include('Others?')
    end
  end

  context 'name fallback' do
    it 'falls back to first available translation when lang not found' do
      get_session(lang: 'fr-FR')
      expect(json['name']).to eq('Sesiunea 1')
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm it fails**

```bash
bin/rspec spec/requests/api/v1/qa_sessions_spec.rb
```

Expected: fails with routing or constant error.

- [ ] **Step 3: Write the controller**

```ruby
# app/controllers/api/v1/qa_sessions_controller.rb
# frozen_string_literal: true

module Api
  module V1
    class QaSessionsController < ActionController::API
      include Authenticatable
      include QaIdentifiable
      include QaQuestionRenderable

      def show
        try_authenticate_user

        event = Event.find_by(slug: params[:event_slug])
        return render json: { error: 'Not found' }, status: :not_found unless event

        qa_session = event.qa_sessions
                          .includes(:qa_session_translations, qa_questions: :qa_votes)
                          .find_by(code: params[:code])
        return render json: { error: 'Not found' }, status: :not_found unless qa_session

        identity = current_qa_identity
        lang = params[:lang].presence || 'ro-RO'
        questions = visible_questions(qa_session, identity)
        sorted = questions.sort_by { |q| [-q.qa_votes.sum(&:value), q.created_at] }

        render json: {
          code: qa_session.code,
          name: qa_session.name_for(lang),
          status: qa_session.status,
          voting_enabled: qa_session.voting_enabled,
          questions_public: qa_session.questions_public,
          questions: sorted.map { |q| question_json(q, identity: identity) }
        }
      end

      private

        def visible_questions(qa_session, identity)
          all = qa_session.qa_questions.to_a
          return all if qa_session.questions_public

          all.select { |q| q.submitted_by?(identity) }
        end
    end
  end
end
```

- [ ] **Step 4: Run spec to confirm it passes**

```bash
bin/rspec spec/requests/api/v1/qa_sessions_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/qa_sessions_controller.rb \
        spec/requests/api/v1/qa_sessions_spec.rb
git commit -m "feat: add public QaSessionsController show endpoint"
```

---

## Task 7: Public QaQuestionsController

**Files:**
- Create: `app/controllers/api/v1/qa_questions_controller.rb`
- Create: `spec/requests/api/v1/qa_questions_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/api/v1/qa_questions_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public Q&A Questions' do
  let(:admin)    { create(:user, role: 'admin') }
  let(:event)    { create(:event, slug: 'my-event') }
  let(:session)  { create(:qa_session, event: event, created_by_user: admin, status: :open) }
  let(:qa_token) { SecureRandom.uuid }
  let(:headers)  { { 'Content-Type' => 'application/json', 'X-QA-Token' => qa_token } }

  describe 'POST /api/v1/events/:event_slug/qa/:code/questions' do
    let(:params) { { body: 'What time?', display_name: 'Timo' } }

    def post_question(p = params)
      post "/api/v1/events/my-event/qa/#{session.code}/questions",
           params: p.to_json, headers: headers
    end

    it 'creates a question and returns 201' do
      post_question
      expect(response).to have_http_status(:created)
      expect(json['body']).to eq('What time?')
      expect(json['display_name']).to eq('Timo')
      expect(json['score']).to eq(0)
      expect(json['my_vote']).to be_nil
      expect(json['can_delete']).to be true
    end

    it 'creates anonymous question when display_name omitted' do
      post_question(body: 'Question?')
      expect(response).to have_http_status(:created)
      expect(json['display_name']).to be_nil
    end

    it 'returns 422 when session is closed' do
      session.closed!
      post_question
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 without body' do
      post_question(display_name: 'Timo')
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 without X-QA-Token and no JWT' do
      post "/api/v1/events/my-event/qa/#{session.code}/questions",
           params: params.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'associates question with authenticated user when JWT provided' do
      user  = create(:user)
      token = JwtService.encode(user.id)
      post "/api/v1/events/my-event/qa/#{session.code}/questions",
           params: params.to_json,
           headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:created)
      question = QaQuestion.last
      expect(question.user_id).to eq(user.id)
      expect(question.submitter_token).to be_nil
    end
  end

  describe 'DELETE /api/v1/events/:event_slug/qa/:code/questions/:id' do
    let!(:question) { create(:qa_question, qa_session: session, submitter_token: qa_token) }
    let!(:other_q)  { create(:qa_question, qa_session: session, submitter_token: 'different-token') }

    it 'deletes own question and returns 204' do
      delete "/api/v1/events/my-event/qa/#{session.code}/questions/#{question.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(QaQuestion.find_by(id: question.id)).to be_nil
    end

    it 'returns 403 when trying to delete another user question' do
      delete "/api/v1/events/my-event/qa/#{session.code}/questions/#{other_q.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm it fails**

```bash
bin/rspec spec/requests/api/v1/qa_questions_spec.rb
```

Expected: fails with routing or constant error.

- [ ] **Step 3: Write the controller**

```ruby
# app/controllers/api/v1/qa_questions_controller.rb
# frozen_string_literal: true

module Api
  module V1
    class QaQuestionsController < ActionController::API
      include Authenticatable
      include QaIdentifiable
      include QaQuestionRenderable

      before_action :try_authenticate_user
      before_action :load_session

      def create
        if @qa_session.closed?
          return render json: { error: 'Session is closed' }, status: :unprocessable_content
        end

        identity = current_qa_identity
        if identity[:user_id].nil? && identity[:voter_token].blank?
          return render json: { error: 'X-QA-Token header required' }, status: :unprocessable_content
        end

        question = @qa_session.qa_questions.new(
          body: params[:body],
          display_name: params[:display_name].presence,
          user_id: identity[:user_id],
          submitter_token: identity[:voter_token]
        )

        if question.save
          question.qa_votes.reload
          render json: question_json(question, identity: identity), status: :created
        else
          render json: { error: question.errors.full_messages.first }, status: :unprocessable_content
        end
      end

      def destroy
        identity = current_qa_identity
        question = @qa_session.qa_questions.find(params[:id])

        unless question.submitted_by?(identity)
          return render json: { error: 'Forbidden' }, status: :forbidden
        end

        question.destroy!
        head :no_content
      end

      private

        def load_session
          event = Event.find_by(slug: params[:event_slug])
          return render json: { error: 'Not found' }, status: :not_found unless event

          @qa_session = event.qa_sessions.find_by(code: params[:code])
          render json: { error: 'Not found' }, status: :not_found unless @qa_session
        end
    end
  end
end
```

- [ ] **Step 4: Run spec to confirm it passes**

```bash
bin/rspec spec/requests/api/v1/qa_questions_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/qa_questions_controller.rb \
        spec/requests/api/v1/qa_questions_spec.rb
git commit -m "feat: add public QaQuestionsController (create + delete)"
```

---

## Task 8: Public QaVotesController

**Files:**
- Create: `app/controllers/api/v1/qa_votes_controller.rb`
- Create: `spec/requests/api/v1/qa_votes_spec.rb`

- [ ] **Step 1: Write failing request spec**

```ruby
# spec/requests/api/v1/qa_votes_spec.rb
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Public Q&A Votes' do
  let(:admin)    { create(:user, role: 'admin') }
  let(:event)    { create(:event, slug: 'my-event') }
  let(:session)  { create(:qa_session, event: event, created_by_user: admin, voting_enabled: true) }
  let(:question) { create(:qa_question, qa_session: session) }
  let(:qa_token) { SecureRandom.uuid }
  let(:headers)  { { 'Content-Type' => 'application/json', 'X-QA-Token' => qa_token } }

  def post_vote(value)
    post "/api/v1/events/my-event/qa/#{session.code}/questions/#{question.id}/vote",
         params: { value: value }.to_json, headers: headers
  end

  describe 'POST …/vote (no existing vote)' do
    it 'creates a vote and returns 201 with my_vote' do
      post_vote(1)
      expect(response).to have_http_status(:created)
      expect(json['my_vote']).to eq(1)
      expect(QaVote.count).to eq(1)
    end

    it 'creates a downvote' do
      post_vote(-1)
      expect(response).to have_http_status(:created)
      expect(json['my_vote']).to eq(-1)
    end

    it 'returns 422 for invalid value' do
      post_vote(0)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'POST …/vote (toggle: same value again)' do
    before { create(:qa_vote, qa_question: question, value: 1, voter_token: qa_token) }

    it 'deletes the vote and returns my_vote: null' do
      post_vote(1)
      expect(response).to have_http_status(:ok)
      expect(json['my_vote']).to be_nil
      expect(QaVote.count).to eq(0)
    end
  end

  describe 'POST …/vote (switch: opposite value)' do
    before { create(:qa_vote, qa_question: question, value: 1, voter_token: qa_token) }

    it 'updates the vote direction and returns 200' do
      post_vote(-1)
      expect(response).to have_http_status(:ok)
      expect(json['my_vote']).to eq(-1)
      expect(QaVote.count).to eq(1)
      expect(QaVote.first.value).to eq(-1)
    end
  end

  describe 'session constraints' do
    it 'returns 422 when session is closed' do
      session.closed!
      post_vote(1)
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'returns 422 when voting is disabled' do
      session.update!(voting_enabled: false)
      post_vote(1)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe 'identity' do
    it 'returns 422 without X-QA-Token and no JWT' do
      post "/api/v1/events/my-event/qa/#{session.code}/questions/#{question.id}/vote",
           params: { value: 1 }.to_json,
           headers: { 'Content-Type' => 'application/json' }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it 'uses user_id from JWT when authenticated' do
      user  = create(:user)
      token = JwtService.encode(user.id)
      post "/api/v1/events/my-event/qa/#{session.code}/questions/#{question.id}/vote",
           params: { value: 1 }.to_json,
           headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{token}" }

      expect(response).to have_http_status(:created)
      expect(QaVote.last.user_id).to eq(user.id)
    end
  end
end
```

- [ ] **Step 2: Run spec to confirm it fails**

```bash
bin/rspec spec/requests/api/v1/qa_votes_spec.rb
```

Expected: fails with routing or constant error.

- [ ] **Step 3: Write the controller**

```ruby
# app/controllers/api/v1/qa_votes_controller.rb
# frozen_string_literal: true

module Api
  module V1
    class QaVotesController < ActionController::API
      include Authenticatable
      include QaIdentifiable

      before_action :try_authenticate_user
      before_action :load_session_and_question

      def create
        if @qa_session.closed?
          return render json: { error: 'Session is closed' }, status: :unprocessable_content
        end

        unless @qa_session.voting_enabled
          return render json: { error: 'Voting is disabled' }, status: :unprocessable_content
        end

        identity = current_qa_identity
        if identity[:user_id].nil? && identity[:voter_token].blank?
          return render json: { error: 'X-QA-Token header required' }, status: :unprocessable_content
        end

        value = params[:value].to_i
        unless [1, -1].include?(value)
          return render json: { error: 'value must be 1 or -1' }, status: :unprocessable_content
        end

        existing = QaVote.find_for(question: @question, identity: identity)

        if existing
          if existing.value == value
            existing.destroy!
            render json: { my_vote: nil }, status: :ok
          else
            existing.update!(value: value)
            render json: { my_vote: value }, status: :ok
          end
        else
          vote = @question.qa_votes.create!(
            value: value,
            user_id: identity[:user_id],
            voter_token: identity[:voter_token]
          )
          render json: { my_vote: vote.value }, status: :created
        end
      end

      private

        def load_session_and_question
          event = Event.find_by(slug: params[:event_slug])
          return render json: { error: 'Not found' }, status: :not_found unless event

          @qa_session = event.qa_sessions.find_by(code: params[:code])
          return render json: { error: 'Not found' }, status: :not_found unless @qa_session

          @question = @qa_session.qa_questions.find_by(id: params[:question_id])
          render json: { error: 'Not found' }, status: :not_found unless @question
        end
    end
  end
end
```

- [ ] **Step 4: Run spec to confirm it passes**

```bash
bin/rspec spec/requests/api/v1/qa_votes_spec.rb
```

Expected: all green.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/qa_votes_controller.rb \
        spec/requests/api/v1/qa_votes_spec.rb
git commit -m "feat: add public QaVotesController with toggle logic"
```

---

## Task 9: Full Suite + Cleanup

- [ ] **Step 1: Run the full test suite**

```bash
bin/rspec
```

Expected: all green, no regressions.

- [ ] **Step 2: Lint**

```bash
bin/rubocop
```

Fix any offenses, then re-run to confirm clean.

- [ ] **Step 3: Commit any lint fixes**

```bash
git add -u
git commit -m "chore: rubocop fixes for Q&A feature"
```

(Skip if nothing to fix.)
