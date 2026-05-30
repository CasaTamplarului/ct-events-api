# frozen_string_literal: true

module Api
  module V1
    module Auth
      class PasswordsController < ActionController::API
        include LocaleSetter

        wrap_parameters false
        before_action :set_locale

        def forgot
          if params[:email].blank?
            render json: { error: I18n.t('auth.errors.email_required') }, status: :unprocessable_content
            return
          end

          user = User.find_by(email: params[:email].to_s.strip.downcase)
          if user
            token = SecureRandom.urlsafe_base64(32)
            # rubocop:disable Rails/SkipsModelValidations
            user.update_columns(
              password_reset_token: token,
              password_reset_token_expires_at: 1.hour.from_now
            )
            # rubocop:enable Rails/SkipsModelValidations
            reset_url = "#{ENV.fetch('FRONTEND_URL', nil)}/reset-password?token=#{token}"
            SendgridService.send_password_reset(user: user, reset_url: reset_url)
          end

          render json: { message: I18n.t('auth.messages.reset_link_sent') }, status: :ok
        end

        def reset
          if params[:token].blank? || params[:password].blank?
            render json: { error: I18n.t('auth.errors.token_password_required') }, status: :unprocessable_content
            return
          end

          user = User.find_by(password_reset_token: params[:token])

          if user.nil? || user.password_reset_token_expires_at.nil? ||
             user.password_reset_token_expires_at < Time.current
            render json: { error: I18n.t('auth.errors.invalid_reset_token') }, status: :unprocessable_content
            return
          end

          unless user.update(password: params[:password],
                             password_reset_token: nil,
                             password_reset_token_expires_at: nil)
            render json: { error: user.errors.full_messages.first }, status: :unprocessable_content
            return
          end

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

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
              can_change_email: user.user_identities.exists?(provider: 'email'),
              email_preferences: email_preferences_json(user)
            }
          end

          def email_preferences_json(user)
            EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.index_with { |col| user.public_send(col) }
          end
      end
    end
  end
end
