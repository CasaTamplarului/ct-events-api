# Apple Wallet Pass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Apple Wallet `.pkpass` generation for event tickets, mirroring the existing Google Wallet endpoints.

**Architecture:** `AppleWalletService` builds a signed `.pkpass` ZIP in memory using `rubyzip` and Ruby's built-in `OpenSSL::PKCS7`. Two new controller actions (`wallet_apple`, `wallet_apple_attendee`) in `me/bookings_controller.rb` stream the binary pass via `send_data`. Credentials come from ENV; the Apple WWDR G4 intermediate cert is committed to the repo.

**Tech Stack:** Ruby on Rails 8, `rubyzip` gem, `openssl` (stdlib), RSpec with FactoryBot.

---

## File Map

| Action | Path |
|--------|------|
| Modify | `Gemfile` |
| Create | `config/apple_wwdr.pem` |
| Create | `public/apple_wallet/icon.png`, `icon@2x.png`, `icon@3x.png`, `logo.png`, `logo@2x.png`, `logo@3x.png` |
| Create | `app/services/apple_wallet_service.rb` |
| Create | `spec/services/apple_wallet_service_spec.rb` |
| Modify | `config/routes.rb` |
| Modify | `app/controllers/api/v1/auth/me/bookings_controller.rb` |
| Create | `spec/requests/api/v1/auth/me/bookings/apple_wallet_spec.rb` |
| Create | `.env.example` |

---

## Task 1: Add `rubyzip` gem

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add the gem**

  Open `Gemfile`. After the `gem 'rqrcode'` line, add:

  ```ruby
  gem 'rubyzip', '~> 2.3'
  ```

- [ ] **Step 2: Install**

  ```bash
  bundle install
  ```

  Expected: `Bundle complete!` with `rubyzip` listed.

- [ ] **Step 3: Commit**

  ```bash
  git add Gemfile Gemfile.lock
  git commit -m "Add rubyzip gem for Apple Wallet pass generation"
  ```

---

## Task 2: Download and commit Apple WWDR G4 certificate

The Apple Worldwide Developer Relations G4 intermediate certificate is required for signing `.pkpass` files. It is a **public** certificate — safe to commit.

**Files:**
- Create: `config/apple_wwdr.pem`

- [ ] **Step 1: Download and convert from DER to PEM**

  ```bash
  curl -s 'https://www.apple.com/certificateauthority/AppleWWDRCAG4.cer' \
    | openssl x509 -inform DER -out config/apple_wwdr.pem
  ```

  Expected: `config/apple_wwdr.pem` is created with `-----BEGIN CERTIFICATE-----` content.

- [ ] **Step 2: Verify it looks right**

  ```bash
  openssl x509 -in config/apple_wwdr.pem -noout -subject -dates
  ```

  Expected output contains `Apple Worldwide Developer Relations` and `notAfter=...2030`.

- [ ] **Step 3: Commit**

  ```bash
  git add config/apple_wwdr.pem
  git commit -m "Bundle Apple WWDR G4 intermediate certificate for Wallet pass signing"
  ```

---

## Task 3: Create placeholder image assets

Apple Wallet requires `icon.png` (29×29), `icon@2x.png` (58×58), `icon@3x.png` (87×87), `logo.png` (160×50), `logo@2x.png` (320×100), `logo@3x.png` (480×150). These are brand assets — commit dark placeholders now; replace with real PNGs before going live.

**Files:**
- Create: `public/apple_wallet/` (6 PNG files)

- [ ] **Step 1: Create the directory and write placeholder PNGs**

  Run this Ruby one-liner from the project root. It writes a minimal valid 1×1 dark PNG to every required path (Apple Wallet renders them at the specified display sizes regardless):

  ```bash
  mkdir -p public/apple_wallet && ruby -e "
  require 'base64'
  # Minimal valid 1x1 dark PNG (#141414)
  data = Base64.decode64('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAAC0lEQVQI12NgAAIABQAABjkB6QAAAABJRU5ErkJggg==')
  %w[icon.png icon@2x.png icon@3x.png logo.png logo@2x.png logo@3x.png].each do |name|
    File.binwrite('public/apple_wallet/' + name, data)
  end
  puts 'Done'
  "
  ```

  Expected: `Done` printed, 6 files present in `public/apple_wallet/`.

