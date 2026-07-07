# frozen_string_literal: true

module Helpers
  def with_env(key, value)
    old = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = old
  end
end

RSpec.configure { |c| c.include Helpers }
