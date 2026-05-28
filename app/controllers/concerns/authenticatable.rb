# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user
  end

  def authenticate_user!
    token = request.headers['Authorization']&.split(' ')&.last
    return render json: { error: 'Unauthorized' }, status: :unauthorized if token.blank?

    user_id = JwtService.decode(token)
    @current_user = User.find_by(id: user_id)
    render json: { error: 'Unauthorized' }, status: :unauthorized unless @current_user
  rescue JWT::DecodeError
    render json: { error: 'Unauthorized' }, status: :unauthorized
  end
end
