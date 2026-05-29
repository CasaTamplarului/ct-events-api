# frozen_string_literal: true

module Api
  module V1
    module Auth
      class RegistrationsController < ActionController::API
        def create
          return missing_params_error unless required_params_present?
          return duplicate_email_error if User.exists?(email: normalized_email)

          user = register_user!
          jwt = JwtService.encode(user.id)
          render json: { jwt: jwt, user: user_json(user) }, status: :created
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.first }, status: :unprocessable_content
        rescue ActiveRecord::RecordNotUnique
          duplicate_email_error
        end

        private

          def required_params_present?
            params[:first_name].present? && params[:email].present? && params[:password].present?
          end

          def normalized_email
            @normalized_email ||= params[:email].to_s.strip.downcase
          end

          def register_user!
            ActiveRecord::Base.transaction do
              user = User.create!(
                first_name: params[:first_name],
                last_name: params[:last_name].presence,
                email: normalized_email,
                password: params[:password],
                phone_number: params[:phone_number].presence,
                church_name: params[:church_name].presence,
                city: params[:city].presence
              )
              user.user_identities.create!(provider: 'email', uid: user.email)
              # rubocop:disable Rails/SkipsModelValidations
              Attendee.where(email_address: user.email).update_all(user_id: user.id)
              # rubocop:enable Rails/SkipsModelValidations
              user
            end
          end

          def missing_params_error
            render json: { error: 'first_name, email, and password are required' }, status: :unprocessable_content
          end

          def duplicate_email_error
            render json: { error: 'Email is already registered' }, status: :conflict
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
              city: user.city
            }
          end
      end
    end
  end
end
