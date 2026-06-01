# Google Wallet Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `GET /api/v1/auth/me/bookings/:order_reference/wallet/google` — returns a Google Wallet save URL for an order (one pass per order, QR = order reference).

**Architecture:** A new `GoogleWalletService` handles all Google interaction: it upserts an `EventTicketClass` (per event) and an `EventTicketObject` (per order) via the Google Wallet REST API on every request (POST to create, PUT on 409), then signs a JWT with the service account key. The existing `BookingsController` gets a new `wallet_google` action — no new controller needed since auth setup is already there.

**Tech Stack:** Rails 8, `googleauth` gem (service account OAuth2), `jwt` gem (already in Gemfile), `Net::HTTP` (stdlib), WebMock + RSpec for tests.

---

## File Map

| Action | File | Purpose |
|--------|------|---------|
| Modify | `Gemfile` | Add `googleauth` |
| Create | `app/services/google_wallet_service.rb` | Upsert class + object, sign JWT |
| Modify | `app/controllers/api/v1/auth/me/bookings_controller.rb` | Add `wallet_google` action |
| Modify | `config/routes.rb` | Add wallet route |
| Create | `spec/services/google_wallet_service_spec.rb` | Unit tests for service |
| Create | `spec/requests/api/v1/auth/me/bookings/wallet_spec.rb` | Request spec |

---

## Task 1: Add `googleauth` gem

- [ ] **Step 1: Add gem to Gemfile**

In `Gemfile`, after the `gem 'jwt'` line, add:

```ruby
gem 'googleauth'
```

- [ ] **Step 2: Install**

```bash
bundle install
```

Expected: resolves and installs `googleauth` and its dependencies (`signet`, `google-apis-core` family).

- [ ] **Step 3: Commit**

```bash
git add Gemfile Gemfile.lock
git commit -m "Add googleauth gem for Google Wallet service account auth"
```

---

## Task 2: `GoogleWalletService` — tests then implementation

### Files
- Create: `spec/services/google_wallet_service_spec.rb`
- Create: `app/services/google_wallet_service.rb`

- [ ] **Step 1: Create the spec file**

