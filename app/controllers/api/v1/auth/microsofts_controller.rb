# frozen_string_literal: true

module Api
  module V1
    module Auth
      class MicrosoftsController < ActionController::API
        include LocaleSetter

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
                # rubocop:disable Rails/SkipsModelValidations
                Attendee.where(email_address: microsoft_data[:email]).update_all(user_id: user.id)
                # rubocop:enable Rails/SkipsModelValidations
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
              # rubocop:disable Rails/SkipsModelValidations
              Attendee.where(email_address: microsoft_data[:email]).update_all(user_id: user.id)
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
              can_change_email: user.user_identities.exists?(provider: 'email')
            }
          end
      end
    end
  end
end