- [ ] **Step 2: Commit**

  ```bash
  git add public/apple_wallet/
  git commit -m "Add placeholder Apple Wallet pass image assets"
  ```

---

## Task 4: Write failing AppleWalletService tests

**Files:**
- Create: `spec/services/apple_wallet_service_spec.rb`

- [ ] **Step 1: Write the spec**

  Create `spec/services/apple_wallet_service_spec.rb`:

  ```ruby
  # frozen_string_literal: true

  require 'rails_helper'
  require 'zip'

  RSpec.describe AppleWalletService do
    let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
    let(:certificate) do
      cert = OpenSSL::X509::Certificate.new
      cert.version   = 2
      cert.serial    = 1
      cert.subject   = cert.issuer = OpenSSL::X509::Name.parse('/CN=Pass Type Test/OU=TESTTEAMID/O=Test/C=US')
      cert.public_key = private_key.public_key
      cert.not_before = Time.now
      cert.not_after  = Time.now + 3600
      cert.sign(private_key, OpenSSL::Digest::SHA256.new)
      cert
    end

    let!(:language)    { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }
    let(:event)        { create(:event, location_name: 'Casa Tâmplarului', start_date: 2.weeks.from_now) }
    let!(:translation) { create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Gala de Vară') }
    let(:order)        { create(:order) }
    let(:attendee)     { create(:attendee, order: order, event: event, first_name: 'Ion', last_name: 'Popescu') }

    subject(:service) { described_class.new(attendee: attendee, language: 'ro-RO') }

    around do |example|
      orig_pass_type = ENV['APPLE_WALLET_PASS_TYPE_ID']
      orig_team_id   = ENV['APPLE_WALLET_TEAM_ID']
      orig_cert      = ENV['APPLE_WALLET_CERTIFICATE']
      orig_key       = ENV['APPLE_WALLET_PRIVATE_KEY']

      ENV['APPLE_WALLET_PASS_TYPE_ID'] = 'pass.test.example'
      ENV['APPLE_WALLET_TEAM_ID']      = 'TESTTEAMID'
      ENV['APPLE_WALLET_CERTIFICATE']  = Base64.strict_encode64(certificate.to_pem)
      ENV['APPLE_WALLET_PRIVATE_KEY']  = Base64.strict_encode64(private_key.to_pem)

      example.run
    ensure
      ENV['APPLE_WALLET_PASS_TYPE_ID'] = orig_pass_type
      ENV['APPLE_WALLET_TEAM_ID']      = orig_team_id
      ENV['APPLE_WALLET_CERTIFICATE']  = orig_cert
      ENV['APPLE_WALLET_PRIVATE_KEY']  = orig_key
    end

    # ── Initialization ──────────────────────────────────────────────────────────

    describe 'initialization' do
      %w[APPLE_WALLET_PASS_TYPE_ID APPLE_WALLET_TEAM_ID APPLE_WALLET_CERTIFICATE APPLE_WALLET_PRIVATE_KEY].each do |var|
        context "when #{var} is not set" do
          around do |example|
            orig = ENV[var]
            ENV.delete(var)
            example.run
          ensure
            ENV[var] = orig
          end

          it 'raises ArgumentError' do
            expect { described_class.new(attendee: attendee, language: 'ro-RO') }
              .to raise_error(ArgumentError, /#{var}/)
          end
        end
      end
    end

    # ── #pass_data ───────────────────────────────────────────────────────────────

    describe '#pass_data' do
      subject(:data) { service.pass_data }

      it 'returns a valid ZIP archive' do
        buffer = StringIO.new(data)
        expect { Zip::File.open_buffer(buffer) }.not_to raise_error
      end

      it 'ZIP contains pass.json, manifest.json, and signature' do
        entries = Zip::File.open_buffer(StringIO.new(data)).entries.map(&:name)
        expect(entries).to include('pass.json', 'manifest.json', 'signature')
      end

      it 'ZIP contains all image assets' do
        entries = Zip::File.open_buffer(StringIO.new(data)).entries.map(&:name)
        %w[icon.png icon@2x.png icon@3x.png logo.png logo@2x.png logo@3x.png].each do |img|
          expect(entries).to include(img)
        end
      end

      describe 'pass.json content' do
        let(:pass) do
          zip = Zip::File.open_buffer(StringIO.new(data))
          JSON.parse(zip.find_entry('pass.json').get_input_stream.read)
        end

        it 'sets serialNumber to attendee.qr_code' do
          expect(pass['serialNumber']).to eq(attendee.qr_code)
        end

        it 'sets the QR barcode value to attendee.qr_code' do
          expect(pass.dig('barcodes', 0, 'message')).to eq(attendee.qr_code)
          expect(pass.dig('barcodes', 0, 'format')).to eq('PKBarcodeFormatQR')
        end

        it 'sets the event name as the primary field value' do
          primary = pass.dig('eventTicket', 'primaryFields', 0)
          expect(primary['value']).to eq('Gala de Vară')
        end

        it 'sets the attendee full name in the auxiliary field' do
          auxiliary = pass.dig('eventTicket', 'auxiliaryFields', 0)
          expect(auxiliary['value']).to eq('Ion Popescu')
        end

        it 'sets passTypeIdentifier from ENV' do
          expect(pass['passTypeIdentifier']).to eq('pass.test.example')
        end

        it 'sets teamIdentifier from ENV' do
          expect(pass['teamIdentifier']).to eq('TESTTEAMID')
        end
      end

      describe 'manifest.json content' do
        it 'contains correct SHA1 digest for pass.json' do
          zip          = Zip::File.open_buffer(StringIO.new(data))
          manifest     = JSON.parse(zip.find_entry('manifest.json').get_input_stream.read)
          pass_content = zip.find_entry('pass.json').get_input_stream.read
          expect(manifest['pass.json']).to eq(Digest::SHA1.hexdigest(pass_content))
        end
      end
    end
  end
  ```