```ruby
# frozen_string_literal: true

require 'rails_helper'
require 'cgi'

RSpec.describe GoogleWalletService do
  let(:private_key) { OpenSSL::PKey::RSA.generate(1024) }
  let(:sa_json) do
    {
      type: 'service_account',
      client_email: 'wallet@test.iam.gserviceaccount.com',
      private_key: private_key.to_pem,
      private_key_id: 'key-id-123',
      token_uri: 'https://oauth2.googleapis.com/token'
    }.to_json
  end
  let(:issuer_id) { '1234567890' }

  let(:event) do
    create(:event,
           slug: 'midsummer-gala',
           location_name: 'Casa Tâmplarului',
           start_date: 2.weeks.from_now,
           end_date: 2.weeks.from_now + 4.hours)
  end
  let!(:translation) { create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Gala de Vară') }
  let(:order)        { create(:order) }
  let!(:attendee)    { create(:attendee, order: order, event: event, payment_status: :paid) }

  let(:class_id)  { "#{issuer_id}.#{event.slug.gsub(/[^a-zA-Z0-9_]/, '_')}" }
  let(:object_id) { "#{issuer_id}.#{order.order_reference.gsub(/[^a-zA-Z0-9_]/, '_')}" }

  around do |example|
    orig_issuer = ENV['GOOGLE_WALLET_ISSUER_ID']
    orig_sa     = ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON']
    ENV['GOOGLE_WALLET_ISSUER_ID']            = issuer_id
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = sa_json
    example.run
  ensure
    ENV['GOOGLE_WALLET_ISSUER_ID']            = orig_issuer
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = orig_sa
  end

  before do
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(
        status: 200,
        body: { access_token: 'fake-token', token_type: 'Bearer', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

  subject(:service) { described_class.new(order: order, language: 'ro-RO') }

  # ── Initialization ──────────────────────────────────────────────────────────

  describe 'initialization' do
    context 'when GOOGLE_WALLET_ISSUER_ID is not set' do
      around do |example|
        ENV.delete('GOOGLE_WALLET_ISSUER_ID')
        example.run
      ensure
        ENV['GOOGLE_WALLET_ISSUER_ID'] = issuer_id
      end

      it 'raises ArgumentError' do
        expect { described_class.new(order: order, language: 'ro-RO') }
          .to raise_error(ArgumentError, /GOOGLE_WALLET_ISSUER_ID/)
      end
    end

    context 'when GOOGLE_WALLET_SERVICE_ACCOUNT_JSON is not set' do
      around do |example|
        ENV.delete('GOOGLE_WALLET_SERVICE_ACCOUNT_JSON')
        example.run
      ensure
        ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = sa_json
      end

      it 'raises ArgumentError' do
        expect { described_class.new(order: order, language: 'ro-RO') }
          .to raise_error(ArgumentError, /GOOGLE_WALLET_SERVICE_ACCOUNT_JSON/)
      end
    end
  end

  # ── #save_url ────────────────────────────────────────────────────────────────

  describe '#save_url' do
    before do
      stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject')
        .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
    end

    it 'returns a Google Wallet save URL' do
      expect(service.save_url).to start_with('https://pay.google.com/gp/v/save/')
    end

    it 'sends the class request with the correct event data' do
      service.save_url
      expect(WebMock).to have_requested(:post,
                                        'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
        .with { |req|
          body = JSON.parse(req.body)
          body['id'] == class_id &&
            body.dig('eventName', 'defaultValue', 'value') == 'Gala de Vară' &&
            body.dig('venue', 'name', 'defaultValue', 'value') == 'Casa Tâmplarului'
        }
    end

    it 'sends the object request with the correct order data' do
      service.save_url
      expect(WebMock).to have_requested(:post,
                                        'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject')
        .with { |req|
          body = JSON.parse(req.body)
          body['id'] == object_id &&
            body['classId'] == class_id &&
            body.dig('barcode', 'type') == 'QR_CODE' &&
            body.dig('barcode', 'value') == order.order_reference
        }
    end

    context 'when the class already exists (409)' do
      before do
        stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
          .to_return(status: 409, body: '{}', headers: { 'Content-Type' => 'application/json' })
        stub_request(:put, "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass/#{class_id}")
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'falls back to PUT and still returns a URL' do
        expect(service.save_url).to start_with('https://pay.google.com/gp/v/save/')
        expect(WebMock).to have_requested(:put,
                                          "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass/#{class_id}")
      end
    end

    context 'when the object already exists (409)' do
      before do
        stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject')
          .to_return(status: 409, body: '{}', headers: { 'Content-Type' => 'application/json' })
        stub_request(:put, "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject/#{object_id}")
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'falls back to PUT and still returns a URL' do
        expect(service.save_url).to start_with('https://pay.google.com/gp/v/save/')
        expect(WebMock).to have_requested(:put,
                                          "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject/#{object_id}")
      end
    end

    context 'when the wallet API returns a server error' do
      before do
        stub_request(:post, 'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
          .to_return(status: 500, body: '{"error":"internal"}')
      end

      it 'raises ApiError' do
        expect { service.save_url }.to raise_error(GoogleWalletService::ApiError)
      end
    end
  end
end
```

- [ ] **Step 2: Run the spec — verify it fails with uninitialized constant**

```bash
bin/rspec spec/services/google_wallet_service_spec.rb
```

Expected: all examples fail with `NameError: uninitialized constant GoogleWalletService`

- [ ] **Step 3: Create the service**

