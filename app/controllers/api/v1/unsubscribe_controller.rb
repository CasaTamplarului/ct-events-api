# frozen_string_literal: true

module Api
  module V1
    class UnsubscribeController < ActionController::API
      def show
        data = EmailUnsubscribeTokenService.verify(params[:token].to_s)
        return redirect_to "#{frontend_url}?error=invalid_token", allow_other_host: true unless data

        user = User.active.find_by(id: data[:user_id])
        return redirect_to "#{frontend_url}?error=invalid_token", allow_other_host: true unless user

        if user.update(data[:type] => false)
          redirect_to "#{frontend_url}?type=#{data[:type]}", allow_other_host: true
        else
          redirect_to "#{frontend_url}?error=invalid_token", allow_other_host: true
        end
      end

      private

        def frontend_url
          "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3001')}/unsubscribed"
        end
    end
  end
end
