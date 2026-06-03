# Per-Attendee QR Codes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give each attendee their own QR code (`CT-2026-XXXXX-<attendee_id>`) surfaced in the bookings list and encoded into a per-attendee Google Wallet pass.

**Architecture:** Three independent changes — add `id`/`qr_code` to the bookings attendee serializer, refactor `GoogleWalletService` to take an attendee instead of an order, and add a new per-attendee wallet endpoint. The scan backend is unchanged; the QR token is parsed on the frontend.

**Tech Stack:** Rails 7.1, RSpec, WebMock, FactoryBot

---

## Task 1: Add `id` and `qr_code` to bookings attendee serializer

**Files:**
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`
- Test: `spec/requests/api/v1/auth/me/bookings_spec.rb`

- [ ] **Step 1: Write the failing test**

In `spec/requests/api/v1/auth/me/bookings_spec.rb`, inside the `describe 'GET /api/v1/auth/me/bookings/upcoming'` → `context 'with a valid JWT'` block, add after the existing `'includes attendee fields with ticket details'` test:

```ruby
it 'includes id and qr_code for each attendee' do
  booking = create_booking(user: user, start_date: 10.days.from_now, end_date: 13.days.from_now)

  get '/api/v1/auth/me/bookings/upcoming', headers: auth_headers

  a = json.first['attendees'].first
  expect(a['id']).to eq(booking[:attendee].id)
  expect(a['qr_code']).to eq("#{booking[:order].order_reference}-#{booking[:attendee].id}")
end
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
bin/rspec spec/requests/api/v1/auth/me/bookings_spec.rb -e "includes id and qr_code" --format documentation
```

Expected: FAIL — `expected nil to eq <attendee.id>` (fields not present in response)

- [ ] **Step 3: Update `serialise_attendee` and `serialise_order` in `bookings_controller.rb`**

Change `serialise_attendee` signature to accept `order_reference` and add the two new fields:

```ruby
def serialise_attendee(attendee, lang, order_reference)
  translation = ticket_translation_for(attendee, lang)
  {
    id: attendee.id,
    qr_code: "#{order_reference}-#{attendee.id}",
    first_name: attendee.first_name,
    last_name: attendee.last_name,
    payment_status: attendee.payment_status,
    ticket_name: translation&.name,
    ticket_description: translation&.description,
    ticket_price: attendee.ticket&.price,
    food_included: attendee.ticket&.food_included,
    dietary_preference: attendee.dietary_preference
  }
end
```

Update the `attendees:` line inside `serialise_order` (the private method, around line 169) to pass the order reference:

```ruby
def serialise_order(order, attendees)
  return nil if attendees.empty?

  event = attendees.first.event
  lang  = current_user.language || 'ro-RO'

  {
    order_reference: order.order_reference,
    payment_status: order.payment_status(attendees),
    total_price: attendees.sum { |a| a.ticket&.price || 0 },
    event: serialise_event(event, lang),
    attendees: attendees.map { |a| serialise_attendee(a, lang, order.order_reference) }
  }
end
```

- [ ] **Step 4: Run the full bookings spec and verify it passes**

```bash
bin/rspec spec/requests/api/v1/auth/me/bookings_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/v1/auth/me/bookings_controller.rb \
        spec/requests/api/v1/auth/me/bookings_spec.rb
git commit -m "$(cat <<'EOF'
Add id and qr_code fields to bookings attendee serializer

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Refactor `GoogleWalletService` to take `attendee:` and update `wallet_google` action

**Files:**
- Modify: `app/services/google_wallet_service.rb`
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`
- Test: `spec/services/google_wallet_service_spec.rb`
- Test: `spec/requests/api/v1/auth/me/bookings/wallet_spec.rb`

- [ ] **Step 1: Update the service spec to use `attendee:` and per-attendee QR token**

Replace the entire `spec/services/google_wallet_service_spec.rb` with:

```ruby
# frozen_string_literal: true

require 'rails_helper'
require 'cgi'