- [ ] **Step 2: Run to confirm it fails (service does not exist yet)**

  ```bash
  bundle exec rspec spec/services/apple_wallet_service_spec.rb --no-color 2>&1 | head -20
  ```

  Expected: `NameError: uninitialized constant AppleWalletService` (or similar load error).

---

## Task 5: Implement AppleWalletService

**Files:**
- Create: `app/services/apple_wallet_service.rb`

- [ ] **Step 1: Create the service**

  Create `app/services/apple_wallet_service.rb`:

  ```ruby
  # frozen_string_literal: true

  require 'zip'
  require 'openssl'
  require 'digest'
  require 'base64'

  class AppleWalletService
    class PassGenerationError < StandardError; end

    BACKGROUND_COLOR = 'rgb(20, 20, 20)'
    FOREGROUND_COLOR = 'rgb(255, 255, 255)'
    LABEL_COLOR      = 'rgb(180, 180, 180)'
    WWDR_CERT_PATH   = Rails.root.join('config', 'apple_wwdr.pem')
    ASSETS_PATH      = Rails.root.join('public', 'apple_wallet')
    IMAGE_NAMES      = %w[icon.png icon@2x.png icon@3x.png logo.png logo@2x.png logo@3x.png].freeze

    def initialize(attendee:, language:)
      @attendee     = attendee
      @language     = language
      @pass_type_id = ENV.fetch('APPLE_WALLET_PASS_TYPE_ID') { raise ArgumentError, 'APPLE_WALLET_PASS_TYPE_ID is not set' }
      @team_id      = ENV.fetch('APPLE_WALLET_TEAM_ID')      { raise ArgumentError, 'APPLE_WALLET_TEAM_ID is not set' }
      cert_pem      = Base64.decode64(ENV.fetch('APPLE_WALLET_CERTIFICATE') { raise ArgumentError, 'APPLE_WALLET_CERTIFICATE is not set' })
      key_pem       = Base64.decode64(ENV.fetch('APPLE_WALLET_PRIVATE_KEY')  { raise ArgumentError, 'APPLE_WALLET_PRIVATE_KEY is not set' })
      @certificate  = OpenSSL::X509::Certificate.new(cert_pem)
      @private_key  = OpenSSL::PKey::RSA.new(key_pem)
      @wwdr_cert    = OpenSSL::X509::Certificate.new(File.read(WWDR_CERT_PATH))
    end

    def pass_data
      files     = build_files
      manifest  = build_manifest(files)
      signature = sign_manifest(manifest)
      build_pkpass(files.merge('manifest.json' => manifest, 'signature' => signature))
    rescue PassGenerationError
      raise
    rescue StandardError => e
      raise PassGenerationError, "Failed to generate Apple Wallet pass: #{e.message}"
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

      def build_files
        files = { 'pass.json' => build_pass_json }
        IMAGE_NAMES.each do |name|
          path = ASSETS_PATH.join(name)
          files[name] = File.binread(path) if File.exist?(path)
        end
        files
      end

      def build_pass_json
        {
          formatVersion:      1,
          passTypeIdentifier: @pass_type_id,
          serialNumber:       @attendee.qr_code,
          teamIdentifier:     @team_id,
          organizationName:   'Casa Tâmplarului',
          description:        event_name,
          backgroundColor:    BACKGROUND_COLOR,
          foregroundColor:    FOREGROUND_COLOR,
          labelColor:         LABEL_COLOR,
          eventTicket: {
            primaryFields: [
              { key: 'event', label: 'EVENIMENT', value: event_name }
            ],
            secondaryFields: [
              { key: 'date',  label: 'DATA',    value: event.start_date.strftime('%d %b %Y, %H:%M') },
              { key: 'venue', label: 'LOCAȚIE', value: event.location_name.to_s }
            ],
            auxiliaryFields: [
              { key: 'attendee', label: 'PARTICIPANT',
                value: "#{@attendee.first_name} #{@attendee.last_name}".strip }
            ],
            backFields: [
              { key: 'order', label: 'REFERINȚĂ COMANDĂ', value: @attendee.order.order_reference }
            ]
          },
          barcodes: [
            { message: @attendee.qr_code, format: 'PKBarcodeFormatQR', messageEncoding: 'iso-8859-1' }
          ]
        }.to_json
      end

      def build_manifest(files)
        files.transform_values { |content| Digest::SHA1.hexdigest(content) }.to_json
      end

      def sign_manifest(manifest_json)
        OpenSSL::PKCS7.sign(
          @certificate,
          @private_key,
          manifest_json,
          [@wwdr_cert],
          OpenSSL::PKCS7::DETACHED | OpenSSL::PKCS7::BINARY
        ).to_der
      end

      def build_pkpass(all_files)
        buffer = Zip::OutputStream.write_buffer do |zip|
          all_files.each do |name, content|
            zip.put_next_entry(name)
            zip.write(content)
          end
        end
        buffer.string
      end
  end
  ```

