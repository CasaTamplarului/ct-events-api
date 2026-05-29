# frozen_string_literal: true

module Api
  module V1
    module Auth
      class MeController < ActionController::API
        include Authenticatable
        include LocaleSetter

        before_action :authenticate_user!
        before_action :set_locale

        def show
          render json: user_json(current_user)
        end

        def update
          if params[:email].present? && !email_identity?
            render json: { error: I18n.t('auth.errors.email_not_changeable_google') }, status: :unprocessable_content
            return
          end

          permitted = params.permit(:first_name, :last_name, :phone_number, :church_name, :city, :language, :email)

          if current_user.update(permitted)
            render json: user_json(current_user)
          else
            render json: { error: current_user.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        def password
          unless email_identity?
            render json: { error: I18n.t('auth.errors.password_not_changeable_google') }, status: :unprocessable_content
            return
          end

          if params[:current_password].blank? || params[:password].blank?
            render json: { error: I18n.t('auth.errors.current_password_required') }, status: :unprocessable_content
            return
          end

          unless current_user.authenticate(params[:current_password])
            render json: { error: I18n.t('auth.errors.incorrect_current_password') }, status: :unauthorized
            return
          end

          if current_user.update(password: params[:password])
            render json: { jwt: JwtService.encode(current_user.id), user: user_json(current_user) }
          else
            render json: { error: current_user.errors.full_messages.first }, status: :unprocessable_content
          end
        end

        private

          def email_identity?
            current_user.user_identities.exists?(provider: 'email')
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
