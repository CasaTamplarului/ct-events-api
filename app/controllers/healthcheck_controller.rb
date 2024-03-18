# frozen_string_literal: true

class HealthcheckController < ActionController::API
  def index
    render json: { message: 'ok' }
  end
end