- [ ] **Step 2: Run the tests**

  ```bash
  bundle exec rspec spec/services/apple_wallet_service_spec.rb --no-color
  ```

  Expected: all examples pass, 0 failures.

- [ ] **Step 3: Commit**

  ```bash
  git add app/services/apple_wallet_service.rb spec/services/apple_wallet_service_spec.rb
  git commit -m "Add AppleWalletService with PKCS7-signed pkpass generation"
  ```

---

## Task 6: Add Apple Wallet routes

**Files:**
- Modify: `config/routes.rb`

- [ ] **Step 1: Add the two routes**

  In `config/routes.rb`, find the existing Google Wallet routes block (lines 25-27):

  ```ruby
  get ':order_reference/wallet/google',     to: 'me/bookings#wallet_google',   as: 'google_wallet_booking'
  get ':order_reference/attendees/:id/wallet/google', to: 'me/bookings#wallet_google_attendee',
                                                      as: 'google_wallet_attendee'
  ```

  Add the Apple routes immediately after:

  ```ruby
  get ':order_reference/wallet/google',     to: 'me/bookings#wallet_google',   as: 'google_wallet_booking'
  get ':order_reference/attendees/:id/wallet/google', to: 'me/bookings#wallet_google_attendee',
                                                      as: 'google_wallet_attendee'
  get ':order_reference/wallet/apple',      to: 'me/bookings#wallet_apple',    as: 'apple_wallet_booking'
  get ':order_reference/attendees/:id/wallet/apple',  to: 'me/bookings#wallet_apple_attendee',
                                                      as: 'apple_wallet_attendee'
  ```

- [ ] **Step 2: Verify routes are registered**

  ```bash
  bin/rails routes | grep apple
  ```

  Expected: two lines for `apple_wallet_booking` and `apple_wallet_attendee`.

- [ ] **Step 3: Commit**

  ```bash
  git add config/routes.rb
  git commit -m "Add Apple Wallet routes alongside Google Wallet routes"
  ```

---

## Task 7: Write failing controller request specs

