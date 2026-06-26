# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_user

    def connect
      self.current_user = find_verified_user
    end

    private

      def find_verified_user
        token = request.params[:token]
        return nil if token.blank?

        user_id = JwtService.decode(token)
        User.active.find_by(id: user_id)
      rescue JWT::DecodeError
        nil
      end
  end
end
