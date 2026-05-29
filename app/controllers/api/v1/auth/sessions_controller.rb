# frozen_string_literal: true

module Api
  module V1
    module Auth
      class SessionsController < ActionController::API
        include LocaleSetter

        before_action :set_locale

        def create
          if params[:email].blank? || params[:password].blank?
            render json: { error: I18n.t('auth.errors.email_password_required') }, status: :unprocessable_content
            return
          end

          user = User.find_by(email: params[:email].to_s.strip.downcase)
          authenticated = user&.authenticate(params[:password])

          unless authenticated
            render json: { error: I18n.t('auth.errors.invalid_credentials') }, status: :unauthorized
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
              language: user.language
            }
          end
      end
    end
  end
end
