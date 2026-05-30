# frozen_string_literal: true

module Api
  module V1
    module Auth
      module Me
        class EmailPreferencesController < ActionController::API
          include Authenticatable

          before_action :authenticate_user!

          def update
            attrs = params.permit(*EmailUnsubscribeTokenService::PREFERENCE_COLUMNS).to_h
                          .transform_values { |v| ActiveRecord::Type::Boolean.new.cast(v) }

            if current_user.update(attrs)
              render json: { email_preferences: email_preferences_json(current_user) }
            else
              render json: { error: current_user.errors.full_messages.first }, status: :unprocessable_content
            end
          end

          private

            def email_preferences_json(user)
              EmailUnsubscribeTokenService::PREFERENCE_COLUMNS.index_with { |col| user.public_send(col) }
            end
        end
      end
    end
  end
end
