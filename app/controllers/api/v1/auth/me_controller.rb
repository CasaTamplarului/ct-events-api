# frozen_string_literal: true

module Api
  module V1
    module Auth
      class MeController < ActionController::API
        include Authenticatable

        before_action :authenticate_user!

        def show
          render json: {
            id: current_user.id,
            first_name: current_user.first_name,
            last_name: current_user.last_name,
            email: current_user.email,
            avatar_url: current_user.avatar_url,
            phone_number: current_user.phone_number,
            church_name: current_user.church_name,
            city: current_user.city
          }
        end
      end
    end
  end
end
