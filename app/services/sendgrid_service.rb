# frozen_string_literal: true

require 'rqrcode'
require 'chunky_png'

class SendgridService
  RESET_PASSWORD_TEMPLATE_ID       = 'd-952a77f57d9f410597cfa1cf84260cef'
  BOOKING_CONFIRMATION_TEMPLATE_ID = 'd-0276cfb6a8b54df996962912bb01cd71'

  def self.emails_enabled?
    ENV['DISABLE_EMAILS'].to_s.downcase != 'true'
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
                         .includes({ ticket: %i[tickets_translations ticket_meal_slots] },
                                   { event: [:events_translations,
                                             { event_template_docs: :event_template_doc_translations }] })
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
          'template_docs' => template_docs_data(event, language, group),
          'single_attendee' => single_attendee,
          'qr_content_id' => single_attendee ? "qr_code_#{group.first.id}" : nil,
          'qr_id_content_id' => single_attendee ? "qr_id_#{group.first.id}" : nil,
          'booking_url' => "#{ENV.fetch('FRONTEND_URL', nil)}/bookings/#{order.order_reference}",
          'frontend_url' => ENV.fetch('FRONTEND_URL', nil)
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

        if single_attendee
          attendee = group.first
          png = qr_with_logo(attendee.id.to_s)
          attachment = SendGrid::Attachment.new
          attachment.content     = Base64.strict_encode64(png)
          attachment.type        = 'image/png'
          attachment.filename    = "qr-id-#{attendee.id}.png"
          attachment.disposition = 'inline'
          attachment.content_id  = "qr_id_#{attendee.id}"
          mail.add_attachment(attachment)
        end

        response = client.client.mail._('send').post(request_body: mail.to_json)
        return if response.status_code.to_i.between?(200, 299)

        Rails.logger.error("SendGrid booking confirmation error: #{response.status_code} #{response.body}")
      end

      MEAL_EMOJIS = { 'breakfast' => '☀️', 'lunch' => '🥗', 'dinner' => '🍽️', 'snack' => '🍎' }.freeze
      MEAL_LABELS = {
        'ro' => { 'breakfast' => 'Mic dejun', 'lunch' => 'Prânz', 'dinner' => 'Cină', 'snack' => 'Gustare' },
        'en' => { 'breakfast' => 'Breakfast', 'lunch' => 'Lunch', 'dinner' => 'Dinner', 'snack' => 'Snack' }
      }.freeze
      LOGO_PATH = Rails.public_path.join('images/ct_logo_qr.png').freeze
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
          'meals_html' => meals_html(attendee.ticket&.ticket_meal_slots || [], lang),
          'google_wallet_url' => google_wallet_url(attendee, lang),
          'apple_wallet_url' => public_wallet_url(attendee, lang, 'apple')
        }
      end

      def google_wallet_url(attendee, lang)
        GoogleWalletService.new(attendee: attendee, language: lang).save_url
      rescue Exception => e # rubocop:disable Lint/RescueException
        Rails.logger.error("Google Wallet URL generation failed for attendee #{attendee.id}: #{e.message}")
        nil
      end

      def template_docs_data(event, lang, attendees)
        ages = attendees.map(&:age)
        event.event_template_docs
             .select { |doc| doc_applies_to_any_attendee?(doc, ages) }
             .map do |doc|
               label = doc.event_template_doc_translations.find { |t| t.languages_code == lang }&.label ||
                       doc.event_template_doc_translations.find { |t| t.languages_code == 'ro-RO' }&.label
               { 'label' => label, 'url' => ApplicationSerializer.asset_url(doc.directus_files_id) }
             end
      end

      def doc_applies_to_any_attendee?(doc, ages)
        return true if doc.age_from.nil? && doc.age_to.nil?

        ages.any? do |age|
          next false if age.nil?

          (doc.age_from.nil? || age >= doc.age_from) &&
            (doc.age_to.nil? || age <= doc.age_to)
        end
      end

      def public_wallet_url(attendee, lang, provider)
        base = ENV['API_BASE_URL']&.chomp('/')
        return nil if base.blank?

        order_ref = attendee.order&.order_reference
        return nil if order_ref.blank?

        "#{base}/api/v1/orders/#{order_ref}/attendees/#{attendee.id}/wallet/#{provider}?lang=#{lang}"
      end

      MEAL_P_STYLE = 'margin: 0 0 2px; font-size: 12px; color: #888; line-height: 1.4;'

      def meals_html(slots, lang)
        locale = lang.to_s.start_with?('ro') ? 'ro' : 'en'
        labels = MEAL_LABELS[locale]

        slots.sort_by { |s| [s.occurs_on, s.sort || 0] }
             .group_by(&:meal_type)
             .map do |meal_type, grouped|
          emoji = MEAL_EMOJIS[meal_type]
          label = labels[meal_type]
          count = grouped.size
          text  = count > 1 ? "#{emoji}&nbsp;#{label} × #{count}" : "#{emoji}&nbsp;#{label}"
          "<p style=\"#{MEAL_P_STYLE}\">#{text}</p>"
        end
             .join
      end
  end
end