**Files:**
- Create: `spec/requests/api/v1/auth/me/bookings/apple_wallet_spec.rb`

- [ ] **Step 1: Write the spec**

  Create `spec/requests/api/v1/auth/me/bookings/apple_wallet_spec.rb`:

  ```ruby
  # frozen_string_literal: true

  require 'rails_helper'

  RSpec.describe 'GET /api/v1/auth/me/bookings/:order_reference/wallet/apple' do
    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      allow_any_instance_of(AppleWalletService).to receive(:pass_data).and_return('FAKE_PKPASS_DATA')
    end

    let(:user)       { create(:user) }
    let(:token)      { JwtService.encode(user.id) }
    let(:headers)    { auth_headers(token) }
    let(:event)      { create(:event, start_date: 1.week.from_now) }
    let(:order_user) { user }
    let(:order)      { create(:order, user: order_user) }
    let!(:attendee)  { create(:attendee, order: order, event: event, user: user, payment_status: :paid) }

    context 'when the user owns the order' do
      it 'returns 200 with application/vnd.apple.pkpass content type' do
        get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/apple", headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('application/vnd.apple.pkpass')
        expect(response.body).to eq('FAKE_PKPASS_DATA')
      end
    end

    context 'when the user is an attendee but not the order owner' do
      let(:order_user) { create(:user) }

      it 'returns 200 with pkpass content type' do
        get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/apple", headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('application/vnd.apple.pkpass')
      end
    end

    context 'when no authentication token is provided' do
      it 'returns 401' do
        get "/api/v1/auth/me/bookings/#{order.order_reference}/wallet/apple"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when the order reference does not exist' do
      it 'returns 404' do
        get '/api/v1/auth/me/bookings/CT-2026-XXXXXX/wallet/apple', headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the user has no access to the order' do
      it 'returns 404' do
        other_user  = create(:user)
        other_order = create(:order, user: other_user)
        create(:attendee, order: other_order, event: event, user: other_user, payment_status: :paid)
        get "/api/v1/auth/me/bookings/#{other_order.order_reference}/wallet/apple", headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  RSpec.describe 'GET /api/v1/auth/me/bookings/:order_reference/attendees/:id/wallet/apple' do
    before do
      Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' }
      allow_any_instance_of(AppleWalletService).to receive(:pass_data).and_return('FAKE_PKPASS_DATA')
    end

    let(:user)      { create(:user) }
    let(:token)     { JwtService.encode(user.id) }
    let(:headers)   { auth_headers(token) }
    let(:event)     { create(:event, start_date: 1.week.from_now) }
    let(:order)     { create(:order) }
    let!(:attendee) { create(:attendee, order: order, event: event, user: user, payment_status: :paid) }

    def path
      "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{attendee.id}/wallet/apple"
    end

    context 'when the attendee belongs to the current user' do
      it 'returns 200 with pkpass content type' do
        get path, headers: headers
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include('application/vnd.apple.pkpass')
        expect(response.body).to eq('FAKE_PKPASS_DATA')
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
        get "/api/v1/auth/me/bookings/CT-2026-XXXXXX/attendees/#{attendee.id}/wallet/apple",
            headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the attendee does not belong to the current user' do
      it 'returns 404' do
        other_user     = create(:user)
        other_attendee = create(:attendee, order: order, event: event, user: other_user, payment_status: :paid)
        get "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/#{other_attendee.id}/wallet/apple",
            headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when the attendee id does not exist in this order' do
      it 'returns 404' do
        get "/api/v1/auth/me/bookings/#{order.order_reference}/attendees/0/wallet/apple",
            headers: headers
        expect(response).to have_http_status(:not_found)
      end
    end
  end
  ```

