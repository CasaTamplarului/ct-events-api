# frozen_string_literal: true

require 'rqrcode'

class SendgridService
  RESET_PASSWORD_TEMPLATE_ID       = 'd-952a77f57d9f410597cfa1cf84260cef'
  BOOKING_CONFIRMATION_TEMPLATE_ID = 'd-0276cfb6a8b54df996962912bb01cd71'

  def self.send_password_reset(user:, reset_url:)
    mail = SendGrid::Mail.new
    from_email = Rails.application.credentials.dig(:sendgrid, :from_email) || 'noreply@example.com'
    mail.from = SendGrid::Email.new(email: from_email)
    mail.template_id = RESET_PASSWORD_TEMPLATE_ID

    personalization = SendGrid::Personalization.new
    personalization.add_to(SendGrid::Email.new(email: user.email))
    personalization.add_dynamic_template_data(
      'is_romanian' => user.language&.start_with?('ro') || false,
      'first_name' => user.first_name,
      'reset_url' => reset_url,
      'year' => Time.current.year.to_s
    )
    mail.add_personalization(personalization)

    client = SendGrid::API.new(api_key: Rails.application.credentials.dig(:sendgrid, :api_key))
    response = client.client.mail._('send').post(request_body: mail.to_json)
    unless response.status_code.to_i.between?(200, 299)
      Rails.logger.error("SendGrid error: #{response.status_code} #{response.body}")
    end
  end

  def self.send_booking_confirmation(order:, language:)
    attendees = order.attendees
                     .includes({ ticket: :tickets_translations }, { event: :events_translations })
                     .reject { |a| a.email_address.blank? }

    return if attendees.empty?

    qr     = RQRCode::QRCode.new(order.order_reference)
    png    = qr.as_png(size: 300, border_modules: 4)
    qr_b64 = Base64.strict_encode64(png.to_s)

    from_email = Rails.application.credentials.dig(:sendgrid, :from_email) || 'noreply@example.com'
    client     = SendGrid::API.new(api_key: Rails.application.credentials.dig(:sendgrid, :api_key))

    attendees.group_by(&:email_address).each do |email_address, group|
      send_confirmation_to(
        email_address: email_address,
        group: group,
        order: order,
        language: language.to_s,
        qr_b64: qr_b64,
        from_email: from_email,
        client: client
      )
    end
  rescue StandardError => e
    Rails.logger.error("SendGrid booking confirmation error: #{e.message}")
  end

  class << self
    private

      def send_confirmation_to(email_address:, group:, order:, language:, qr_b64:, from_email:, client:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        event      = group.first.event
        event_name = event.events_translations.find { |t| t.languages_code == language }&.name ||
                     event.events_translations.find { |t| t.languages_code == 'ro-RO' }&.name

        mail = SendGrid::Mail.new
        mail.from        = SendGrid::Email.new(email: from_email)
        mail.template_id = BOOKING_CONFIRMATION_TEMPLATE_ID

        personalization = SendGrid::Personalization.new
        personalization.add_to(SendGrid::Email.new(email: email_address))
        personalization.add_dynamic_template_data(
          'is_romanian' => language.start_with?('ro'),
          'first_name' => group.first.first_name,
          'order_reference' => order.order_reference,
          'event_name' => event_name,
          'event_start_date' => event.start_date.strftime('%-d %B %Y'),
          'event_location' => event.location_name,
          'attendees' => group.map { |a| attendee_data(a, language) },
          'total_price' => group.sum { |a| a.ticket&.price || 0 },
          'is_pending' => group.first.payment_pending?,
          'year' => Time.current.year.to_s
        )
        mail.add_personalization(personalization)

        attachment = SendGrid::Attachment.new
        attachment.content     = qr_b64
        attachment.type        = 'image/png'
        attachment.filename    = 'booking-qr.png'
        attachment.disposition = 'inline'
        attachment.content_id  = 'qr_code'
        mail.add_attachment(attachment)

        response = client.client.mail._('send').post(request_body: mail.to_json)
        return if response.status_code.to_i.between?(200, 299)

        Rails.logger.error("SendGrid booking confirmation error: #{response.status_code} #{response.body}")
      end

      def attendee_data(attendee, lang) # rubocop:disable Metrics/CyclomaticComplexity
        translation = attendee.ticket&.tickets_translations&.find { |t| t.languages_code == lang } ||
                      attendee.ticket&.tickets_translations&.find { |t| t.languages_code == 'ro-RO' }
        {
          'first_name' => attendee.first_name,
          'last_name' => attendee.last_name,
          'ticket_name' => translation&.name,
          'ticket_description' => translation&.description,
          'ticket_price' => attendee.ticket&.price,
          'food_included' => attendee.ticket&.food_included
        }
      end
  end
end
