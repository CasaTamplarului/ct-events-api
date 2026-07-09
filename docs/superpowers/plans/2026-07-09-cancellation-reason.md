# Cancellation Reason & Admin Push Alert — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store an optional reason (preset key + free text) when a user cancels a booking, and fire a push notification to all admin users immediately after.

**Architecture:** Two nullable columns on `attendees` capture the reason. Both cancel endpoints in `BookingsController` accept and validate the new optional params, write them alongside the status change, then enqueue `SendCancellationAlertJob`. The job calls `FcmService.send_to_user` for every admin user with a human-readable Romanian message.

**Tech Stack:** Rails 7.1 migration, existing `FcmService`, new `ApplicationJob` subclass, RSpec.

## Global Constraints

- Preset keys (exact): `cant_attend`, `health`, `financial`, `plans_changed`, `other`
- Romanian labels (exact): `cant_attend` → `"Nu pot participa"`, `health` → `"Motive de sănătate"`, `financial` → `"Motive financiare"`, `plans_changed` → `"Schimbare de planuri"`, `other` → `"Altele"`
- Fallback label when no reason: `"Nespecificat"`
- Push title format: `"Anulare bilet — #{event_name}"` (ro-RO translation)
- Push body format: `"#{first_name} #{last_name} și-a anulat locul. Motiv: #{reason_label}"`
- Push `preference:` must be `nil` so admin preference flags are not checked
- Both new columns are nullable — omitting `reason` is not an error
- Invalid `reason` value → `422 { error: "Invalid cancellation reason" }`
- `SendCancellationAlertJob` is enqueued with `perform_later` after the DB write

---

### Task 1: Migration + `CANCELLATION_REASONS` constant

**Files:**
- Create: `db/migrate/20260709200000_add_cancellation_reason_to_attendees.rb`
- Modify: `app/models/attendee.rb`
- Test: `spec/models/attendee_spec.rb`

**Interfaces:**
- Produces: `Attendee::CANCELLATION_REASONS` — array of 5 string keys used by Tasks 2 and 3

- [ ] **Step 1: Write the failing spec**

Add to `spec/models/attendee_spec.rb` (create the file if it does not exist):

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Attendee, type: :model do
  describe 'CANCELLATION_REASONS' do
    it 'includes all expected preset keys' do
      expect(Attendee::CANCELLATION_REASONS).to match_array(
        %w[cant_attend health financial plans_changed other]
      )
    end
  end

  describe 'cancellation_reason column' do
    it 'defaults to nil' do
      attendee = build(:attendee)
      expect(attendee.cancellation_reason).to be_nil
    end
  end

  describe 'cancellation_reason_text column' do
    it 'defaults to nil' do
      attendee = build(:attendee)
      expect(attendee.cancellation_reason_text).to be_nil
    end
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
bundle exec rspec spec/models/attendee_spec.rb --format documentation 2>&1 | tail -10
```

Expected: 3 failures — `CANCELLATION_REASONS` uninitialized, columns don't exist.

- [ ] **Step 3: Generate and write the migration**

```bash
bin/rails generate migration AddCancellationReasonToAttendees cancellation_reason:string cancellation_reason_text:text
```

Open the generated file and confirm it looks like:

```ruby
class AddCancellationReasonToAttendees < ActiveRecord::Migration[7.1]
  def change
    add_column :attendees, :cancellation_reason, :string
    add_column :attendees, :cancellation_reason_text, :text
  end
end
```

- [ ] **Step 4: Run the migration**

```bash
bin/rails db:migrate
```

Expected: migration runs, `attendees` table gains two nullable columns.

Also migrate the production DB (port 5433):

```bash
DATABASE_PORT=5433 bin/rails db:migrate
```

- [ ] **Step 5: Add `CANCELLATION_REASONS` to `Attendee`**

Open `app/models/attendee.rb`. Find the line:

```ruby
ALLERGY_OPTIONS = %w[gluten lactose nuts eggs soy fish shellfish].freeze
```

Add directly below it:

```ruby
CANCELLATION_REASONS = %w[cant_attend health financial plans_changed other].freeze
```

- [ ] **Step 6: Run the spec**

```bash
bundle exec rspec spec/models/attendee_spec.rb --format documentation
```

Expected: 3 examples, 0 failures.

- [ ] **Step 7: Commit**

```bash
git add db/migrate/ app/models/attendee.rb spec/models/attendee_spec.rb
git commit -m "feat: add cancellation_reason columns to attendees and CANCELLATION_REASONS constant"
```

---

### Task 2: BookingsController — reason params, validation, job enqueue

**Files:**
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`
- Modify: `spec/requests/api/v1/auth/me/bookings_spec.rb`