```ruby
# frozen_string_literal: true

require 'googleauth'
require 'net/http'

class GoogleWalletService
  class ApiError < StandardError; end

  WALLET_API_BASE = 'https://walletobjects.googleapis.com/walletobjects/v1'
  SCOPES = ['https://www.googleapis.com/auth/wallet_object.issuer'].freeze

  def initialize(order:, language:)
    @order     = order
    @language  = language
    @issuer_id = ENV.fetch('GOOGLE_WALLET_ISSUER_ID') { raise ArgumentError, 'GOOGLE_WALLET_ISSUER_ID is not set' }
    sa_json    = ENV.fetch('GOOGLE_WALLET_SERVICE_ACCOUNT_JSON') { raise ArgumentError, 'GOOGLE_WALLET_SERVICE_ACCOUNT_JSON is not set' }
    parsed = JSON.parse(sa_json)
    @service_account_email = parsed['client_email']
    @private_key = OpenSSL::PKey::RSA.new(parsed['private_key'])
    @credentials = Google::Auth::ServiceAccountCredentials.make_creds(
      json_key_io: StringIO.new(sa_json),
      scope: SCOPES
    )
  end

  def save_url
    upsert_class
    upsert_object
    "https://pay.google.com/gp/v/save/#{signed_jwt}"
  end

  private

    def event
      @event ||= begin
        att = @order.attendees.includes(event: :events_translations).first
        raise ApiError, 'Order has no attendees' unless att

        att.event
      end
    end

    def event_name
      translations = event.events_translations
      (translations.find { |t| t.languages_code == @language } ||
       translations.find { |t| t.languages_code == 'ro-RO' })&.name.to_s
    end

    def class_id
      "#{@issuer_id}.#{sanitize_id(event.slug)}"
    end

    def object_id
      "#{@issuer_id}.#{sanitize_id(@order.order_reference)}"
    end

    def sanitize_id(str)
      str.gsub(/[^a-zA-Z0-9_]/, '_')
    end

    def access_token
      @credentials.fetch_access_token!['access_token']
    end

    def upsert_class
      body = {
        id: class_id,
        issuerName: 'Casa Tâmplarului',
        eventName: { defaultValue: { language: 'ro', value: event_name } },
        venue: { name: { defaultValue: { language: 'ro', value: event.location_name.to_s } } },
        dateTime: { start: event.start_date.iso8601 }
      }
      body[:dateTime][:end] = event.end_date.iso8601 if event.end_date
      upsert_resource('eventTicketClass', class_id, body)
    end

    def upsert_object
      body = {
        id: object_id,
        classId: class_id,
        state: 'ACTIVE',
        barcode: { type: 'QR_CODE', value: @order.order_reference }
      }
      upsert_resource('eventTicketObject', object_id, body)
    end

    def upsert_resource(collection, id, body)
      token = access_token
      post_response = wallet_request(:post, collection, body, token)
      return if post_response.code.to_i.between?(200, 299)

      if post_response.code == '409'
        put_response = wallet_request(:put, "#{collection}/#{id}", body, token)
        raise ApiError, "PUT #{put_response.code}: #{put_response.body}" unless put_response.code.to_i.between?(200, 299)

        return
      end

      raise ApiError, "POST #{post_response.code}: #{post_response.body}"
    end

    def wallet_request(method, path, body, token)
      uri = URI("#{WALLET_API_BASE}/#{path}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = method == :post ? Net::HTTP::Post.new(uri) : Net::HTTP::Put.new(uri)
      request['Authorization'] = "Bearer #{token}"
      request['Content-Type']  = 'application/json'
      request.body = body.to_json
      http.request(request)
    end

    def signed_jwt
      payload = {
        iss: @service_account_email,
        aud: 'google',
        typ: 'savetowallet',
        iat: Time.now.to_i,
        payload: { eventTicketObjects: [{ id: object_id }] }
      }
      JWT.encode(payload, @private_key, 'RS256')
    end
end
```

- [ ] **Step 4: Run the spec — verify it passes**

```bash
bin/rspec spec/services/google_wallet_service_spec.rb
```

Expected: all examples pass

- [ ] **Step 5: Commit**

```bash
git add app/services/google_wallet_service.rb spec/services/google_wallet_service_spec.rb
git commit -m "Add GoogleWalletService with upsert and JWT signing"
```

---

## Task 3: Route + controller action

