# frozen_string_literal: true

class EmailUnsubscribeTokenService
  VERIFIER_SALT = :email_unsubscribe

  PREFERENCE_COLUMNS = %w[
    marketing_emails
    payment_reminder_emails
    payment_receipt_emails
    event_reminder_emails
    event_update_emails
  ].freeze

  def self.generate(user:, type:)
    raise ArgumentError, "Unknown preference type: #{type}" unless PREFERENCE_COLUMNS.include?(type.to_s)

    Rails.application.message_verifier(VERIFIER_SALT).generate(
      { user_id: user.id, type: type.to_s },
      expires_in: 90.days
    )
  end

  def self.verify(token)
    return nil if token.blank?

    data = Rails.application.message_verifier(VERIFIER_SALT).verify(token)
    return nil unless PREFERENCE_COLUMNS.include?(data['type'])

    # MessageVerifier deserializes as string-keyed Hash; normalize to symbols for callers
    { user_id: data['user_id'], type: data['type'] }
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end
end
