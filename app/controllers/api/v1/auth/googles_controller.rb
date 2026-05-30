# frozen_string_literal: true

module Api
  module V1
    module Auth
      class GooglesController < ActionController::API
        include LocaleSetter

        before_action :set_locale

        def create
          if params[:id_token].blank?
            render json: { error: I18n.t('auth.errors.id_token_required') }, status: :unprocessable_content
            return
          end

          google_data = GoogleAuthService.call(params[:id_token])
          user = find_or_create_user(google_data)
          jwt = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue GoogleAuthService::InvalidTokenError
          render json: { error: I18n.t('auth.errors.invalid_google_token') }, status: :unauthorized
        rescue ActiveRecord::RecordNotUnique
          identity = UserIdentity.find_by(provider: 'google', uid: google_data&.dig(:uid))
          user = identity&.user || User.find_by(email: google_data&.dig(:email))
          return render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized unless user

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

        private

          def find_or_create_user(google_data)
            identity = UserIdentity.find_by(provider: 'google', uid: google_data[:uid])
            return identity.user if identity

            user = User.find_by(email: google_data[:email])
            if user
              ActiveRecord::Base.transaction do
                user.user_identities.create!(provider: 'google', uid: google_data[:uid])
                user.update!(avatar_url: google_data[:avatar_url])
                # rubocop:disable Rails/SkipsModelValidations
                Attendee.backfill_user(email: google_data[:email], user_id: user.id)
                # rubocop:enable Rails/SkipsModelValidations
              end
              return user
            end

            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: google_data[:first_name],
                last_name: google_data[:last_name],
                email: google_data[:email],
                avatar_url: google_data[:avatar_url]
              )
              user.user_identities.create!(provider: 'google', uid: google_data[:uid])
              # rubocop:disable Rails/SkipsModelValidations
              Attendee.backfill_user(email: google_data[:email], user_id: user.id)
              # rubocop:enable Rails/SkipsModelValidations
              user
            end
          end

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
