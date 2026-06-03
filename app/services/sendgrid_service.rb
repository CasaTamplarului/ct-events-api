# frozen_string_literal: true

require 'rqrcode'
require 'chunky_png'

class SendgridService
  RESET_PASSWORD_TEMPLATE_ID       = 'd-952a77f57d9f410597cfa1cf84260cef'
  BOOKING_CONFIRMATION_TEMPLATE_ID = 'd-0276cfb6a8b54df996962912bb01cd71'

  def self.emails_enabled?
    ENV['DISABLE_EMAILS'].blank?
  end

  def self.send_password_reset(user:, reset_url:)
    return unless emails_enabled?

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

  def self.send_booking_confirmation(order:, language:) # rubocop:disable Metrics/CyclomaticComplexity
    return unless emails_enabled?

    all_attendees = order.attendees
                         .includes({ ticket: [:tickets_translations, :ticket_meal_slots] }, { event: :events_translations })
                         .to_a

    attendees_with_email = all_attendees.reject { |a| a.email_address.blank? }
    return if attendees_with_email.empty?

    from_email = Rails.application.credentials.dig(:sendgrid, :from_email) || 'noreply@example.com'
    client     = SendGrid::API.new(api_key: Rails.application.credentials.dig(:sendgrid, :api_key))

    attendees_with_email.group_by(&:email_address).each do |email_address, group|
      send_confirmation_to(
        email_address: email_address,
        group: group,
        order: order,
        all_attendees: all_attendees,
        language: language.to_s,
        from_email: from_email,
        client: client
      )
    end
  rescue StandardError => e
    Rails.logger.error("SendGrid booking confirmation error: #{e.message}")
  end

  class << self
    private

      def send_confirmation_to(email_address:, group:, order:, language:, from_email:, client:, all_attendees:) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        event      = group.first.event
        event_name = event.events_translations.find { |t| t.languages_code == language }&.name ||
                     event.events_translations.find { |t| t.languages_code == 'ro-RO' }&.name

        mail = SendGrid::Mail.new
        mail.from        = SendGrid::Email.new(email: from_email)
        mail.template_id = BOOKING_CONFIRMATION_TEMPLATE_ID

        personalization = SendGrid::Personalization.new
        personalization.add_to(SendGrid::Email.new(email: email_address))
        single_attendee = group.size == 1
        personalization.add_dynamic_template_data(
          'is_romanian' => language.start_with?('ro'),
          'first_name' => group.first.first_name,
          'order_reference' => order.order_reference,
          'event_name' => event_name,
          'event_start_date' => event.start_date.strftime('%-d %B %Y'),
          'event_location' => event.location_name,
          'attendees' => group.map { |a| attendee_data(a, language) },
          'total_price' => group.sum { |a| a.ticket&.price || 0 },
          'is_pending' => order.payment_pending?(all_attendees),
          'year' => Time.current.year.to_s,
          'single_attendee' => single_attendee,
          'qr_content_id' => single_attendee ? "qr_code_#{group.first.id}" : nil
        )
        mail.add_personalization(personalization)

        group.each do |attendee|
          png = qr_with_logo(attendee.qr_code)
          attachment = SendGrid::Attachment.new
          attachment.content     = Base64.strict_encode64(png)
          attachment.type        = 'image/png'
          attachment.filename    = "qr-#{attendee.id}.png"
          attachment.disposition = 'inline'
          attachment.content_id  = "qr_code_#{attendee.id}"
          mail.add_attachment(attachment)
        end

        response = client.client.mail._('send').post(request_body: mail.to_json)
        return if response.status_code.to_i.between?(200, 299)

        Rails.logger.error("SendGrid booking confirmation error: #{response.status_code} #{response.body}")
      end

      MEAL_EMOJIS = { 'breakfast' => '☀️', 'lunch' => '🥗', 'dinner' => '🍽️', 'snack' => '🍎' }.freeze
      MEAL_LABELS = {
        'ro' => { 'breakfast' => 'Mic dejun', 'lunch' => 'Prânz', 'dinner' => 'Cină', 'snack' => 'Gustare' },
        'en' => { 'breakfast' => 'Breakfast', 'lunch' => 'Lunch',  'dinner' => 'Dinner', 'snack' => 'Snack'    }
      }.freeze
      MONTH_ABBR_RO = %w[ian feb mar apr mai iun iul aug sep oct nov dec].freeze

      LOGO_PATH = Rails.root.join('public', 'images', 'ct_logo_qr.png').freeze
      QR_SIZE   = 300
      # Logo covers ~20% of QR area — safe with H-level error correction (30% recovery)
      LOGO_SIZE = (QR_SIZE * 0.20).to_i
      LOGO_PAD  = 5

      def qr_with_logo(text)
        qr_canvas = ChunkyPNG::Canvas.from_string(
          RQRCode::QRCode.new(text, level: :h).as_png(size: QR_SIZE, border_modules: 4).to_s
        )
        return qr_canvas.to_blob unless File.exist?(LOGO_PATH)

        logo = ChunkyPNG::Canvas.from_file(LOGO_PATH.to_s).resample_bilinear(LOGO_SIZE, LOGO_SIZE)

        bg = LOGO_SIZE + (LOGO_PAD * 2)
        bg_x = (QR_SIZE - bg) / 2
        bg_y = (QR_SIZE - bg) / 2
        bg.times { |dy| bg.times { |dx| qr_canvas[bg_x + dx, bg_y + dy] = ChunkyPNG::Color::WHITE } }

        qr_canvas.compose!(logo, (QR_SIZE - LOGO_SIZE) / 2, (QR_SIZE - LOGO_SIZE) / 2)
        qr_canvas.to_blob
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
          'food_included' => attendee.ticket&.food_included,
          'qr_content_id' => "qr_code_#{attendee.id}",
          'meal_slots' => format_meal_slots(attendee.ticket&.ticket_meal_slots || [], lang)
        }
      end

      def format_meal_slots(slots, lang)
        locale  = lang.to_s.start_with?('ro') ? 'ro' : 'en'
        labels  = MEAL_LABELS[locale]
        sorted  = slots.sort_by { |s| [s.occurs_on, s.sort || 0] }
        sorted.map do |s|
          date_label = if locale == 'ro'
                         "#{s.occurs_on.day} #{MONTH_ABBR_RO[s.occurs_on.month - 1]}"
                       else
                         s.occurs_on.strftime('%-d %b')
                       end
          { 'emoji' => MEAL_EMOJIS[s.meal_type], 'label' => labels[s.meal_type], 'date_label' => date_label }
        end
      end
  end
end
