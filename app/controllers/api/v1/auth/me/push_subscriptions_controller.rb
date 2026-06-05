# frozen_string_literal: true

module Api
  module V1
    module Auth
      module Me
        class PushSubscriptionsController < ActionController::API
          include Authenticatable

          before_action :authenticate_user!

          def create
            sub = current_user.push_subscriptions.find_by(token: params[:token])

            if sub
              sub.update(device_name: params[:device_name])
              render json: { push_subscription: serialise(sub) }, status: :ok
            else
              sub = current_user.push_subscriptions.build(subscription_params)
              if sub.save
                render json: { push_subscription: serialise(sub) }, status: :created
              else
                render json: { error: sub.errors.full_messages.first }, status: :unprocessable_content
              end
            end
          end

          def destroy
            sub = current_user.push_subscriptions.find_by(id: params[:id])
            return head :not_found unless sub

            sub.destroy
            head :no_content
          end

          private

            def subscription_params
              params.permit(:token, :platform, :device_name)
            end

            def serialise(sub)
              { id: sub.id, token: sub.token, platform: sub.platform, device_name: sub.device_name }
            end
        end
      end
    end
  end
end
