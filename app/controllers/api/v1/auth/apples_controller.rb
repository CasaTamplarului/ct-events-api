# frozen_string_literal: true

module Api
  module V1
    module Auth
      class ApplesController < ActionController::API
        include LocaleSetter
        include UserSerialisable

        before_action :set_locale

        def create
          if params[:id_token].blank?
            render json: { error: I18n.t('auth.errors.id_token_required') },
                   status: :unprocessable_content
            return
          end

          apple_data = AppleAuthService.call(params[:id_token])
          user = find_or_create_user(apple_data)
          jwt  = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue AppleAuthService::InvalidTokenError
          render json: { error: I18n.t('auth.errors.invalid_apple_token') },
                 status: :unauthorized
        rescue ActiveRecord::RecordNotUnique
          identity = UserIdentity.find_by(provider: 'apple', uid: apple_data&.dig(:uid))
          user     = identity&.user || User.find_by(email: apple_data&.dig(:email))
          unless user
            return render json: { error: I18n.t('auth.errors.unauthorized') },
                          status: :unauthorized
          end

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

        private

          def find_or_create_user(apple_data)
            identity = UserIdentity.find_by(provider: 'apple', uid: apple_data[:uid])
            return identity.user if identity

            user = User.find_by(email: apple_data[:email])
            if user
              ActiveRecord::Base.transaction do
                user.user_identities.create!(provider: 'apple', uid: apple_data[:uid])
                Attendee.backfill_user(email: apple_data[:email], user_id: user.id)
              end
              return user
            end

            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: apple_data[:first_name],
                last_name: apple_data[:last_name],
                email: apple_data[:email]
              )
              user.user_identities.create!(provider: 'apple', uid: apple_data[:uid])
              Attendee.backfill_user(email: apple_data[:email], user_id: user.id)
              user
            end
          end
      end
    end
  end
end
