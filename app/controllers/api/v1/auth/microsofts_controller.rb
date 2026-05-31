# frozen_string_literal: true

module Api
  module V1
    module Auth
      class MicrosoftsController < ActionController::API
        include LocaleSetter
        include UserSerialisable

        before_action :set_locale

        def create
          if params[:id_token].blank?
            render json: { error: I18n.t('auth.errors.id_token_required') }, status: :unprocessable_content
            return
          end

          microsoft_data = MicrosoftAuthService.call(params[:id_token])
          user = find_or_create_user(microsoft_data)
          jwt  = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue MicrosoftAuthService::InvalidTokenError
          render json: { error: I18n.t('auth.errors.invalid_microsoft_token') }, status: :unauthorized
        rescue ActiveRecord::RecordNotUnique
          identity = UserIdentity.find_by(provider: 'microsoft', uid: microsoft_data&.dig(:uid))
          user     = identity&.user || User.find_by(email: microsoft_data&.dig(:email))
          return render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized unless user

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

        private

          def find_or_create_user(microsoft_data)
            identity = UserIdentity.find_by(provider: 'microsoft', uid: microsoft_data[:uid])
            return identity.user if identity

            user = User.find_by(email: microsoft_data[:email])
            if user
              ActiveRecord::Base.transaction do
                user.user_identities.create!(provider: 'microsoft', uid: microsoft_data[:uid])
                user.update!(avatar_url: microsoft_data[:avatar_url])
                Attendee.backfill_user(email: microsoft_data[:email], user_id: user.id)
              end
              return user
            end

            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: microsoft_data[:first_name],
                last_name: microsoft_data[:last_name],
                email: microsoft_data[:email],
                avatar_url: microsoft_data[:avatar_url]
              )
              user.user_identities.create!(provider: 'microsoft', uid: microsoft_data[:uid])
              Attendee.backfill_user(email: microsoft_data[:email], user_id: user.id)
              user
            end
          end
      end
    end
  end
end
