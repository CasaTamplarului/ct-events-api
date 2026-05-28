# frozen_string_literal: true

module Api
  module V1
    module Auth
      class GooglesController < ActionController::API
        def create
          return render json: { error: 'id_token is required' }, status: :unprocessable_entity if params[:id_token].blank?

          google_data = GoogleAuthService.call(params[:id_token])
          user = find_or_create_user(google_data)
          jwt = JwtService.encode(user.id)

          render json: { jwt: jwt, user: user_json(user) }, status: :ok
        rescue GoogleAuthService::InvalidTokenError
          render json: { error: 'Invalid Google token' }, status: :unauthorized
        end

        private

        def find_or_create_user(google_data)
          identity = UserIdentity.find_by(provider: 'google', uid: google_data[:uid])
          return identity.user if identity

          user = User.find_by(email: google_data[:email])
          if user
            user.user_identities.create!(provider: 'google', uid: google_data[:uid])
            user.update(avatar_url: google_data[:avatar_url])
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
            Attendee.where(email_address: google_data[:email]).update_all(user_id: user.id)
            user
          end
        end

        def user_json(user)
          {
            id: user.id,
            first_name: user.first_name,
            last_name: user.last_name,
            email: user.email,
            avatar_url: user.avatar_url
          }
        end
      end
    end
  end
end
