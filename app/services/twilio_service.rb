# frozen_string_literal: true

class TwilioService
  WHATSAPP_PREFIX = 'whatsapp:'

  def self.whatsapp_enabled?
    ENV['DISABLE_EMAILS'].to_s.downcase != 'true'
  end

  # Accepts numbers with or without leading '+' (e.g. "40757233708" → "+40757233708").
  # Returns nil for unparseable or structurally invalid numbers.
  def self.normalise_phone(raw)
    phone = Phonelib.parse(raw.to_s.strip)
    phone.valid? ? phone.e164 : nil
  end

  def self.send_whatsapp(to:, content_sid:, content_variables:)
    return unless whatsapp_enabled?

    normalised = normalise_phone(to)
    unless normalised
      Rails.logger.warn("TwilioService: invalid phone '#{to}' — skipping")
      return
    end

    account_sid = Rails.application.credentials.dig(:twilio, :account_sid)
    auth_token  = Rails.application.credentials.dig(:twilio, :auth_token)
    from_number = Rails.application.credentials.dig(:twilio, :whatsapp_from)

    if account_sid.blank? || auth_token.blank? || from_number.blank?
      Rails.logger.error('TwilioService: missing credentials — skipping send')
      return
    end

    client = Twilio::REST::Client.new(account_sid, auth_token)
    client.messages.create(
      from: from_number,
      to: "#{WHATSAPP_PREFIX}#{normalised}",
      content_sid: content_sid,
      content_variables: content_variables.to_json
    )
  rescue Twilio::REST::RestError => e
    Rails.logger.error("TwilioService WhatsApp error: #{e.message}")
  end
end
