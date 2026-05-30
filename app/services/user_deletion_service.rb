# frozen_string_literal: true

class UserDeletionService
  def self.call(user)
    ActiveRecord::Base.transaction do
      # rubocop:disable Rails/SkipsModelValidations
      user.update_columns(
        deleted_at: Time.current,
        email: nil,
        first_name: 'Deleted',
        last_name: nil,
        avatar_url: nil,
        phone_number: nil,
        church_name: nil,
        city: nil,
        language: nil,
        password_digest: nil,
        password_reset_token: nil,
        password_reset_token_expires_at: nil
      )
      # rubocop:enable Rails/SkipsModelValidations
      user.user_identities.destroy_all
      user.passkeys.destroy_all
    end
  end
end
