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
  WWDR_CERT        = OpenSSL::X509::Certificate.new(File.read(WWDR_CERT_PATH)).freeze

  def initialize(attendee:, language:)
    @attendee     = attendee
    @language     = language
    @pass_type_id = ENV.fetch('APPLE_WALLET_PASS_TYPE_ID') { raise ArgumentError, 'APPLE_WALLET_PASS_TYPE_ID is not set' }
    @team_id      = ENV.fetch('APPLE_WALLET_TEAM_ID')      { raise ArgumentError, 'APPLE_WALLET_TEAM_ID is not set' }
    cert_pem      = Base64.strict_decode64(ENV.fetch('APPLE_WALLET_CERTIFICATE') { raise ArgumentError, 'APPLE_WALLET_CERTIFICATE is not set' })
    key_pem       = Base64.strict_decode64(ENV.fetch('APPLE_WALLET_PRIVATE_KEY')  { raise ArgumentError, 'APPLE_WALLET_PRIVATE_KEY is not set' })
    @certificate  = OpenSSL::X509::Certificate.new(cert_pem)
    @private_key  = OpenSSL::PKey::RSA.new(key_pem)
    @wwdr_cert    = WWDR_CERT
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
            { key: 'order', label: 'REFERINȚĂ COMANDĂ', value: @attendee.order&.order_reference.to_s }
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
