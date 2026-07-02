# frozen_string_literal: true

module Api
  module V1
    module Auth
      class FacebooksController < ActionController::API
        include LocaleSetter
        include UserSerialisable

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

        # Return URL for the mobile apps' Facebook web OAuth flow: exchanges
        # the code server-side and bounces the access token into the app via
        # its deep link; the app finishes sign-in by POSTing it to #create.
        CALLBACK_URL = 'https://api-events.casatamplarului.ro/api/v1/auth/facebook/callback'

        def callback
          if params[:code].present?
            token = FacebookAuthService.exchange_code(params[:code], CALLBACK_URL)
            redirect_to "casatamplarului://facebook-signin?access_token=#{CGI.escape(token)}",
                        allow_other_host: true
          else
            redirect_to "casatamplarului://facebook-signin?error=#{CGI.escape(params[:error].presence || 'missing_code')}",
                        allow_other_host: true
          end
        rescue FacebookAuthService::InvalidTokenError => e
          redirect_to "casatamplarului://facebook-signin?error=#{CGI.escape(e.message)}",
                      allow_other_host: true
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
                  Attendee.backfill_user(email: facebook_data[:email], user_id: user.id)
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
              Attendee.backfill_user(email: facebook_data[:email], user_id: user.id) if facebook_data[:email].present?
              user
            end
          end
      end
    end
  end
end