- [ ] **Step 2: Run to confirm failures**

  ```bash
  bundle exec rspec spec/requests/api/v1/auth/me/bookings/apple_wallet_spec.rb --no-color 2>&1 | tail -10
  ```

  Expected: failures with `AbstractController::ActionNotFound` or `NoMethodError` (actions don't exist yet).

---

## Task 8: Implement controller actions

**Files:**
- Modify: `app/controllers/api/v1/auth/me/bookings_controller.rb`

- [ ] **Step 1: Add `wallet_apple` action**

  In `app/controllers/api/v1/auth/me/bookings_controller.rb`, find the `wallet_google_attendee` method (ends around line 127). Add the following two methods directly after it, before the `private` keyword:

  ```ruby
  def wallet_apple
    order = Order.find_by(order_reference: params[:order_reference])
    return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

    base     = order.attendees.includes(:order, event: :events_translations)
    attendee = base.find_by(user_id: current_user.id)
    attendee ||= base.order(:id).first if order.user_id == current_user.id

    return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

    lang = current_user.language || 'ro-RO'
    data = AppleWalletService.new(attendee: attendee, language: lang).pass_data
    send_data data,
              type: 'application/vnd.apple.pkpass',
              filename: "ticket-#{order.order_reference}.pkpass",
              disposition: 'attachment'
  rescue AppleWalletService::PassGenerationError => e
    Rails.logger.error("Apple Wallet error for #{order.order_reference}: #{e.message}")
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end

  def wallet_apple_attendee
    order = Order.find_by(order_reference: params[:order_reference])
    return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless order

    attendee = order.attendees
                    .includes(event: :events_translations)
                    .find_by(id: params[:id], user_id: current_user.id)
    return render json: { error: I18n.t('errors.not_found') }, status: :not_found unless attendee

    lang = current_user.language || 'ro-RO'
    data = AppleWalletService.new(attendee: attendee, language: lang).pass_data
    send_data data,
              type: 'application/vnd.apple.pkpass',
              filename: "ticket-#{order.order_reference}.pkpass",
              disposition: 'attachment'
  rescue AppleWalletService::PassGenerationError => e
    Rails.logger.error("Apple Wallet error for attendee #{attendee.id}: #{e.message}")
    render json: { error: 'Internal server error' }, status: :internal_server_error
  end
  ```

- [ ] **Step 2: Run request specs**

  ```bash
  bundle exec rspec spec/requests/api/v1/auth/me/bookings/apple_wallet_spec.rb --no-color
  ```

  Expected: all examples pass, 0 failures.

- [ ] **Step 3: Run the full test suite to catch regressions**

  ```bash
  bundle exec rspec --no-color 2>&1 | tail -5
  ```

  Expected: 0 failures.

- [ ] **Step 4: Commit**

  ```bash
  git add app/controllers/api/v1/auth/me/bookings_controller.rb \
          spec/requests/api/v1/auth/me/bookings/apple_wallet_spec.rb
  git commit -m "Add wallet_apple and wallet_apple_attendee controller actions"
  ```

---

## Task 9: Document ENV vars

**Files:**
- Create: `.env.example`

- [ ] **Step 1: Create `.env.example`**

  Create `.env.example` at the project root:

  ```bash
  # Database
  DATABASE_PORT=5432
  DATABASE_HOST=localhost
  DATABASE_USERNAME=postgres
  DATABASE_PASSWORD=postgres

  # Google Wallet
  GOOGLE_WALLET_ISSUER_ID=
  GOOGLE_WALLET_SERVICE_ACCOUNT_JSON=

  # Apple Wallet
  # Pass Type Identifier from your Apple Developer account (e.g. pass.io.yourapp.events)
  APPLE_WALLET_PASS_TYPE_ID=
  # 10-character Team ID from your Apple Developer account
  APPLE_WALLET_TEAM_ID=
  # Base64-encoded PEM certificate extracted from your Pass Type ID .p12:
  #   openssl pkcs12 -in Certificates.p12 -clcerts -nokeys | openssl x509 | base64 | tr -d '\n'
  APPLE_WALLET_CERTIFICATE=
  # Base64-encoded PEM private key extracted from your Pass Type ID .p12:
  #   openssl pkcs12 -in Certificates.p12 -nocerts -nodes | openssl rsa | base64 | tr -d '\n'
  APPLE_WALLET_PRIVATE_KEY=

  # Frontend
  FRONTEND_URL=
  ```

- [ ] **Step 2: Commit**

  ```bash
  git add .env.example
  git commit -m "Add .env.example with Apple Wallet credential vars and extraction commands"
  ```

---

## Implementation Complete

Run the full suite one final time:

```bash
bundle exec rspec --no-color 2>&1 | tail -5
```

Expected: 0 failures.

**Before going live, replace the placeholder images in `public/apple_wallet/` with real brand assets at the correct pixel dimensions (see spec for sizes), and provision the Pass Type ID certificate from Apple Developer once the membership is active.**