### Files
- Create: `spec/requests/api/v1/auth/me/bookings/wallet_spec.rb`
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`

- [ ] **Step 1: Create the request spec**

```ruby
# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'GET /api/v1/auth/me/bookings/:order_reference/wallet/google' do
  let(:user)       { create(:user) }
  let(:token)      { JwtService.encode(user.id) }
  let(:headers)    { auth_headers(token) }
  let(:event)      { create(:event, slug: 'test-event', start_date: 1.week.from_now, end_date: 1.week.from_now + 3.hours) }
  let(:order_user) { user }
  let(:order)      { create(:order, user: order_user) }
  let!(:attendee)  { create(:attendee, order: order, event: event, user: user, payment_status: :paid) }

  let(:private_key) { OpenSSL::PKey::RSA.generate(1024) }
  let(:sa_json) do
    {
      type: 'service_account',
      client_email: 'wallet@test.iam.gserviceaccount.com',
      private_key: private_key.to_pem,
      private_key_id: 'key-id-123',
      token_uri: 'https://oauth2.googleapis.com/token'
    }.to_json
  end

  around do |example|
    orig_issuer = ENV['GOOGLE_WALLET_ISSUER_ID']
    orig_sa     = ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON']
    ENV['GOOGLE_WALLET_ISSUER_ID']            = '1234567890'
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = sa_json
    example.run
  ensure
    ENV['GOOGLE_WALLET_ISSUER_ID']            = orig_issuer
    ENV['GOOGLE_WALLET_SERVICE_ACCOUNT_JSON'] = orig_sa
  end

  before do
    stub_request(:post, 'https://oauth2.googleapis.com/token')
      .to_return(
        status: 200,
        body: { access_token: 'fake-token', token_type: 'Bearer', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    stub_request(:post, /walletobjects\.googleapis\.com/)
      .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  context 'when the user owns the order' do
    it 'returns 200 with a Google Wallet URL' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/google", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['url']).to start_with('https://pay.google.com/gp/v/save/')
    end
  end

  context 'when the user is an attendee but not the order owner' do
    let(:order_user) { create(:user) }

    it 'returns 200 with a Google Wallet URL' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/google", headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['url']).to start_with('https://pay.google.com/gp/v/save/')
    end
  end

  context 'when no authentication token is provided' do
    it 'returns 401' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/google"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'when the order reference does not exist' do
    it 'returns 404' do
      get '/api/v1/auth/me/bookings/CT-2026-XXXXXX/wallet/google', headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the user has no access to the order' do
    let(:other_user) { create(:user) }
    let(:other_order) { create(:order, user: other_user) }
    let!(:other_attendee) do
      create(:attendee, order: other_order, event: event, user: other_user, payment_status: :paid)
    end

    it 'returns 404' do
      get "/api/v1/auth/me/bookings/#{other_order.order_reference}/wallet/google", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 2: Run the spec — verify it fails with routing error**

```bash
bin/rspec spec/requests/api/v1/auth/me/bookings/wallet_spec.rb
```

Expected: all examples fail with `ActionController::RoutingError` (route not yet defined)

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the `scope '/me/bookings'` block, add after the existing `delete` lines:

```ruby
get ':order_reference/wallet/google', to: 'me/bookings#wallet_google', as: 'google_wallet_booking'
```

The block should look like:

```ruby
scope '/me/bookings' do
  get  :upcoming, to: 'me/bookings#upcoming'
  get  :past,     to: 'me/bookings#past'
  post :check,    to: 'me/bookings#check'
  delete ':order_reference',                to: 'me/bookings#cancel_order',    as: 'cancel_booking'
  delete ':order_reference/attendees/:id',  to: 'me/bookings#cancel_attendee', as: 'cancel_booking_attendee'
  get ':order_reference/wallet/google',     to: 'me/bookings#wallet_google',   as: 'google_wallet_booking'
end
```

- [ ] **Step 4: Add the `wallet_google` action to `BookingsController`**

In `app/controllers/api/v1/auth/me/bookings_controller.rb`, add after the `cancel_attendee` method and before the `private` keyword:

```ruby
def wallet_google
  order = Order.find_by(order_reference: params[:order_reference])
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

  authorized = order.user_id == current_user.id ||
               order.attendees.where(user_id: current_user.id).exists?
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless authorized

  lang = current_user.language || 'ro-RO'
  url  = GoogleWalletService.new(order: order, language: lang).save_url
  render json: { url: url }
rescue GoogleWalletService::ApiError => e
  Rails.logger.error("Google Wallet error for #{order.order_reference}: #{e.message}")
  render json: { error: 'Internal server error' }, status: :internal_server_error
end
```

- [ ] **Step 5: Run the spec — verify it passes**

```bash
bin/rspec spec/requests/api/v1/auth/me/bookings/wallet_spec.rb
```

Expected: all examples pass

- [ ] **Step 6: Run the full suite to check for regressions**

```bash
bin/rails test && bin/rspec
```

Expected: all tests pass

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb \
        app/controllers/api/v1/auth/me/bookings_controller.rb \
        spec/requests/api/v1/auth/me/bookings/wallet_spec.rb
git commit -m "Add Google Wallet pass endpoint"
```

---

## Credentials Setup (non-code, do after implementation)

Add to `.env`:

```
GOOGLE_WALLET_SERVICE_ACCOUNT_JSON={"type":"service_account",...}
GOOGLE_WALLET_ISSUER_ID=<your-issuer-id-from-google-pay-console>
```

Add the same keys to Rails encrypted credentials for production:

```bash
bin/rails credentials:edit
```

```yaml
google_wallet:
  service_account_json: '{"type":"service_account",...}'
  issuer_id: "1234567890123456789"
```

Note: if you prefer to read from credentials instead of ENV in production, update `GoogleWalletService#initialize` to fall back to `Rails.application.credentials.dig(:google_wallet, :issuer_id)` etc. This is a deploy-time decision.
