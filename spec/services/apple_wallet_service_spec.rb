# frozen_string_literal: true

require 'rails_helper'
require 'zip'

RSpec.describe AppleWalletService do
  subject(:service) { described_class.new(attendee: attendee, language: 'ro-RO') }

  let(:private_key) { OpenSSL::PKey::RSA.generate(2048) }
  let(:certificate) do
    cert = OpenSSL::X509::Certificate.new
    cert.version   = 2
    cert.serial    = 1
    cert.subject   = cert.issuer = OpenSSL::X509::Name.parse('/CN=Pass Type Test/OU=TESTTEAMID/O=Test/C=US')
    cert.public_key = private_key.public_key
    cert.not_before = Time.now
    cert.not_after  = Time.now + 3600
    cert.sign(private_key, OpenSSL::Digest.new('SHA256'))
    cert
  end

  let!(:language)    { Language.find_or_create_by!(code: 'ro-RO') { |l| l.name = 'Romanian' } }
  let(:event)        { create(:event, location_name: 'Casa Tâmplarului', start_date: 2.weeks.from_now) }
  let!(:translation) { create(:events_translation, event: event, languages_code: 'ro-RO', name: 'Gala de Vară') }
  let(:order)        { create(:order) }
  let(:attendee)     { create(:attendee, order: order, event: event, first_name: 'Ion', last_name: 'Popescu') }

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
