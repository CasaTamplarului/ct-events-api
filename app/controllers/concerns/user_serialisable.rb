# frozen_string_literal: true

module UserSerialisable
  private

    def user_json(user)
      {
        id: user.id,
        first_name: user.first_name,
        last_name: user.last_name,
        email: user.email,
        avatar_url: user.avatar_url,
        phone_number: user.phone_number,
        church_name: user.church_name,
        city: user.city,
        language: user.language,
        role: user.role,
        permissions: User::ROLE_PERMISSIONS[user.role],
        can_change_email: user.user_identities.exists?(provider: 'email'),
        email_preferences: email_preferences_json(user)
      }
    end

    def email_preferences_json(user)
      EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.index_with { |col| user.public_send(col) }
    end
end
