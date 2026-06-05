# frozen_string_literal: true

module Api
  module V1
    module Auth
      module Me
        class PushPreferencesController < ActionController::API
          include Authenticatable

          before_action :authenticate_user!

          def update
            attrs = params.permit(*EmailUnsubscribeTokenService::PUSH_PREFERENCE_COLUMNS).to_h
                          .transform_values { |v| ActiveRecord::Type::Boolean.new.cast(v) }

            if current_user.update(attrs)
              render json: { push_preferences: push_preferences_json(current_user) }
            else
              render json: { error: current_user.errors.full_messages.first }, status: :unprocessable_content
            end
          end

          private

            def push_preferences_json(user)
              EmailUnsubscribeTokenService::PUSH_PREFERENCE_COLUMNS.index_with { |col| user.public_send(col) }
            end
        end
      end
    end
  end
end