**Interfaces:**
- Consumes: `Attendee::CANCELLATION_REASONS` (Task 1), `SendCancellationAlertJob` (Task 3 — reference by name only; job must exist before full integration tests run, but the controller code can be written now)
- Produces: updated `cancel_order` and `cancel_attendee` that accept `reason` + `reason_text` params and enqueue `SendCancellationAlertJob.perform_later(attendee_id)`

- [ ] **Step 1: Write the failing specs**

Open `spec/requests/api/v1/auth/me/bookings_spec.rb`.

Find the `describe 'DELETE /api/v1/auth/me/bookings/:order_reference'` block (around line 368). **Inside that block**, add these examples after the last existing example:

```ruby
describe 'cancellation reason' do
  before { allow(SendCancellationAlertJob).to receive(:perform_later) }

  it 'stores reason and reason_text on the cancelled attendee' do
    delete "/api/v1/auth/me/bookings/#{order.order_reference}",
           params: { reason: 'health', reason_text: 'Recuperare dupa operatie' }.to_json,
           headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(attendee.reload.cancellation_reason).to eq('health')
    expect(attendee.reload.cancellation_reason_text).to eq('Recuperare dupa operatie')
  end

  it 'returns 422 for an invalid reason' do
    delete "/api/v1/auth/me/bookings/#{order.order_reference}",
           params: { reason: 'not_a_reason' }.to_json,
           headers: auth_headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']).to eq('Invalid cancellation reason')
  end

  it 'stores nil for both columns when no reason is provided' do
    delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
    expect(attendee.reload.cancellation_reason).to be_nil
    expect(attendee.reload.cancellation_reason_text).to be_nil
  end

  it 'enqueues SendCancellationAlertJob with the attendee id' do
    delete "/api/v1/auth/me/bookings/#{order.order_reference}", headers: auth_headers
    expect(SendCancellationAlertJob).to have_received(:perform_later).with(attendee.id)
  end
end
```

Find the `describe 'DELETE /api/v1/auth/me/bookings/:order_reference/attendees/:id'` block (around line 430). Add inside that block after the last existing example:

```ruby
describe 'cancellation reason' do
  before { allow(SendCancellationAlertJob).to receive(:perform_later) }

  it 'stores reason and reason_text on the cancelled attendee' do
    delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
           params: { reason: 'plans_changed', reason_text: 'Alt eveniment' }.to_json,
           headers: auth_headers
    expect(response).to have_http_status(:ok)
    expect(attendee.reload.cancellation_reason).to eq('plans_changed')
    expect(attendee.reload.cancellation_reason_text).to eq('Alt eveniment')
  end

  it 'returns 422 for an invalid reason' do
    delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
           params: { reason: 'bogus' }.to_json,
           headers: auth_headers
    expect(response).to have_http_status(:unprocessable_content)
    expect(json['error']).to eq('Invalid cancellation reason')
  end

  it 'stores nil for both columns when no reason is provided' do
    delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
           headers: auth_headers
    expect(attendee.reload.cancellation_reason).to be_nil
    expect(attendee.reload.cancellation_reason_text).to be_nil
  end

  it 'enqueues SendCancellationAlertJob with the attendee id' do
    delete "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}",
           headers: auth_headers
    expect(SendCancellationAlertJob).to have_received(:perform_later).with(attendee.id)
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
bundle exec rspec spec/requests/api/v1/auth/me/bookings_spec.rb --format progress 2>&1 | tail -10
```

Expected: 8 new failures — `SendCancellationAlertJob` undefined, columns not written, no validation.

- [ ] **Step 3: Update `cancel_order`**

In `app/controllers/api/v1/auth/me/bookings_controller.rb`, replace the entire `cancel_order` method:

