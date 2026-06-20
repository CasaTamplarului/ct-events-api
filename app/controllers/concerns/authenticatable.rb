# frozen_string_literal: true

module Authenticatable
  extend ActiveSupport::Concern

  included do
    attr_reader :current_user
  end

  def authenticate_user!
    token = request.headers['Authorization']&.split&.last || params[:token]
    return render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized if token.blank?

    user_id = JwtService.decode(token)
    @current_user = User.active.find_by(id: user_id)
    render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized unless @current_user
  rescue JWT::DecodeError
    render json: { error: I18n.t('auth.errors.unauthorized') }, status: :unauthorized
  end

  def try_authenticate_user
    token = request.headers['Authorization']&.split&.last || params[:token]
    return if token.blank?

    user_id = JwtService.decode(token)
    @current_user = User.active.find_by(id: user_id)
  rescue JWT::DecodeError
    nil
  end

  def require_permission!(permission)
    return if current_user&.can?(permission)

    render json: { error: I18n.t('auth.errors.forbidden') }, status: :forbidden
  end

  def require_admin!
    return if current_user&.role == 'admin'

    render json: { error: I18n.t('auth.errors.forbidden') }, status: :forbidden
  end
end
