# frozen_string_literal: true

module Api
  module V1
    # Device registration for the mobile apps. Auth is optional: signed-in
    # requests attach the subscription to the user (all channels); anonymous
    # devices only receive marketing broadcasts. Rows are upserted by token,
    # so signing in later claims a previously anonymous device.
    class PushSubscriptionsController < ActionController::API
      before_action :set_current_user

      def create
        return render json: { error: 'token required' }, status: :unprocessable_content if params[:token].blank?

        sub = PushSubscription.find_or_initialize_by(token: params[:token])
        sub.platform    = params[:platform].presence || sub.platform || 'android'
        sub.device_name = params[:device_name].presence || sub.device_name
        sub.user        = @current_user if @current_user

        if sub.save
          render json: { push_subscription: { id: sub.id, platform: sub.platform } }, status: :ok
        else
          render json: { error: sub.errors.full_messages.first }, status: :unprocessable_content
        end
      end

      def destroy
        sub = PushSubscription.find_by(token: params[:token])
        sub&.destroy
        head :no_content
      end

      private

        def set_current_user
          token = request.headers['Authorization']&.split&.last
          return if token.blank?

          user_id = JwtService.decode(token)
          @current_user = User.active.find_by(id: user_id)
        rescue JWT::DecodeError
          nil
        end
    end
  end
end
