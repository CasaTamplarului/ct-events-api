# frozen_string_literal: true

class TwilioService
  WHATSAPP_PREFIX = 'whatsapp:'

  def self.whatsapp_enabled?
    ENV['DISABLE_EMAILS'].to_s.downcase != 'true'
  end

  def self.send_whatsapp(to:, content_sid:, content_variables:)
    return unless whatsapp_enabled?

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
      to: "#{WHATSAPP_PREFIX}#{to}",
      content_sid: content_sid,
      content_variables: content_variables.to_json
    )
  rescue Twilio::REST::RestError => e
    Rails.logger.error("TwilioService WhatsApp error: #{e.message}")
  end
end