RSpec.describe GoogleWalletService do
  subject(:service) { described_class.new(attendee: attendee, language: 'ro-RO') }

  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
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

  let!(:language) { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }

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

  let(:class_id)         { "#{issuer_id}.#{event.slug.gsub(/[^a-zA-Z0-9_]/, '_')}" }
  let(:qr_token)         { "#{order.order_reference}-#{attendee.id}" }
  let(:ticket_object_id) { "#{issuer_id}.#{qr_token.gsub(/[^a-zA-Z0-9_]/, '_')}" }

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
    stub_request(:post, 'https://www.googleapis.com/oauth2/v4/token')
      .to_return(
        status: 200,
        body: { access_token: 'fake-token', token_type: 'Bearer', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
  end

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
        expect { described_class.new(attendee: attendee, language: 'ro-RO') }
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
        expect { described_class.new(attendee: attendee, language: 'ro-RO') }
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
      expect(WebMock).to(
        have_requested(:post,
                       'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketClass')
          .with do |req|
            body = JSON.parse(req.body)
            body['id'] == class_id &&
              body.dig('eventName', 'defaultValue', 'value') == 'Gala de Vară' &&
              body.dig('venue', 'name', 'defaultValue', 'value') == 'Casa Tâmplarului' &&
              body.dig('dateTime', 'start').is_a?(String) &&
              body.dig('dateTime', 'end').is_a?(String)
          end
      )
    end

    it 'sends the object request with the per-attendee QR token' do
      service.save_url
      expect(WebMock).to(
        have_requested(:post,
                       'https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject')
          .with do |req|
            body = JSON.parse(req.body)
            body['id'] == ticket_object_id &&
              body['classId'] == class_id &&
              body['state'] == 'ACTIVE' &&
              body.dig('barcode', 'type') == 'QR_CODE' &&
              body.dig('barcode', 'value') == qr_token
          end
      )
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
        stub_request(:put, "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject/#{ticket_object_id}")
          .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
      end

      it 'falls back to PUT and still returns a URL' do
        expect(service.save_url).to start_with('https://pay.google.com/gp/v/save/')
        expect(WebMock).to have_requested(:put,
                                          "https://walletobjects.googleapis.com/walletobjects/v1/eventTicketObject/#{ticket_object_id}")
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

    it 'returns a JWT with the correct payload' do
      url = service.save_url
      token = url.split('/').last
      header = JWT.decode(token, nil, false).last
      expect(header['alg']).to eq('RS256')
      decoded = JWT.decode(token, private_key.public_key, true, algorithms: ['RS256']).first
      expect(decoded['aud']).to eq('google')
      expect(decoded['typ']).to eq('savetowallet')
      expect(decoded.dig('payload', 'eventTicketObjects', 0, 'id')).to eq(ticket_object_id)
    end
  end
end
```

- [ ] **Step 2: Run the service spec and verify it fails**

```bash
bin/rspec spec/services/google_wallet_service_spec.rb --format documentation
```

Expected: FAIL — `unknown keyword: attendee` (service still takes `order:`)

- [ ] **Step 3: Rewrite `app/services/google_wallet_service.rb`**

```ruby
# frozen_string_literal: true

require 'googleauth'
require 'net/http'

class GoogleWalletService
  class ApiError < StandardError; end

  WALLET_API_BASE = 'https://walletobjects.googleapis.com/walletobjects/v1'
  SCOPES = ['https://www.googleapis.com/auth/wallet_object.issuer'].freeze

  def initialize(attendee:, language:)
    @attendee  = attendee
    @language  = language
    @issuer_id = ENV.fetch('GOOGLE_WALLET_ISSUER_ID') { raise ArgumentError, 'GOOGLE_WALLET_ISSUER_ID is not set' }
    sa_json = ENV.fetch('GOOGLE_WALLET_SERVICE_ACCOUNT_JSON') do
      raise ArgumentError, 'GOOGLE_WALLET_SERVICE_ACCOUNT_JSON is not set'
    end
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
      @event ||= @attendee.event
    end

    def event_name
      translations = event.events_translations
      (translations.find { |t| t.languages_code == @language } ||
       translations.find { |t| t.languages_code == 'ro-RO' })&.name.to_s
    end

    def class_id
      "#{@issuer_id}.#{sanitize_id(event.slug)}"
    end

    def qr_token
      "#{@attendee.order.order_reference}-#{@attendee.id}"
    end

    def wallet_object_id
      "#{@issuer_id}.#{sanitize_id(qr_token)}"
    end

    def sanitize_id(str)
      str.gsub(/[^a-zA-Z0-9_]/, '_')
    end

    def access_token
      @access_token ||= @credentials.fetch_access_token!['access_token']
    end

    def upsert_class
      body = {
        id: class_id,
        issuerName: 'Casa Tâmplarului',
        reviewStatus: 'UNDER_REVIEW',
        eventName: { defaultValue: { language: 'ro', value: event_name } },
        venue: {
          name: { defaultValue: { language: 'ro', value: event.location_name.to_s } },
          address: { defaultValue: { language: 'ro', value: event.address.to_s } }
        },
        dateTime: { start: event.start_date.iso8601 }
      }
      body[:dateTime][:end] = event.end_date.iso8601 if event.end_date
      hero_url = ApplicationSerializer.asset_url(event.hero_image)
      body[:heroImage] = { sourceUri: { uri: hero_url } } if hero_url
      upsert_resource('eventTicketClass', class_id, body)
    end

    def upsert_object
      body = {
        id: wallet_object_id,
        classId: class_id,
        state: 'ACTIVE',
        barcode: { type: 'QR_CODE', value: qr_token }
      }
      upsert_resource('eventTicketObject', wallet_object_id, body)
    end

    def upsert_resource(collection, id, body)
      token = access_token
      post_response = wallet_request(:post, collection, body, token)
      return if post_response.code.to_i.between?(200, 299)

      if post_response.code == '409'
        put_response = wallet_request(:put, "#{collection}/#{id}", body, token)
        unless put_response.code.to_i.between?(200, 299)
          raise ApiError, "PUT to #{collection}/#{id} failed with status #{put_response.code}"
        end

        return
      end

      raise ApiError, "POST to #{collection} failed with status #{post_response.code}"
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
        payload: { eventTicketObjects: [{ id: wallet_object_id }] }
      }
      JWT.encode(payload, @private_key, 'RS256')
    end
end
```

- [ ] **Step 4: Update the `wallet_google` action in `bookings_controller.rb` to use the refactored service**

Replace the `wallet_google` private method with:

```ruby
def wallet_google
  order = Order.find_by(order_reference: params[:order_reference])
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

  attendee = order.attendees
                  .includes(event: :events_translations)
                  .find_by(user_id: current_user.id)

  if attendee.nil? && order.user_id == current_user.id
    attendee = order.attendees.includes(event: :events_translations).first
  end

  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

  lang = current_user.language || 'ro-RO'
  url  = GoogleWalletService.new(attendee: attendee, language: lang).save_url
  render json: { url: url }
rescue GoogleWalletService::ApiError => e
  Rails.logger.error("Google Wallet error for #{order.order_reference}: #{e.message}")
  render json: { error: 'Internal server error' }, status: :internal_server_error
end
```

- [ ] **Step 5: Run the service spec and the existing wallet spec to verify they pass**

```bash
bin/rspec spec/services/google_wallet_service_spec.rb \
         spec/requests/api/v1/auth/me/bookings/wallet_spec.rb \
         --format documentation
```

Expected: all green

- [ ] **Step 6: Commit**

```bash
git add app/services/google_wallet_service.rb \
        app/controllers/api/v1/auth/me/bookings_controller.rb \
        spec/services/google_wallet_service_spec.rb
git commit -m "$(cat <<'EOF'
Refactor GoogleWalletService to take attendee instead of order

QR token is now per-attendee: CT-YYYY-XXXXX-<attendee_id>.
Update wallet_google action to find the user's attendee for the order.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Add per-attendee wallet endpoint

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`
- Test: `spec/requests/api/v1/auth/me/bookings/wallet_spec.rb`

- [ ] **Step 1: Write failing tests for the new endpoint**

Append a new top-level `RSpec.describe` block to `spec/requests/api/v1/auth/me/bookings/wallet_spec.rb`:

```ruby
RSpec.describe 'GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/google' do
  before do
    Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
    stub_request(:post, 'https://www.googleapis.com/oauth2/v4/token')
      .to_return(
        status: 200,
        body: { access_token: 'fake-token', token_type: 'Bearer', expires_in: 3600 }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    stub_request(:post, /walletobjects\.googleapis\.com/)
      .to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  let(:user)      { create(:user) }
  let(:token)     { JwtService.encode(user.id) }
  let(:headers)   { auth_headers(token) }
  let(:event)     { create(:event, slug: 'test-event', start_date: 1.week.from_now, end_date: 1.week.from_now + 3.hours) }
  let(:order)     { create(:order) }
  let!(:attendee) { create(:attendee, order: order, event: event, user: user, payment_status: :paid) }

  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
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

  def path
    "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}/wallet/google"
  end

  context 'when the attendee belongs to the current user' do
    it 'returns 200 with a Google Wallet URL' do
      get path, headers: headers
      expect(response).to have_http_status(:ok)
      expect(json['url']).to start_with('https://pay.google.com/gp/v/save/')
    end
  end

  context 'when no authentication token is provided' do
    it 'returns 401' do
      get path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'when the order reference does not exist' do
    it 'returns 404' do
      get "/api/v1/auth/me/bookings/CT-2026-XXXXXX/attendees/#{attendee.id}/wallet/google",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the attendee does not belong to the current user' do
    it 'returns 404' do
      other_user     = create(:user)
      other_attendee = create(:attendee, order: order, event: event, user: other_user, payment_status: :paid)
      get "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{other_attendee.id}/wallet/google",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'when the attendee id does not exist in this order' do
    it 'returns 404' do
      get "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/0/wallet/google",
          headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
```

- [ ] **Step 2: Run the new tests and verify they fail**

```bash
bin/rspec spec/requests/api/v1/auth/me/bookings/wallet_spec.rb \
  -e "GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/google" \
  --format documentation
```

Expected: FAIL — `ActionController::RoutingError` (route does not exist yet)

- [ ] **Step 3: Add the route to `config/routes.rb`**

Inside the `scope '/me/bookings'` block, after the existing `':order_reference/wallet/google'` line, add:

```ruby
get ':order_reference/attendees/:id/wallet/google', to: 'me/bookings#wallet_google_attendee',
                                                    as: 'google_wallet_attendee'
```

- [ ] **Step 4: Add the `wallet_google_attendee` action to `bookings_controller.rb`**

Add after the `wallet_google` action (before `private`):

```ruby
def wallet_google_attendee
  order = Order.find_by(order_reference: params[:order_reference])
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

  attendee = order.attendees
                  .includes(event: :events_translations)
                  .find_by(id: params[:id], user_id: current_user.id)
  return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

  lang = current_user.language || 'ro-RO'
  url  = GoogleWalletService.new(attendee: attendee, language: lang).save_url
  render json: { url: url }
rescue GoogleWalletService::ApiError => e
  Rails.logger.error("Google Wallet error for attendee #{attendee.id}: #{e.message}")
  render json: { error: 'Internal server error' }, status: :internal_server_error
end
```

- [ ] **Step 5: Run the new tests and verify they pass**

```bash
bin/rspec spec/requests/api/v1/auth/me/bookings/wallet_spec.rb --format documentation
```

Expected: all green

- [ ] **Step 6: Run the full test suite and fix any rubocop offenses**

```bash
bin/rspec && bin/rubocop
```

Expected: all tests green, no offenses. If rubocop flags method length on `bookings_controller.rb`, add a `# rubocop:disable Metrics/ClassLength` comment at the class level if needed.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb \
        app/controllers/api/v1/auth/me/bookings_controller.rb \
        spec/requests/api/v1/auth/me/bookings/wallet_spec.rb
git commit -m "$(cat <<'EOF'
Add per-attendee Google Wallet endpoint

GET :order_reference/attendees/:id/wallet/google returns a wallet pass
with the attendee's individual QR token (CT-YYYY-XXXXX-<attendee_id>).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```
