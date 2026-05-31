# frozen_string_literal: true

module Api
  module V1
    module Auth
      class SessionsController < ActionController::API
        include LocaleSetter
        include UserSerialisable

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

          Attendee.backfill_user(email: user.email, user_id: user.id)
          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        end
      end
    end
  end
end