```ruby
def cancel_order
  order = Order.find_by(order_reference: params[:order_reference])
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

  user_attendees = order.attendees.where(user_id: current_user.id)
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found if user_attendees.empty?

  cancellable = user_attendees.where(payment_status: :payment_pending)
  if cancellable.empty?
    return render json: { error: I18n.t('bookings.errors.nothing_to_cancel') },
                  status: :unprocessable_content
  end

  reason      = params[:reason].presence
  reason_text = params[:reason_text].presence

  if reason && !Attendee::CANCELLATION_REASONS.include?(reason)
    return render json: { error: 'Invalid cancellation reason' }, status: :unprocessable_content
  end

  first_cancelled_id = cancellable.pick(:id)

  # rubocop:disable Rails/SkipsModelValidations
  cancellable.update_all(
    payment_status:           Attendee.payment_statuses['attendee_cancelled'],
    cancellation_reason:      reason,
    cancellation_reason_text: reason_text
  )
  # rubocop:enable Rails/SkipsModelValidations

  SendCancellationAlertJob.perform_later(first_cancelled_id) if first_cancelled_id

  render json: serialise_order(order, attendees_for_response(order))
end
```

- [ ] **Step 4: Update `cancel_attendee`**

Replace the entire `cancel_attendee` method:

```ruby
def cancel_attendee
  order = Order.find_by(order_reference: params[:order_reference])
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

  attendee = order.attendees.find_by(id: params[:id], user_id: current_user.id)
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

  unless attendee.payment_pending?
    return render json: { error: I18n.t('bookings.errors.cannot_cancel') },
                  status: :unprocessable_content
  end

  reason      = params[:reason].presence
  reason_text = params[:reason_text].presence

  if reason && !Attendee::CANCELLATION_REASONS.include?(reason)
    return render json: { error: 'Invalid cancellation reason' }, status: :unprocessable_content
  end

  attendee.update!(
    payment_status:           :attendee_cancelled,
    cancellation_reason:      reason,
    cancellation_reason_text: reason_text
  )

  SendCancellationAlertJob.perform_later(attendee.id)

  render json: serialise_order(order, attendees_for_response(order))
end
```

- [ ] **Step 5: Create a stub job so specs can load**

Create `app/jobs/send_cancellation_alert_job.rb` with just enough to satisfy the constant reference:

```ruby
# frozen_string_literal: true

class SendCancellationAlertJob < ApplicationJob
  queue_as :default

  def perform(attendee_id)
    # implemented in Task 3
  end
end
```

- [ ] **Step 6: Run the specs**

```bash
bundle exec rspec spec/requests/api/v1/auth/me/bookings_spec.rb --format progress
```

Expected: all examples pass, 0 failures.

- [ ] **Step 7: Run rubocop**

```bash
bundle exec rubocop app/controllers/api/v1/auth/me/bookings_controller.rb
```

Fix any offenses.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/api/v1/auth/me/bookings_controller.rb \
        app/jobs/send_cancellation_alert_job.rb \
        spec/requests/api/v1/auth/me/bookings_spec.rb
