# frozen_string_literal: true

module Rack
  class Attack
    AUTH_ENDPOINTS = %w[/api/v1/auth/registration /api/v1/auth/session].freeze

    throttle('auth/ip', limit: 5, period: 1.minute) do |req|
      req.ip if AUTH_ENDPOINTS.include?(req.path) && req.post?
    end

    throttle('password_forgot/ip', limit: 3, period: 1.minute) do |req|
      req.ip if req.path == '/api/v1/auth/password/forgot' && req.post?
    end

    self.throttled_responder = lambda do |_env|
      body = { error: 'Too many requests. Please try again later.' }.to_json
      [429, { 'Content-Type' => 'application/json' }, [body]]
    end
  end
end
