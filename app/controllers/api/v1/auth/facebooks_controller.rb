# frozen_string_literal: true

module Api
  module V1
    module Auth
      class FacebooksController < ActionController::API
        include LocaleSetter

        before_action :set_locale

        def create
          if params[:access_token].blank?
            render json: { error: I18n.t('auth.errors.access_token_required') }, status: :unprocessable_content
            return
          end

          facebook_data = FacebookAuthService.call(params[:access_token])
          user = find_or_create_user(facebook_data)
          jwt  = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue FacebookAuthService::InvalidTokenError
          render json: { error: I18n.t('auth.errors.invalid_facebook_token') }, status: :unauthorized
        rescue ActiveRecord::RecordNotUnique
          identity = UserIdentity.find_by(provider: 'facebook', uid: facebook_data&.dig(:uid))
          user     = identity&.user || User.find_by(email: facebook_data&.dig(:email))
          return render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized unless user

          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end

        private

          def find_or_create_user(facebook_data)
            identity = UserIdentity.find_by(provider: 'facebook', uid: facebook_data[:uid])
            return identity.user if identity

            if facebook_data[:email].present?
              user = User.find_by(email: facebook_data[:email])
              if user
                ActiveRecord::Base.transaction do
                  user.user_identities.create!(provider: 'facebook', uid: facebook_data[:uid])
                  user.update!(avatar_url: facebook_data[:avatar_url])
                  # rubocop:disable Rails/SkipsModelValidations
                  Attendee.where(email_address: facebook_data[:email]).update_all(user_id: user.id)
                  # rubocop:enable Rails/SkipsModelValidations
                end
                return user
              end
            end

            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: facebook_data[:first_name],
                last_name: facebook_data[:last_name],
                email: facebook_data[:email],
                avatar_url: facebook_data[:avatar_url]
              )
              user.user_identities.create!(provider: 'facebook', uid: facebook_data[:uid])
              if facebook_data[:email].present?
                # rubocop:disable Rails/SkipsModelValidations
                Attendee.where(email_address: facebook_data[:email]).update_all(user_id: user.id)
                # rubocop:enable Rails/SkipsModelValidations
              end
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
