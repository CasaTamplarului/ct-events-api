# frozen_string_literal: true

require 'sendgrid-ruby'

class SendgridService
  RESET_PASSWORD_TEMPLATE_ID = 'd-952a77f57d9f410597cfa1cf84260cef'

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
    client.client.mail._('send').post(request_body: mail.to_json)
  end
end