git commit -m "feat: accept cancellation reason in cancel_order and cancel_attendee, enqueue alert job"
```

---

### Task 3: `SendCancellationAlertJob` — full implementation

**Files:**
- Modify: `app/jobs/send_cancellation_alert_job.rb` (replace stub from Task 2)
- Create: `spec/jobs/send_cancellation_alert_job_spec.rb`

**Interfaces:**
- Consumes: `Attendee::CANCELLATION_REASONS` (Task 1), `FcmService.send_to_user(user:, title:, body:, preference: nil)`
- Produces: nothing (side-effect: FCM push to each admin user)

- [ ] **Step 1: Write the failing spec**

Create `spec/jobs/send_cancellation_alert_job_spec.rb`:

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SendCancellationAlertJob, type: :job do
  let(:event) { create(:event) }
  let!(:ro_translation) do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Fara Regrete')
  end
  let(:order)    { create(:order) }
  let(:user)     { create(:user, first_name: 'Ion', last_name: 'Pop', email: 'ion@example.com') }
  let!(:attendee) do
    create(:attendee, event: event, order: order, user: user,
                      first_name: 'Ion', last_name: 'Pop',
                      payment_status: :attendee_cancelled,
                      cancellation_reason: 'health')
  end
  let!(:admin) { create(:user, role: 'admin', email: 'admin@example.com') }

  before { allow(FcmService).to receive(:send_to_user) }

  def perform(id = attendee.id)
    described_class.new.perform(id)
  end

  it 'calls FcmService.send_to_user for each admin user' do
    perform
    expect(FcmService).to have_received(:send_to_user).with(hash_including(user: admin))
  end

  it 'includes the event name in the push title' do
    perform
    expect(FcmService).to have_received(:send_to_user).with(
      hash_including(title: 'Anulare bilet — Fara Regrete')
    )
  end

  it 'includes the attendee name and Romanian reason label in the body' do
    perform
    expect(FcmService).to have_received(:send_to_user).with(
      hash_including(body: 'Ion Pop și-a anulat locul. Motiv: Motive de sănătate')
    )
  end

  it 'uses "Nespecificat" when cancellation_reason is nil' do
    attendee.update_columns(cancellation_reason: nil)
    perform
    expect(FcmService).to have_received(:send_to_user).with(
      hash_including(body: include('Nespecificat'))
    )
  end

  it 'sends with preference: nil so admin push preferences are not checked' do
    perform
    expect(FcmService).to have_received(:send_to_user).with(
      hash_including(preference: nil)
    )
  end

  it 'does not call FcmService for non-admin users' do
    perform
    expect(FcmService).not_to have_received(:send_to_user).with(
      hash_including(user: user)
    )
  end

  it 'does nothing when the attendee is not found' do
    expect { perform(0) }.not_to raise_error
    expect(FcmService).not_to have_received(:send_to_user)
  end
end
```

- [ ] **Step 2: Run to verify failures**

```bash
bundle exec rspec spec/jobs/send_cancellation_alert_job_spec.rb --format documentation 2>&1 | tail -15
```

Expected: most examples fail — stub job body is a no-op, so `FcmService` never receives the call.

- [ ] **Step 3: Implement the job**

Replace the full contents of `app/jobs/send_cancellation_alert_job.rb`:

```ruby
# frozen_string_literal: true

class SendCancellationAlertJob < ApplicationJob
  queue_as :default

  REASON_LABELS = {
    'cant_attend'   => 'Nu pot participa',
    'health'        => 'Motive de sănătate',
    'financial'     => 'Motive financiare',
    'plans_changed' => 'Schimbare de planuri',
    'other'         => 'Altele'
  }.freeze

  def perform(attendee_id)
    attendee = Attendee.includes(event: :events_translations).find_by(id: attendee_id)
    return unless attendee

    event_name   = attendee.event
                           .events_translations
                           .find { |t| t.languages_code == 'ro-RO' }
                           &.name
                           .to_s
    reason_label = REASON_LABELS[attendee.cancellation_reason] || 'Nespecificat'

    title = "Anulare bilet — #{event_name}"
    body  = "#{attendee.first_name} #{attendee.last_name} și-a anulat locul. Motiv: #{reason_label}"

    User.where(role: 'admin').find_each do |admin|
      FcmService.send_to_user(
        user:       admin,
        title:      title,
        body:       body,
        preference: nil
      )
    end
  end
end
```

- [ ] **Step 4: Run the specs**

```bash
bundle exec rspec spec/jobs/send_cancellation_alert_job_spec.rb --format documentation
```

Expected: 7 examples, 0 failures.

- [ ] **Step 5: Run the full suite**

```bash
bundle exec rspec --format progress 2>&1 | tail -5
```

Expected: existing examples still pass (only the 2 pre-existing push_notification failures).

- [ ] **Step 6: Run rubocop**

```bash
bundle exec rubocop app/jobs/send_cancellation_alert_job.rb
```

Fix any offenses.

- [ ] **Step 7: Commit**

```bash
git add app/jobs/send_cancellation_alert_job.rb spec/jobs/send_cancellation_alert_job_spec.rb
git commit -m "feat: implement SendCancellationAlertJob — push FCM alert to admins on booking cancellation"
```
